import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme.dart';
import 'work_api.dart';
import 'work_commitments.dart';
import 'work_context.dart';
import 'work_glass.dart';
import 'work_tickets.dart';
import 'work_ui.dart';

/// The client view on the phone, for Sales / BU people: how each client
/// project is doing this week (deliverable progress from the tickets behind
/// it, what's at risk and why), and a client-safe update to send -- always a
/// draft the person reviews; nothing goes to a client by itself.

String _plural(int n, String w) => '$n $w${n == 1 ? '' : 's'}';

/// "2 of 5 tickets done · 1 blocked" with a bar.
class TicketProgressBar extends StatelessWidget {
  final Map p; // {done, total, blocked}
  const TicketProgressBar({super.key, required this.p});

  @override
  Widget build(BuildContext context) {
    final total = (p['total'] as num?)?.toInt() ?? 0;
    if (total == 0) return const SizedBox.shrink();
    final done = (p['done'] as num?)?.toInt() ?? 0;
    final blocked = (p['blocked'] as num?)?.toInt() ?? 0;
    return Semantics(
      label: '$done of $total tickets done${blocked > 0 ? ', $blocked blocked' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: done / total,
                minHeight: 6,
                backgroundColor: AppColors.dmBubbleBorder,
                color: blocked > 0 ? AppColors.danger : const Color(0xFF2E8F79),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Muted('$done of ${_plural(total, 'ticket')}${blocked > 0 ? ' · $blocked blocked' : ''}', size: 12),
        ]),
      ),
    );
  }
}

/// Home card: "Your client projects this week".
class ClientDigestCard extends StatelessWidget {
  final WorkContext work;
  final Map digest;
  const ClientDigestCard({super.key, required this.work, required this.digest});

  @override
  Widget build(BuildContext context) {
    final projects = List<Map>.from(digest['projects'] ?? []);
    if (projects.isEmpty) return const SizedBox.shrink();
    final t = (digest['totals'] as Map?) ?? {};
    final summary = [
      if ((t['at_risk'] ?? 0) > 0) '${t['at_risk']} at risk',
      if ((t['due_soon'] ?? 0) > 0) '${t['due_soon']} due in 2 weeks',
      if ((t['done'] ?? 0) > 0) '${t['done']} delivered',
      if ((t['tickets_done'] ?? 0) > 0) '${_plural((t['tickets_done'] as num).toInt(), 'ticket')} done',
    ].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Client projects this week', count: projects.length),
      if (summary.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 2, bottom: 8), child: Muted(summary)),
      for (final p in projects) _ProjectCard(work: work, p: p),
    ]);
  }
}

class _ProjectCard extends StatelessWidget {
  final WorkContext work;
  final Map p;
  const _ProjectCard({required this.work, required this.p});

  @override
  Widget build(BuildContext context) {
    final health = p['health'] as String?;
    final (label, color) = switch (health) {
      'late' => ('Late', AppColors.danger),
      'at_risk' => ('At risk', AppColors.dmAccentDark),
      _ => ('On track', const Color(0xFF2E8F79)),
    };
    final items = [
      ...List<Map>.from(p['at_risk'] ?? []).map((x) => (x, AppColors.danger)),
      ...List<Map>.from(p['due_soon'] ?? []).map((x) => (x, AppColors.dmAccent)),
      ...List<Map>.from(p['on_track'] ?? []).take(3).map((x) => (x, workSoftText)),
    ];
    final blocked = List<Map>.from(p['blocked_tickets'] ?? []);
    return WorkCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['name'] as String? ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dmText)),
              if ((p['client'] as String?)?.isNotEmpty == true) Muted(p['client'] as String),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        for (final (x, c) in items)
          InkWell(
            onTap: () => openCommitment(context, work, x['id'] as int),
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: c, width: 3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x['text'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dmText)),
                Muted(
                    [if (x['contact'] != null) 'for ${x['contact']}', if (x['due_date'] != null) 'due ${fmtDay(x['due_date'] as String)}']
                        .join(' · '),
                    size: 12),
                if (x['why'] != null) Text('At risk: ${x['why']}', style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
                if (x['progress'] is Map) TicketProgressBar(p: x['progress'] as Map),
              ]),
            ),
          ),
        if (blocked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Blocked:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.danger)),
              for (final k in blocked)
                ActionChip(label: Text(k['key'] as String? ?? ''), onPressed: () => openTicket(context, work, id: k['id'] as int)),
            ]),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => ClientUpdateSheet(work: work, projectId: p['id'] as int, projectName: p['name'] as String? ?? ''),
            ),
            icon: const Icon(Icons.mark_email_unread_outlined, size: 18),
            label: const Text('Draft a client update'),
          ),
        ),
      ]),
    );
  }
}

/// A client-safe status update drafted from the project's deliverables. The
/// person edits it, then copies it or opens it in their email app.
class ClientUpdateSheet extends StatefulWidget {
  final WorkContext work;
  final int projectId;
  final String projectName;
  const ClientUpdateSheet({super.key, required this.work, required this.projectId, required this.projectName});

  @override
  State<ClientUpdateSheet> createState() => _ClientUpdateSheetState();
}

class _ClientUpdateSheetState extends State<ClientUpdateSheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  List<String> _internal = [];
  String _to = '';
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _draft();
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _draft() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await WorkApi.instance.clientUpdate(widget.work.orgId, widget.projectId);
      if (!mounted) return;
      setState(() {
        _subject.text = d['subject'] as String? ?? '';
        _body.text = d['body'] as String? ?? '';
        _internal = List<String>.from(d['internal'] ?? []);
        _to = d['to'] as String? ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = workError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEmail() async {
    final uri =
        Uri(scheme: 'mailto', path: _to, query: 'subject=${Uri.encodeComponent(_subject.text)}&body=${Uri.encodeComponent(_body.text)}');
    if (!await launchUrl(uri) && mounted) showWorkSnack(context, 'No email app found. Copy the text instead.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassPanel(
        radius: 28,
        blur: 24,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.85,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
                child: Row(children: [
                  Expanded(child: Text('Client update', style: appHeadlineFont(color: AppColors.dmText, fontSize: 18))),
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Muted('${widget.projectName} · drafted in client-safe words. You edit and send it; nothing goes out by itself.'),
              ),
              Expanded(
                child: _busy
                    ? const Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(strokeWidth: 2.4),
                        SizedBox(height: 12),
                        Muted('Reading the deliverables and the tickets behind them…'),
                      ]))
                    : _error != null
                        ? EmptyNote(icon: Icons.error_outline, title: "Couldn't draft it", text: _error)
                        : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), children: [
                            if (_internal.isNotEmpty)
                              WorkCard(
                                edge: AppColors.dmAccentDark,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Before you send (internal)',
                                      style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.dmText)),
                                  for (final x in _internal)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text('• $x', style: TextStyle(color: AppColors.dmText))),
                                ]),
                              ),
                            TextField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject')),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _body,
                              minLines: 8,
                              maxLines: null,
                              decoration:
                                  const InputDecoration(labelText: 'Message', alignLabelWithHint: true, border: OutlineInputBorder()),
                            ),
                          ]),
              ),
              if (!_busy && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: '${_subject.text}\n\n${_body.text}'));
                        showWorkSnack(context, 'Copied');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _openEmail,
                        icon: const Icon(Icons.mail_outline, size: 18),
                        label: Text(_to.isEmpty ? 'Open in email' : 'Email $_to', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
