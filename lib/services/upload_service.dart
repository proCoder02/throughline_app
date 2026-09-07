import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;

import 'api_client.dart';

/// Presigned-URL direct upload to Cloudflare R2 -- see MEDIA_STORAGE_PLAN.md.
/// The Flask backend never receives the file bytes, only a short-lived PUT
/// URL (POST /uploads/presign). `purpose` is one of
/// 'profile_picture'|'chat_image'|'chat_video'|'chat_file' (storage.py's
/// _PURPOSES), which the caller derives from the picked file's MIME type.
class UploadService {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> status() async {
    final r = await _api.dio.get('/uploads/status');
    return Map<String, dynamic>.from(r.data);
  }

  Future<String> uploadFile(
    File file,
    String purpose,
    String contentType, {
    void Function(double)? onProgress,
  }) async {
    final presign = await _api.dio.post('/uploads/presign', data: {
      'purpose': purpose,
      'content_type': contentType,
    });
    final uploadUrl = presign.data['upload_url'] as String;
    final objectKey = presign.data['object_key'] as String;

    // A separate plain Dio instance (not ApiClient.instance) -- this PUT
    // goes straight to R2, not this app's own backend, and must NOT carry
    // the app's Bearer auth header.
    await Dio().put(
      uploadUrl,
      data: file.openRead(),
      options: Options(
        headers: {Headers.contentLengthHeader: await file.length(), 'Content-Type': contentType},
      ),
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
    );
    return objectKey;
  }

  Future<String> confirmUpload(String objectKey, String purpose) async {
    final r = await _api.dio.post('/uploads/confirm', data: {'object_key': objectKey, 'purpose': purpose});
    return r.data['public_url'] as String;
  }

  /// Profile pictures go through a dedicated route instead of the generic
  /// confirmUpload() above -- POST /profile/picture both confirms the R2
  /// object AND persists the URL onto the user's own row (also cleaning up
  /// their previous picture's object). confirmUpload() alone only validates
  /// the object and hands back its public URL; it never touches the
  /// database, so calling it here instead of this route -- as this app
  /// briefly did -- looked fine in the moment (AuthProvider patches
  /// in-memory state immediately) but silently never persisted anything,
  /// so the picture vanished on the next app restart's /me refetch. Mirrors
  /// the web client's SettingsSection, which always posts here directly.
  Future<String> confirmProfilePicture(String objectKey) async {
    final r = await _api.dio.post('/profile/picture', data: {'object_key': objectKey});
    return r.data['profile_picture_url'] as String;
  }

  /// Downscaled, low-quality JPEG as a base64 data: URL -- sent inline with
  /// the message itself (see DirectMessage.thumbnailDataUrl), never
  /// uploaded to R2. `imageSource` is any already-decodable image file; for
  /// video, pass a captured frame instead of the raw video bytes.
  Future<String> makeThumbnailDataUrl(File imageSource, {int maxWidth = 160}) async {
    final bytes = await imageSource.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image for thumbnail');
    final width = maxWidth < decoded.width ? maxWidth : decoded.width;
    final resized = img.copyResize(decoded, width: width);
    final jpeg = img.encodeJpg(resized, quality: 50);
    return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
  }
}
