import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../theme.dart';
import '../../widgets/avatar.dart';
import 'meet_animations.dart';
import 'meet_api.dart';
import 'meet_card_editor.dart';
import 'meet_card_view.dart';
import 'meet_haptics.dart';
import 'meet_history_screen.dart';
import 'meet_models.dart';
import 'meet_proximity.dart';
import 'meet_qr_screen.dart';

enum _Phase { loading, unavailable, needsCard, primer, blocked, searching, paused, confirming, waitingForThem, shared, ended, failed }

/// No one nearby for this long -> stop Bluetooth and ask "Still looking?".
const _idleLimit = Duration(minutes: 3);

/// Hold two phones together -> both people see "Share your card with X?"
/// -> once both tap Share, each sees the other's card.
///
/// Bluetooth runs only while this screen is open and in the foreground.
class MeetScreen extends StatefulWidget {
  const MeetScreen({super.key});

  @override
  State<MeetScreen> createState() => _MeetScreenState();
}

class _MeetScreenState extends State<MeetScreen> with WidgetsBindingObserver {
  final _api = MeetApi();
  final _proximity = MeetProximity();

  _Phase _phase = _Phase.loading;
  MyMeetCard? _mine;
  MeetSession? _session;
  MeetBlockReason? _blocked;
  MeetEncounter? _encounter;
  String? _message;
  MeetSignal _signal = MeetSignal.none;
  bool _reporting = false;
  bool _actionBusy = false;
  final Set<int> _dismissed = {}; // encounters already finished on this screen
  bool _primerSeen = false; // explained Bluetooth before Android's prompt
  DateTime _lastActivity = DateTime.now(); // last time another phone was heard (or searching began)

