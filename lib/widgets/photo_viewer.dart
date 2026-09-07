import 'package:flutter/material.dart';

/// WhatsApp-style full-screen profile-picture viewer -- pinch-to-zoom via
/// InteractiveViewer, dismiss by tapping the backdrop, the close button, or
/// the system back gesture/button. Call sites should only invoke this when
/// a real photo exists (InitialAvatar's initials-only fallback has nothing
/// worth viewing full-screen) -- see direct_message_screen.dart's and
/// friend_profile_screen.dart's avatar taps for the two current call sites.
void showPhotoViewer(BuildContext context, {required String imageUrl}) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    pageBuilder: (context, animation, __) => FadeTransition(
      opacity: animation,
      child: _PhotoViewerScreen(imageUrl: imageUrl),
    ),
  ));
}

class _PhotoViewerScreen extends StatelessWidget {
  final String imageUrl;

  const _PhotoViewerScreen({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  // Swallows the tap so tapping the photo itself (as opposed
                  // to the surrounding backdrop) doesn't dismiss the viewer.
                  child: GestureDetector(
                    onTap: () {},
                    child: Image.network(imageUrl, fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                top: 4, right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
