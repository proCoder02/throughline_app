import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';

import '../../theme.dart';
import '../../widgets/avatar.dart';
import 'meet_api.dart';
import 'meet_card_editor.dart';
import 'meet_card_view.dart';
import 'meet_history_screen.dart';
import 'meet_models.dart';
import 'meet_proximity.dart';

enum _Phase { loading, unavailable, needsCard, blocked, searching, confirming, waitingForThem, shared, ended, failed }

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
  int? _nearest;
  bool _reporting = false;
  bool _actionBusy = false;
  final Set<int> _dismissed = {}; // encounters already finished on this screen

  StreamSubscription<String>? _touchSub;
  StreamSubscription<int?>? _nearestSub;
  Timer? _rotateTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _touchSub = _proximity.touches.listen(_onTouch);
    _nearestSub = _proximity.nearestSignal.listen((v) {
      if (mounted && v != _nearest) setState(() => _nearest = v);
    });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotateTimer?.cancel();
    _pollTimer?.cancel();
    _touchSub?.cancel();
    _nearestSub?.cancel();
    _proximity.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopRadio();
    } else if (state == AppLifecycleState.resumed && (_phase == _Phase.searching || _phase == _Phase.blocked)) {
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
    _set(_Phase.searching);
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
    await _proximity.stop();
    if (mounted && _nearest != null) setState(() => _nearest = null);
  }

  // ---- touching ----

  Future<void> _onTouch(String seenCode) async {
    final session = _session;
    if (_phase != _Phase.searching || _reporting || session == null) return;
    _reporting = true;
    try {
      final r = await _api.reportTouch(myCode: session.code, seenCode: seenCode);
      switch (r.status) {
        case 'matched':
          final enc = r.encounter;
          if (enc == null || _dismissed.contains(enc.id) || _phase != _Phase.searching) break;
          HapticFeedback.mediumImpact();
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
        if (_phase != _Phase.shared) HapticFeedback.mediumImpact();
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
      body: SafeArea(
        child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _body()),
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
      case _Phase.blocked:
        return _blockedNotice();
      case _Phase.searching:
        return _searching();
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
          "This phone can't send a Bluetooth signal, so other phones won't notice it. Sharing by QR code is coming next.",
          'Try again'
        ),
      MeetBlockReason.notResponding => (
          "Bluetooth isn't responding",
          'Bluetooth on this phone took too long to answer. Turning Bluetooth off and on again usually fixes it.',
          'Try again'
        ),
      _ => ("Bluetooth isn't available", "This device doesn't support Bluetooth.", 'Try again'),
    };
    return _Notice(key: const ValueKey('blocked'), icon: Icons.bluetooth_disabled, title: title, body: body, action: action, onAction: _fixBlocked);
  }

  Widget _searching() {
    final threshold = _session?.rssiThreshold ?? -40;
    final near = _nearest;
    final hint = near == null
        ? 'Looking for another phone with Meet open…'
        : near >= threshold
            ? 'Hold still…'
            : 'Found a phone -- bring them closer';
    return ListView(
      key: const ValueKey('searching'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        const SizedBox(height: 12),
        _Pulse(active: near != null),
        const SizedBox(height: 28),
        Text('Hold your phones together',
            textAlign: TextAlign.center, style: appHeadlineFont(color: AppColors.text, fontSize: 24)),
        const SizedBox(height: 10),
        Text(
          'Keep Meet open on both phones and bring them back to back. Your card is shared only if you both tap Share.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSoft, height: 1.4),
        ),
        const SizedBox(height: 20),
        Text(hint, textAlign: TextAlign.center, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          near == null ? 'Signal: none yet' : 'Signal: $near dBm (touch at $threshold)',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSoft, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        if (_mine != null) ...[
          const SizedBox(height: 32),
          Text('YOUR CARD',
              style: TextStyle(color: AppColors.textSoft, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          MeetCardView(card: _mine!.card, person: _mine!.me),
        ],
      ],
    );
  }

  Widget _confirm() {
    final enc = _encounter!;
    final waiting = _phase == _Phase.waitingForThem;
    return ListView(
      key: const ValueKey('confirm'),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
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
          MeetCardView(card: card, person: enc.other)
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

  const _Notice({super.key, required this.icon, required this.title, required this.body, this.action, this.onAction});

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
          ],
        ),
      ),
    );
  }
}

/// Concentric rings that breathe faster once another phone is in range.
class _Pulse extends StatefulWidget {
  final bool active;

  const _Pulse({required this.active});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void didUpdateWidget(covariant _Pulse old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      _c.duration = Duration(milliseconds: widget.active ? 1100 : 2400);
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: 160,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            if (!reduceMotion)
              for (final offset in const [0.0, 0.33, 0.66])
                Builder(builder: (_) {
                  final t = (_c.value + offset) % 1.0;
                  return Container(
                    width: 64 + 96 * t,
                    height: 64 + 96 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent.withValues(alpha: (1 - t) * 0.6), width: 2),
                    ),
                  );
                }),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
              child: const Icon(Icons.contactless_outlined, color: Colors.white, size: 32),
            ),
          ],
        ),
      ),
    );
  }
}
