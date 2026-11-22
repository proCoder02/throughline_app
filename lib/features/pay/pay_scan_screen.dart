import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme.dart';
import 'pay_confirm_screen.dart';
import 'upi_link.dart';

/// Scan & Pay: reads a UPI QR code (camera, a gallery screenshot, or a
/// typed UPI ID) and hands it to PayConfirmScreen. Separate from Meet's
/// MeetQrScreen on purpose -- its own controller, disposed with the screen,
/// so the two never compete for the camera.
class PayScanScreen extends StatefulWidget {
  const PayScanScreen({super.key});

  @override
  State<PayScanScreen> createState() => _PayScanScreenState();
}

class _PayScanScreenState extends State<PayScanScreen> {
  static const _frame = 250.0;

  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _handled = false;
  DateTime _lastWarning = DateTime.fromMillisecondsSinceEpoch(0);

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
      MaterialPageRoute(builder: (_) => PayConfirmScreen(link: link)),
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
