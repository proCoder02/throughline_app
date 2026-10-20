/// Best-effort file-extension -> MIME type -- good enough for R2's content
/// type and for picking the right upload purpose (image/video/file); a
/// wrong guess for an obscure document extension only affects how a
/// browser treats the download, never whether the upload/send itself
/// works (the backend's chat_file purpose accepts any content type -- see
/// storage.py). Shared by direct_message_screen.dart (DM file
/// attachments) and email_draft_card.dart (claim/email draft
/// attachments).
String guessMimeType(String path) {
  final ext = path.split('.').last.toLowerCase();
  const map = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif',
    'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm',
    'pdf': 'application/pdf', 'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'txt': 'text/plain', 'zip': 'application/zip',
  };
  return map[ext] ?? 'application/octet-stream';
}
