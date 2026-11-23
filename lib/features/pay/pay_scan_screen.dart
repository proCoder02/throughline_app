import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme.dart';
import 'pay_api.dart';
import 'pay_confirm_screen.dart';
import 'upi_link.dart';

/// Scan & Pay: reads a UPI QR code (camera, a gallery screenshot, or a
/// typed UPI ID) and hands it to PayConfirmScreen. Separate from Meet's
/// MeetQrScreen on purpose -- its own controller, disposed with the screen,
/// so the two never compete for the camera.
class PayScanScreen extends StatefulWidget {
  /// Scanning to pay a specific promise ("Send Ravi 500 for the tickets"):
  /// shown as a banner, and carried into the confirm screen.
  final OwedItem? paying;

  const PayScanScreen({super.key, this.paying});

  @override
  State<PayScanScreen> createState() => _PayScanScreenState();
}

class _PayScanScreenState extends State<PayScanScreen> {
  static const _frame = 250.0;

  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _handled = false;
  DateTime _lastWarning = DateTime.fromMillisecondsSinceEpoch(0);
  OwedItem? _paying;
  PaySnapshot _snap = PaySnapshot.empty;

  @override
  void initState() {
    super.initState();
    _paying = widget.paying;
    // Last-known list first (instant), then the network.
    _snap = PayApi.instance.cached();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await PayApi.instance.refresh();
      if (mounted) setState(() => _snap = s);
    } catch (_) {
      // Offline or an older server: the camera works exactly as before.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final code in capture.barcodes) {
      final link = UpiLink.tryParse(code.rawValue);
      if (link != null) {
        _open(link);
        return;
      }
    }
    // A QR, just not a UPI one -- say so, but not on every camera frame.
    if (capture.barcodes.isNotEmpty &&
        DateTime.now().difference(_lastWarning) > const Duration(seconds: 3)) {
      _lastWarning = DateTime.now();
      _toast("That isn't a UPI payment code");
    }
  }

  Future<void> _pickFromGallery() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    BarcodeCapture? capture;
    try {
      capture = await _controller.analyzeImage(image.path);
    } catch (_) {
      capture = null;
    }
    if (!mounted) return;
    for (final code in capture?.barcodes ?? const <Barcode>[]) {
      final link = UpiLink.tryParse(code.rawValue);
      if (link != null) {
        _open(link);
        return;
      }
    }
    _toast('No UPI payment code found in that image');
  }

  Future<void> _enterUpiId() async {
    final controller = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay a UPI ID'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'name@bank'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Continue')),
        ],
      ),
    );
    controller.dispose();
    if (id == null || !mounted) return;
    final link = UpiLink.tryParse('upi://pay?pa=${Uri.encodeComponent(id.trim())}');
    if (link == null) {
      _toast("That doesn't look like a UPI ID (e.g. name@okaxis)");
      return;
    }
    _open(link, haptic: false);
  }

  void _open(UpiLink link, {bool haptic = true}) {
    if (_handled) return;
    _handled = true;
    if (haptic) HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PayConfirmScreen(link: link, owed: _paying)),
    );
  }

  UpiLink? _linkFor(String vpa, String? name) => UpiLink.tryParse(
      'upi://pay?pa=${Uri.encodeComponent(vpa)}${name == null ? '' : '&pn=${Uri.encodeComponent(name)}'}');

  /// A promise from "You owe": straight to the confirm screen when we know
  /// the person's UPI ID, otherwise keep scanning with it as the context.
  void _payOwed(OwedItem item) {
    Navigator.of(context).pop(); // the sheet
    setState(() => _paying = item);
    final link = item.suggestedVpa == null ? null : _linkFor(item.suggestedVpa!, item.suggestedName);
    if (link != null) {
      _open(link, haptic: false);
      return;
    }
    _toast('Scan ${item.person ?? 'their'} UPI QR to pay this');
  }

  void _payAgain(RecentPayee p) {
    Navigator.of(context).pop();
    final link = _linkFor(p.vpa, p.name);
    if (link != null) _open(link, haptic: false);
  }

  Future<void> _dismiss(OwedItem item) async {
    setState(() => _snap = PaySnapshot(_snap.owed.where((o) => o.taskId != item.taskId).toList(), _snap.recent));
    try {
      await PayApi.instance.dismiss(item.taskId);
    } catch (_) {}
  }

  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dmBubbleIn,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _PaySheet(
        snap: _snap,
        onPayOwed: _payOwed,
        onPayAgain: _payAgain,
        onDismiss: (o) {
          Navigator.of(ctx).pop();
          _dismiss(o);
        },
      ),
    );
  }

  Widget _topOverlay() {
    final paying = _paying;
    if (paying != null) {
      final amount = paying.amount == null ? '' : ' \u20b9${_fmt(paying.amount!)}';
      final reason = paying.reason == null ? '' : ' \u00b7 ${paying.reason}';
      return Material(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              const Icon(Icons.handshake_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Paying ${paying.person ?? 'a promise'}$amount$reason',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Not paying this now',
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () => setState(() => _paying = null),
              ),
            ],
          ),
        ),
      );
    }
    if (_snap.owed.isEmpty && _snap.recent.isEmpty) return const SizedBox.shrink();
    final label = _snap.owed.isNotEmpty ? 'You owe \u00b7 ${_snap.owed.length}' : 'Pay again';
    return Center(
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.6),
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 44),
          shape: const StadiumBorder(),
        ),
        onPressed: _openSheet,
        icon: Icon(_snap.owed.isNotEmpty ? Icons.handshake_outlined : Icons.history, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Scan & Pay'),
        actions: [
          // Torch icon mirrors the real torch state (visibility of status).
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (_, state, __) {
              final on = state.torchState == TorchState.on;
              if (state.torchState == TorchState.unavailable) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                tooltip: on ? 'Turn torch off' : 'Turn torch on',
                onPressed: () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (_, __) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Camera unavailable. Allow camera access for Throughline in Settings, or use a gallery screenshot or UPI ID below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSoft),
                ),
              ),
            ),
          ),
          // Dim everything outside the frame so the eye goes to the target.
          ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.55), BlendMode.srcOut),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(decoration: const BoxDecoration(color: Colors.transparent, backgroundBlendMode: BlendMode.dstOut)),
                Center(
                  child: Container(
                    width: _frame,
                    height: _frame,
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: Container(
              width: _frame,
              height: _frame,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.dmAccent, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
            child: _topOverlay(),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: MediaQuery.of(context).size.height / 2 + _frame / 2 + 20,
            child: const Text(
              'Point at any UPI QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  children: [
                    Expanded(child: _bottomAction(Icons.photo_library_outlined, 'Gallery', _pickFromGallery)),
                    const SizedBox(width: 12),
                    Expanded(child: _bottomAction(Icons.alternate_email, 'UPI ID', _enterUpiId)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomAction(IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.16),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// "You owe" (money promised in conversations) and "Pay again" (people and
/// shops paid before), one tap to the confirm screen.
class _PaySheet extends StatelessWidget {
  final PaySnapshot snap;
  final void Function(OwedItem) onPayOwed;
  final void Function(RecentPayee) onPayAgain;
  final void Function(OwedItem) onDismiss;

  const _PaySheet({required this.snap, required this.onPayOwed, required this.onPayAgain, required this.onDismiss});

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: AppColors.dmTextSoft)),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.dmBubbleBorder, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          if (snap.owed.isNotEmpty) ...[
            _label('You owe'),
            for (final o in snap.owed)
              Card(
                color: AppColors.dmPillFill,
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                  title: Text(o.title, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.dmText)),
                  subtitle: Text(
                    [o.text, if (o.sourceTitle != null) 'From: ${o.sourceTitle}', if (o.due != null) 'Due ${o.due}'].join('\n'),
                    style: TextStyle(color: AppColors.dmTextSoft, fontSize: 13),
                  ),
                  isThreeLine: true,
                  onTap: () => onPayOwed(o),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (o.amount != null)
                        Text('\u20b9${_fmt(o.amount!)}',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.dmText)),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        icon: Icon(Icons.more_vert, color: AppColors.dmTextSoft),
                        onSelected: (_) => onDismiss(o),
                        itemBuilder: (_) => const [PopupMenuItem(value: 'dismiss', child: Text('Not money I owe'))],
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (snap.recent.isNotEmpty) ...[
            _label('Pay again'),
            for (final p in snap.recent)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: CircleAvatar(
                  backgroundColor: AppColors.dmPillFill,
                  child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                      style: TextStyle(color: AppColors.dmText, fontWeight: FontWeight.w700)),
                ),
                title: Text(p.name, style: TextStyle(color: AppColors.dmText, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Last \u20b9${_fmt(p.lastAmount)}${p.lastNote == null ? '' : ' \u00b7 ${p.lastNote}'}',
                  style: TextStyle(color: AppColors.dmTextSoft, fontSize: 13),
                ),
                onTap: () => onPayAgain(p),
              ),
          ],
          if (snap.owed.isEmpty && snap.recent.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Nothing owed right now.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.dmTextSoft)),
            ),
        ],
      ),
    );
  }
}
