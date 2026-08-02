import 'package:intl/intl.dart';

/// WhatsApp/Telegram-style: today's time, "Yesterday", or a short date for
/// anything older. Shared between the friends list subtitle and the
/// per-friend call history screen.
String formatCallTimestamp(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(dt.year, dt.month, dt.day);
  final diffDays = today.difference(that).inDays;
  if (diffDays == 0) return DateFormat.Hm().format(dt);
  if (diffDays == 1) return 'Yesterday';
  return DateFormat.MMMd().format(dt);
}

/// e.g. "14:32 (3) Outgoing" / "Yesterday Incoming" / "Aug 1 (2) Outgoing".
/// The call count only shows in parentheses when there's more than one.
String formatLastCallSubtitle({
  required DateTime? lastCallAt,
  required bool? lastCallOutgoing,
  required int callCount,
}) {
  if (lastCallAt == null) return 'No calls yet';
  final ts = formatCallTimestamp(lastCallAt);
  final countPart = callCount > 1 ? ' ($callCount)' : '';
  final direction = lastCallOutgoing == true ? 'Outgoing' : 'Incoming';
  return '$ts$countPart  $direction';
}
