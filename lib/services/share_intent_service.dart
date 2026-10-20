import 'dart:async';
import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Wraps receive_sharing_intent so callers don't need to know the plugin's
/// own API shape. Two separate paths, not one, because they have genuinely
/// different timing:
///
/// - `init(onImageShared)` -- the app is ALREADY RUNNING (foreground or
///   backgrounded) when a share arrives. Called once from main(), same as
///   PushService's live onMessage/onMessageOpenedApp listeners -- auth is
///   already resolved and the Navigator under navigatorKey already exists,
///   so pushing a route immediately is safe.
/// - `consumePendingSharedImage()` -- the app was COLD-STARTED by the share
///   (Throughline wasn't already open). Must NOT push a route the instant
///   this resolves: at that point authProvider.bootstrap() may still be
///   mid-flight (reading the stored token from secure storage is async),
///   so an immediate `if (!authProvider.isAuthenticated)` check can read
///   false for an actually-logged-in user and silently drop the share --
///   confirmed live (share sheet opened the app to a bare Home screen,
///   receipt never attached). Fixed the same way this codebase already
///   solves the identical cold-start race for notification taps
///   (consumePendingTaskAction/consumePendingDigestOpen in this same file's
///   neighbor, push_service.dart): a one-shot read-and-clear pull, called
///   from HomeShell._bootstrap() -- which only ever runs once auth has
///   already resolved to authenticated, since HomeShell can't mount
///   otherwise. See home_shell.dart's _bootstrap() for the pull site.
///
/// Only handles images, matching AndroidManifest.xml's SEND intent-filter
/// (mimeType image/*) -- anything else the OS might still hand over
/// (SharedMediaType.text/file/etc., if a future intent-filter widens this)
/// is ignored here rather than mis-routed into the image-share flow.
class ShareIntentService {
  ShareIntentService._();
  static final instance = ShareIntentService._();

  StreamSubscription<List<SharedMediaFile>>? _subscription;

  File? _firstSharedImage(List<SharedMediaFile> files) {
    final image = files.firstWhere(
      (f) => f.type == SharedMediaType.image,
      orElse: () => SharedMediaFile(path: '', type: SharedMediaType.text),
    );
    return image.path.isEmpty ? null : File(image.path);
  }

  void init(void Function(File image) onImageShared) {
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      final image = _firstSharedImage(files);
      if (image != null) onImageShared(image);
    }, onError: (_) {});
  }

  /// Read-once-and-clear, same pull pattern as push_service.dart's
  /// consumePendingTaskAction -- a cold-start share is a one-shot getter,
  /// so it must be explicitly acknowledged via reset() once consumed, or
  /// the same file re-delivers on the next getInitialMedia() call (e.g.
  /// after a hot restart in debug).
  Future<File?> consumePendingSharedImage() async {
    final files = await ReceiveSharingIntent.instance.getInitialMedia();
    ReceiveSharingIntent.instance.reset();
    return _firstSharedImage(files);
  }

  void dispose() => _subscription?.cancel();
}
