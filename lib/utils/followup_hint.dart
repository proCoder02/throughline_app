/// Whether a global-chat message leans on earlier turns ("and what did he
/// say?", "the second one", "which company?") -- only to pick the waiting
/// text, so a slightly longer wait for a follow-up reads as intended. A
/// loose mirror of the server's resolver gate (chat_followup.needs_resolution
/// in speech2text); getting it wrong only changes a label, never what the
/// server does. Same rule as the web client's lib/followup.js.
final _followUp = RegExp(
  r'^\s*(?:and|also|plus|then|so|what about|how about|same)\b'
  r'|\b(?:he|him|his|she|her|hers|they|them|their|it|that|this|those|these|there|one|ones|'
  r'first|second|third|last|latest|previous|earlier|same|again|else|instead)\b',
  caseSensitive: false,
);

const followUpPendingLabel = 'Checking what we talked about…';

bool looksLikeFollowUp(String text, {required bool hasEarlierReplies}) {
  final t = text.trim();
  if (t.isEmpty || !hasEarlierReplies) return false;
  return _followUp.hasMatch(t) || t.split(RegExp(r'\s+')).length <= 5;
}