  StreamSubscription<MeetTouch>? _touchSub;
  StreamSubscription<MeetSignal>? _signalSub;
  Timer? _rotateTimer;
  Timer? _pollTimer;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A sleeping screen stops Bluetooth and the touch silently fails, so
    // Meet keeps the screen on while it's open.
    WakelockPlus.enable();
    _touchSub = _proximity.touches.listen(_onTouch);
    _signalSub = _proximity.signal.listen((v) {
      if (!mounted) return;
      // A light tick the moment another phone comes into range.
      if (v.rssi != null) _lastActivity = DateTime.now();
      if (_phase == _Phase.searching) {
        if (_signal.rssi == null && v.rssi != null) MeetHaptics.detected();
        if (_signal.hold < 1 && v.hold >= 1) MeetHaptics.touched();
      }
      if (v.rssi != _signal.rssi || (v.hold - _signal.hold).abs() > 0.01) setState(() => _signal = v);
    });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotateTimer?.cancel();
    _pollTimer?.cancel();
    _idleTimer?.cancel();
    WakelockPlus.disable();
    _touchSub?.cancel();
    _signalSub?.cancel();
    _proximity.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      WakelockPlus.disable();
      _stopRadio();
    } else if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
    }
    if (state == AppLifecycleState.resumed && (_phase == _Phase.searching || _phase == _Phase.blocked)) {
      _begin();
    }
  }

  void _set(_Phase phase, {String? message}) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  // ---- setup ----

  Future<void> _load() async {
    _set(_Phase.loading);
    try {
      _mine = await _api.myCard();
    } on MeetUnavailable {
      _set(_Phase.unavailable);
      return;
    } catch (_) {
      _set(_Phase.failed, message: "Couldn't reach Throughline. Check your connection.");
      return;
    }
    if (!_mine!.saved || !_mine!.card.sharing) {
      _set(_Phase.needsCard);
      return;
    }
    await _begin();
  }

  Future<void> _editCard() async {
    final mine = _mine;
    if (mine == null) return;
    await _stopRadio();
    if (!mounted) return;
    final saved = await Navigator.of(context).push<MeetCard>(
      MaterialPageRoute(builder: (_) => MeetCardEditorScreen(initial: mine)),
    );
    if (saved != null) _mine = MyMeetCard(saved: true, card: saved, me: mine.me);
    if (!mounted) return;
    if (_mine!.saved && _mine!.card.sharing) {
      await _begin();
    } else {
      _set(_Phase.needsCard);
    }
  }

  Future<void> _begin() async {
    // Say why Bluetooth is needed BEFORE Android asks -- only when the
    // prompt would actually appear.
    if (!_primerSeen && !await _proximity.permissionGranted()) {
      _set(_Phase.primer);
      return;
    }
    _set(_Phase.loading, message: 'Starting Bluetooth…');
    await _stopRadio();
    try {
      await _proximity.preflight();
      debugPrint('[meet] starting session...');
      _session = await _api.startSession().timeout(const Duration(seconds: 15));
      await _proximity.start(_session!);
    } on MeetBlocked catch (b) {
      await _stopRadio();
      if (mounted) setState(() => _blocked = b.reason);
      _set(_Phase.blocked);
      return;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] == 'card_required') {
        _set(_Phase.needsCard);
      } else {
        _set(_Phase.failed, message: "Couldn't start Meet. Check your connection and try again.");
      }
      return;
    } on TimeoutException {
      await _stopRadio();
      _set(_Phase.failed, message: "Couldn't reach Throughline in time. Check your connection and try again.");
      return;
    } catch (e) {
      debugPrint('[meet] start failed: $e');
      await _stopRadio();
      _set(_Phase.failed, message: "Couldn't start Bluetooth on this phone.");
      return;
    }
    _rotateTimer?.cancel();
    _rotateTimer = Timer.periodic(_session!.rotateAfter, (_) => _rotate());
    _lastActivity = DateTime.now();
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkIdle());
    _set(_Phase.searching);
  }

  /// Saves battery (and stops broadcasting from someone's pocket) when no
  /// one has been nearby for a while.
  Future<void> _checkIdle() async {
    if (_phase != _Phase.searching || DateTime.now().difference(_lastActivity) < _idleLimit) return;
    await _stopRadio();
    _set(_Phase.paused);
  }

  void _primerContinue() {
    _primerSeen = true;
    _begin();
  }

  /// QR fallback -- Bluetooth is paused while the QR screen is open.
  Future<void> _openQr() async {
    await _stopRadio();
    if (!mounted) return;
    final enc = await Navigator.of(context).push<MeetEncounter>(
      MaterialPageRoute(builder: (_) => const MeetQrScreen()),
    );
    if (!mounted) return;
    if (enc != null && !_dismissed.contains(enc.id)) {
      MeetHaptics.matched();
      _encounter = enc;
      _set(enc.isShared ? _Phase.shared : _Phase.confirming);
      _startPolling();
    } else {
      _begin();
    }
  }

  Future<void> _rotate() async {
    try {
      final next = await _api.startSession();
      await _proximity.rotate(next);
      _session = next;
    } catch (e) {
      debugPrint('[meet] rotate failed: $e'); // the old code stays valid for a few more minutes
    }
  }

  Future<void> _stopRadio() async {
    _rotateTimer?.cancel();
    _rotateTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    await _proximity.stop();
    if (mounted && _signal.rssi != null) setState(() => _signal = MeetSignal.none);
  }

  // ---- touching ----

  Future<void> _onTouch(MeetTouch touch) async {
    final session = _session;
    if (_phase != _Phase.searching || _reporting || session == null) return;
    _reporting = true;
    try {
      debugPrint('[meet] touch at ${touch.rssi} dBm (threshold ${session.rssiThreshold})');
      final r = await _api.reportTouch(myCode: session.code, touch: touch);
      switch (r.status) {
        case 'matched':
          final enc = r.encounter;
          if (enc == null || _dismissed.contains(enc.id) || _phase != _Phase.searching) break;
          MeetHaptics.matched();
          _encounter = enc;
          _set(enc.isShared ? _Phase.shared : _Phase.confirming);
          _startPolling();
        case 'invalid':
          await _rotate();
        case 'limited':
          _set(_Phase.ended, message: r.error ?? 'Too many meetings in the last hour. Try again later.');
          await _stopRadio();
      }
    } catch (e) {
      debugPrint('[meet] report failed: $e');
    } finally {
      _reporting = false;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    final enc = _encounter;
    if (enc == null) return;
    try {
      final next = await _api.encounter(enc.id);
      if (!mounted || _encounter?.id != next.id) return;
      setState(() => _encounter = next);
      if (next.isShared) {
        _pollTimer?.cancel();
        if (_phase != _Phase.shared) MeetHaptics.revealed();
        _set(_Phase.shared);
      } else if (next.isFinished) {
        _pollTimer?.cancel();
        _dismissed.add(next.id);
        _set(_Phase.ended, message: switch (next.status) {
          'declined' => next.iConfirmed ? '${next.other.name} chose not to share this time.' : 'Not shared.',
          'expired' => 'That took too long. Hold your phones together to try again.',
          _ => 'Sharing stopped.',
        });
      }
    } catch (e) {
      debugPrint('[meet] poll failed: $e');
    }
  }

  Future<void> _answer(bool accept) async {
    final enc = _encounter;
    if (enc == null || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final next = await _api.confirm(enc.id, accept: accept);
      if (!mounted) return;
      setState(() => _encounter = next);
      if (!accept) {
        _pollTimer?.cancel();
        _dismissed.add(enc.id);
        _backToSearching();
      } else if (next.isShared) {
        _pollTimer?.cancel();
        MeetHaptics.revealed();
        _set(_Phase.shared);
      } else {
        _set(_Phase.waitingForThem);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't send that. Try again.")));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _addFriend() async {
    final enc = _encounter;
    if (enc == null || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await _api.addFriend(enc.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You and ${enc.other.name} are now friends.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't add them as a friend. Try again.")));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// Ends the share for both people -- same as Stop sharing in People
  /// you've met, offered right on the card too.
  Future<void> _stopSharing() async {
    final enc = _encounter;
    if (enc == null || _actionBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop sharing with ${enc.other.name}?'),
        content: const Text("You'll both lose access to each other's cards."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop sharing')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await _api.remove(enc.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stopped sharing with ${enc.other.name}.')));
      _backToSearching();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't stop sharing. Try again.")));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _backToSearching() {
    final enc = _encounter;
    if (enc != null) _dismissed.add(enc.id);
    _pollTimer?.cancel();
    _encounter = null;
    if (_session != null && _rotateTimer != null) {
      _set(_Phase.searching);
    } else {
      _begin();
    }
  }

  // ---- fixes for a blocked start ----

  Future<void> _fixBlocked() async {
    switch (_blocked) {
      case MeetBlockReason.bluetoothOff:
        if (Platform.isAndroid) {
          try {
            await FlutterBluePlus.turnOn(timeout: 15);
          } catch (_) {}
        }
      case MeetBlockReason.locationOff:
        await Geolocator.openLocationSettings();
        return; // resumed() restarts once they come back
      case MeetBlockReason.permissionDenied:
        await Geolocator.openAppSettings();
        return;
      default:
        break;
    }
    await _begin();
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        backgroundColor: AppColors.bgApp,
        title: const Text('Meet'),
        actions: [
          if (_mine?.saved == true)
            IconButton(icon: const Icon(Icons.badge_outlined), tooltip: 'Edit your card', onPressed: _editCard),
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: "People you've met",
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MeetHistoryScreen())),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _body()),
          ),
          if (_phase == _Phase.searching)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: EdgeGlow(level: signalLevel(_signal.rssi, _session?.rssiThreshold ?? -40)),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.loading:
        return Center(
          key: const ValueKey('loading'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!, style: TextStyle(color: AppColors.textSoft)),
              ],
            ],
          ),
        );
      case _Phase.unavailable:
        return const _Notice(
          key: ValueKey('unavailable'),
          icon: Icons.contactless_outlined,
          title: "Meet isn't switched on yet",
          body: "This feature hasn't been turned on for your account. Check back soon.",
        );
      case _Phase.failed:
        return _Notice(
          key: const ValueKey('failed'),
          icon: Icons.cloud_off_outlined,
          title: 'Something went wrong',
          body: _message ?? '',
          action: 'Try again',
          onAction: _load,
        );
      case _Phase.needsCard:
        return _Notice(
          key: const ValueKey('needsCard'),
          icon: Icons.badge_outlined,
          title: _mine?.saved == true ? 'Your card is switched off' : 'Set up your card first',
          body: _mine?.saved == true
              ? 'Turn sharing on to swap cards with people you meet.'
              : 'Your card is what people see when you meet. You choose everything on it.',
          action: _mine?.saved == true ? 'Edit card' : 'Set up my card',
          onAction: _editCard,
        );
      case _Phase.primer:
        return _Notice(
          key: const ValueKey('primer'),
          icon: Icons.contactless_outlined,
          title: 'Meet uses Bluetooth',
          body: 'To notice when your phone touches theirs. Only a random code that changes every few minutes is sent -- '
              'never your name, your details or where you are. Android will ask for permission next.',
          action: 'Continue',
          onAction: _primerContinue,
        );
      case _Phase.blocked:
        return _blockedNotice();
      case _Phase.searching:
        return _searching();
      case _Phase.paused:
        return _Notice(
          key: const ValueKey('paused'),
          icon: Icons.pause_circle_outline,
          title: 'Still looking?',
          body: 'No one was nearby for a few minutes, so Meet paused to save battery.',
          action: 'Keep looking',
          onAction: _begin,
          secondary: 'Use a QR code instead',
          onSecondary: _openQr,
        );
      case _Phase.confirming:
      case _Phase.waitingForThem:
        return _confirm();
      case _Phase.shared:
        return _shared();
      case _Phase.ended:
        return _Notice(
          key: const ValueKey('ended'),
          icon: Icons.info_outline,
          title: 'Not shared',
          body: _message ?? '',
          action: 'Back',
          onAction: _backToSearching,
        );
    }
  }

  Widget _blockedNotice() {
    final (title, body, action) = switch (_blocked) {
      MeetBlockReason.bluetoothOff => ('Turn on Bluetooth', 'Meet uses Bluetooth to notice when two phones are touching.', 'Turn on Bluetooth'),
      MeetBlockReason.locationOff => (
          'Turn on Location',
          'On this version of Android, phones only find nearby Bluetooth devices while Location is on. Meet never reads or sends where you are.',
          'Open Location settings'
        ),
      MeetBlockReason.permissionDenied => (
          'Allow nearby devices',
          'Meet needs permission to use Bluetooth. Only a random code is sent -- never your name or details.',
          'Open app settings'
        ),
      MeetBlockReason.cannotBroadcast => (
          "This phone can't broadcast",
          "This phone can't send a Bluetooth signal, so other phones won't notice it. Use a QR code instead.",
          'Try again'
        ),
      MeetBlockReason.notResponding => (
          "Bluetooth isn't responding",
          'Bluetooth on this phone took too long to answer. Turning Bluetooth off and on again usually fixes it.',
          'Try again'
        ),
      _ => ("Bluetooth isn't available", "This device doesn't support Bluetooth.", 'Try again'),
    };
    return _Notice(
      key: const ValueKey('blocked'),
      icon: Icons.bluetooth_disabled,
      title: title,
      body: body,
      action: action,
      onAction: _fixBlocked,
      secondary: 'Use a QR code instead',
      onSecondary: _openQr,
    );
  }

  Widget _searching() {
    final threshold = _session?.rssiThreshold ?? -40;
    final near = _signal.rssi;
    final hint = near == null
        ? 'Looking for a phone with Meet open…'
        : near >= threshold
            ? 'Hold still…'
            : 'Bring them closer';
    // One focal point (the orb), one title, one live status line. The card
    // itself is one tap away (app bar), and the signal number only goes to
    // the log -- it's for tuning, not for the person meeting someone.
    return Center(
      key: const ValueKey('searching'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProximityOrb(level: signalLevel(near, threshold), hold: _signal.hold),
            const SizedBox(height: 28),
            Text('Hold your phones together',
                textAlign: TextAlign.center, style: appHeadlineFont(color: AppColors.text, fontSize: 24)),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(hint,
                  key: ValueKey(hint),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSoft, fontSize: 15)),
            ),
            const SizedBox(height: 40),
            TextButton.icon(
              onPressed: _openQr,
              icon: const Icon(Icons.qr_code_2, size: 18),
              label: const Text('Use a QR code instead'),
            ),
            const SizedBox(height: 4),
            Text(
              'Only shared if you both tap Share',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSoft, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirm() {
    final enc = _encounter!;
    final waiting = _phase == _Phase.waitingForThem;
    final left = enc.secondsLeft();
    return ListView(
      key: const ValueKey('confirm'),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
        if (_mine != null)
          MergeAvatars(me: _mine!.me, them: enc.other)
        else
          Center(child: InitialAvatar(name: enc.other.name, imageUrl: enc.other.photo, size: 96)),
        const SizedBox(height: 20),
        Text(waiting ? 'Waiting for ${enc.other.name}…' : 'You met ${enc.other.name}',
            textAlign: TextAlign.center, style: appHeadlineFont(color: AppColors.text, fontSize: 24)),
        const SizedBox(height: 10),
        Text(
          waiting
              ? "You've shared. Their card appears as soon as they share too."
              : enc.theyConfirmed
                  ? '${enc.other.name} has shared their card. Share yours to see it.'
                  : 'Share your card with ${enc.other.name}? You will see theirs once you both share.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSoft, height: 1.4),
        ),
        if (left != null) ...[
          const SizedBox(height: 14),
          Text(
            left > 0 ? '${left}s left to share' : 'Time is up',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: left <= 15 ? AppColors.danger : AppColors.textSoft,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        const SizedBox(height: 28),
        if (waiting)
          const Center(child: CircularProgressIndicator())
        else ...[
          FilledButton(
            onPressed: _actionBusy ? null : () => _answer(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size.fromHeight(48)),
            child: const Text('Share my card'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _actionBusy ? null : () => _answer(false),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Not now'),
          ),
        ],
      ],
    );
  }

  Widget _shared() {
    final enc = _encounter!;
    final card = enc.card;
    return ListView(
      key: const ValueKey('shared'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (card != null)
          CardReveal(child: MeetCardView(card: card, person: enc.other))
        else
          _Notice(
            icon: Icons.visibility_off_outlined,
            title: '${enc.other.name} switched their card off',
            body: "You've both shared, but they've since turned their card off.",
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _actionBusy ? null : _addFriend,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size.fromHeight(48)),
          label: const Text('Add friend'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _backToSearching,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Done'),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _actionBusy ? null : _stopSharing,
          icon: const Icon(Icons.link_off, size: 18),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size.fromHeight(44)),
          label: const Text('Stop sharing'),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  final String? secondary;
  final VoidCallback? onSecondary;

  const _Notice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
    this.secondary,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: appHeadlineFont(color: AppColors.text, fontSize: 20)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft, height: 1.4)),
            if (action != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                child: Text(action!),
              ),
            ],
            if (secondary != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondary!)),
            ],
          ],
        ),
      ),
    );
  }
}
