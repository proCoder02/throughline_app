import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';
import '../services/outlook_service.dart';
import '../theme.dart';

/// Shown under a global-chat reply that used the Outlook tools: what the
/// assistant actually did ("Searched your mailbox for …") and the emails it
/// drew on, each opening in Outlook -- so a mail answer is visibly grounded
/// and checkable, never indistinguishable from a guess. Mirrors the web
/// client's MailReplyMeta.jsx.
class MailReplyMeta extends StatefulWidget {
  final Map<String, dynamic> meta;

  const MailReplyMeta({super.key, required this.meta});

  @override
  State<MailReplyMeta> createState() => _MailReplyMetaState();
}

class _MailReplyMetaState extends State<MailReplyMeta> {
  static const _visibleSources = 3;
  bool _expanded = false;

  List<Map> _list(String key) => ((widget.meta[key] as List?) ?? const []).whereType<Map>().toList();

  Future<void> _reconnect() async {
    try {
      await OutlookService().connect();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start Outlook sign-in: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = _list('tool_activity');
    final sources = _list('mail_sources');
    if (activity.isEmpty && sources.isEmpty) return const SizedBox.shrink();
    final shown = _expanded ? sources : sources.take(_visibleSources).toList();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.dmBubbleBorder))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in activity) _ActivityLine(activity: a, onReconnect: _reconnect),
          if (sources.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                'SOURCES',
                style: TextStyle(color: AppColors.dmTextSoft, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
              ),
            ),
            for (final s in shown) _SourceTile(source: s),
            if (sources.length > _visibleSources)
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.dmAccent,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show fewer' : 'Show all ${sources.length}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActivityLine extends StatelessWidget {
  final Map activity;
  final VoidCallback onReconnect;

  const _ActivityLine({required this.activity, required this.onReconnect});

  @override
  Widget build(BuildContext context) {
    final isError = activity['error'] == true;
    final color = isError ? AppColors.danger : AppColors.dmTextSoft;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.warning_amber_rounded : Icons.mail_outline_rounded, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${activity['label'] ?? ''}', style: TextStyle(color: color, fontSize: 12.5, height: 1.35)),
          ),
          if (isError)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.dmAccent,
              ),
              onPressed: onReconnect,
              child: const Text('Reconnect', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final Map source;

  const _SourceTile({required this.source});

  static String _senderName(String? from) {
    // "Name <addr>" -> "Name"; a bare address stays as-is.
    final match = RegExp(r'^(.*?)\s*<[^>]+>$').firstMatch(from ?? '');
    final name = (match != null ? match.group(1) : from) ?? '';
    return name.isEmpty ? 'Unknown sender' : name;
  }

  static String _shortDate(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    return sameDay ? DateFormat.Hm().format(d) : DateFormat.MMMd().format(d);
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await OutlookStatus.openEmail(source['web_link'] as String?);
    final subject = '${source['subject'] ?? ''}';
    switch (result) {
      case OpenedEmail.appInbox:
        // Outlook opened, but on its inbox -- say which email to look for.
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('Opened Outlook -- look for “${subject.isEmpty ? '(no subject)' : subject}” '
              'from ${_senderName(source['from'] as String?)}.'),
        ));
      case OpenedEmail.failed:
        messenger.showSnackBar(const SnackBar(content: Text("Couldn't open that email.")));
      case OpenedEmail.exact:
      case OpenedEmail.browser:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final opened = source['read'] == true;
    final subject = '${source['subject'] ?? ''}'.isEmpty ? '(no subject)' : '${source['subject']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.black.withValues(alpha: isAppDarkMode ? 0.16 : 0.035),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          // Always tappable: even without a webLink, the Outlook app itself
          // can still be opened (see OutlookStatus.openEmail).
          onTap: () => _open(context),
          child: Semantics(
            button: true,
            label: '${_senderName(source['from'] as String?)}, $subject, opens in Outlook',
            excludeSemantics: true,
            child: Container(
              // 48dp-ish row height -- a comfortable thumb target.
              constraints: const BoxConstraints(minHeight: 46),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.dmBubbleBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _senderName(source['from'] as String?),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.dmText, fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (opened)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.dmAccent),
                                ),
                                child: const Text('Opened',
                                    style: TextStyle(color: AppColors.dmAccent, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            const SizedBox(width: 6),
                            Text(_shortDate(source['received'] as String?),
                                style: TextStyle(color: AppColors.dmTextSoft, fontSize: 11.5)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.dmTextSoft, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.open_in_new_rounded, size: 15, color: AppColors.dmTextSoft),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Try with your inbox" chips for the global chat -- only once Outlook is
/// connected and usable, so nobody is offered something that can't work.
class MailSuggestions extends StatelessWidget {
  final ValueChanged<String> onPick;
  final bool enabled;
  final WrapAlignment alignment;

  /// One horizontally-scrolling line instead of a wrapping block -- for the
  /// row just above the composer, where vertical space is precious.
  final bool singleLine;

  const MailSuggestions({
    super.key,
    required this.onPick,
    this.enabled = true,
    this.alignment = WrapAlignment.start,
    this.singleLine = false,
  });

  /// True once the thread already has a reply that used mail -- the user
  /// has discovered the feature, so the chips can step aside.
  static bool hasMailReply(Iterable<ChatMessage> messages) => messages.any((m) => m.replyMeta != null);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: OutlookStatus.notifier,
      builder: (context, status, _) {
        if (!OutlookStatus.ready(status)) return const SizedBox.shrink();
        final children = <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mail_outline_rounded, size: 15, color: AppColors.dmTextSoft),
              const SizedBox(width: 4),
              Text('Try with your inbox:', style: TextStyle(color: AppColors.dmTextSoft, fontSize: 12)),
            ],
          ),
          for (final p in OutlookStatus.examplePrompts)
            ActionChip(
              label: Text(p, style: TextStyle(fontSize: 12, color: AppColors.dmText)),
              backgroundColor: AppColors.dmBubbleIn,
              side: BorderSide(color: AppColors.dmBubbleBorder),
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
              onPressed: enabled ? () => onPick(p) : null,
            ),
        ];
        if (singleLine) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(width: 6), c],
              ],
            ),
          );
        }
        return Wrap(
          alignment: alignment,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: children,
        );
      },
    );
  }
}
