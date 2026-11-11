import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../widgets/formatted_text.dart';
import 'work_api.dart';
import 'work_context.dart';
import 'work_glass.dart';
import 'work_ui.dart';

/// Tickets on the phone: the list (assigned to me / following / all), one
/// ticket with its trace, and tagging messages, emails and calls to a ticket.
/// Setting a project's ticket key stays on the website.

const ticketStatus = {'todo': 'To do', 'in_progress': 'In progress', 'in_review': 'In review', 'done': 'Done', 'cancelled': 'Cancelled'};
const ticketPriority = {'urgent': 'Urgent', 'high': 'High', 'medium': 'Medium', 'low': 'Low'};
final _keyRe = RegExp(r'\b([A-Z][A-Z0-9]{1,9}-\d{1,6})\b');

/// Ticket keys typed in a piece of text, e.g. "see PAY-12".
List<String> keysIn(String? text) => _keyRe.allMatches(text ?? '').map((m) => m.group(1)!).toSet().toList();

Color _statusColor(String? s) => switch (s) {
      'in_progress' => AppColors.dmAccentDark,
      'in_review' => const Color(0xFF7B5BD6),
      'done' => const Color(0xFF2E8F79),
      'cancelled' => workSoftText,
      _ => AppColors.dmText,
    };

class TicketStatusChip extends StatelessWidget {
  final String? status;
  const TicketStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status);
    return Semantics(
      label: 'Status: ${ticketStatus[status] ?? status}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(10)),
        child: Text(ticketStatus[status] ?? status ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
      ),
    );
  }
}

Future<void> openTicket(BuildContext context, WorkContext work, {int? id, String? key}) async {
  var tid = id;
  if (tid == null && key != null) {
    try {
      final r = await WorkApi.instance.tickets(work.orgId, scope: 'all', status: 'all', q: key);
      tid = (List<Map>.from(r['tickets'] ?? []).where((t) => t['key'] == key).firstOrNull)?['id'] as int?;
    } catch (_) {}
    if (tid == null) {
      if (context.mounted) showWorkSnack(context, "$key isn't shared with you, or doesn't exist.", error: true);
      return;
    }
  }
  if (tid == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TicketScreen(work: work, id: tid!)));
}

class TicketTile extends StatelessWidget {
  final Map t;
  final VoidCallback onTap;
  const TicketTile({super.key, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final prio = t['priority'] as String?;
    return WorkCard(
      onTap: onTap,
      edge: prio == 'urgent'
          ? AppColors.danger
          : prio == 'high'
              ? AppColors.dmAccentDark
              : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(t['key'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.dmAccentDark)),
          const SizedBox(width: 8),
          if (prio == 'urgent' || prio == 'high')
            Text(ticketPriority[prio]!,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: prio == 'urgent' ? AppColors.danger : AppColors.dmAccentDark)),
          const Spacer(),
          TicketStatusChip(t['status'] as String?),
        ]),
        const SizedBox(height: 6),
        Text(t['title'] as String? ?? '',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.dmText, height: 1.3)),
        const SizedBox(height: 4),
        Muted(
          [
            t['project_name'],
            t['assignees'] ?? 'Unassigned',
            if (t['due_date'] != null) 'due ${fmtDay(t['due_date'] as String)}',
            if ((t['links'] as num? ?? 0) > 0) '${t['links']} linked',
          ].where((x) => x != null).join(' · '),
          maxLines: 1,
        ),
      ]),
    );
  }
}

/// The Tickets tab.
class TicketsTab extends StatefulWidget {
  final WorkContext work;
  const TicketsTab({super.key, required this.work});

  @override
  State<TicketsTab> createState() => _TicketsTabState();
}

class _TicketsTabState extends State<TicketsTab> {
  String _scope = 'mine';
  bool _closed = false;
  int _version = 0;
  static const _scopes = {'mine': 'Assigned to me', 'watching': 'Following', 'all': 'All'};

  @override
  Widget build(BuildContext context) {
    final org = widget.work.orgId;
    final status = _closed ? 'all' : 'open';
    return WorkPage(
      title: 'Tickets',
      leading: widget.work.leading(context),
      actions: [
        IconButton(
          tooltip: 'Find a ticket',
          icon: const Icon(Icons.search),
          onPressed: () async {
            final t = await showModalBottomSheet<Map>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => TicketPicker(work: widget.work, title: 'Find a ticket', openOnly: false),
            );
            if (t != null && context.mounted) {
              await openTicket(context, widget.work, id: t['id'] as int);
              setState(() => _version++);
            }
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(MediaQuery.textScalerOf(context).scale(48).clamp(48, 96)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(children: [
            for (final e in _scopes.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: _scope == e.key,
                  onSelected: (_) => setState(() => _scope = e.key),
                  selectedColor: AppColors.dmAccent.withValues(alpha: 0.25),
                ),
              ),
            FilterChip(label: const Text('Show closed'), selected: _closed, onSelected: (v) => setState(() => _closed = v)),
          ]),
        ),
      ),
      body: CachedLoad(
        key: ValueKey('$org:$_scope:$status:$_version'),
        cacheKey: 'tickets:$org:$_scope:$status',
        fetch: () => WorkApi.instance.tickets(org, scope: _scope, status: status),
        builder: (context, data, reload) {
          final items = List<Map>.from((data as Map)['tickets'] ?? []);
          if (items.isEmpty) {
            return ListView(children: [
              EmptyNote(
                icon: Icons.confirmation_number_outlined,
                title: _scope == 'mine' ? 'Nothing assigned to you' : 'No tickets here',
                text: 'Tickets are created on the website or here. Type a key like PAY-12 in a message to link it.',
              ),
            ]);
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(14, 6, 14, listEnd(context)),
            children: [
              for (final t in items)
                TicketTile(
                  t: t,
                  onTap: () async {
                    await openTicket(context, widget.work, id: t['id'] as int);
                    reload();
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Search open tickets and pick one (for tagging, or to open).
class TicketPicker extends StatefulWidget {
  final WorkContext work;
  final String title;
  final bool openOnly;
  final bool askShare; // tagging: also ask whether to share the full content
  const TicketPicker({super.key, required this.work, required this.title, this.openOnly = true, this.askShare = false});

  @override
  State<TicketPicker> createState() => _TicketPickerState();
}

class _TicketPickerState extends State<TicketPicker> {
  String _q = '';
  bool _shared = false;
  Map? _picked;
  int _gen = 0;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassPanel(
        radius: 28,
        blur: 24,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: h * 0.72,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
                child: Row(children: [
                  Expanded(child: Text(widget.title, style: appHeadlineFont(color: AppColors.dmText, fontSize: 18))),
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (v) => setState(() {
                    _q = v.trim();
                    _picked = null;
                    _gen++;
                  }),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Key or words, e.g. PAY-12 or refund',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              Expanded(
                child: CachedLoad(
                  key: ValueKey('pick$_gen'),
                  cacheKey: null,
                  fetch: () => WorkApi.instance.tickets(widget.work.orgId, scope: 'all', status: widget.openOnly ? 'open' : 'all', q: _q),
                  builder: (context, data, _) {
                    final items = List<Map>.from((data as Map)['tickets'] ?? []);
                    if (items.isEmpty) return ListView(children: const [EmptyNote(icon: Icons.search_off, title: 'No tickets match')]);
                    return ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 8), children: [
                      for (final t in items.take(40))
                        ListTile(
                          minVerticalPadding: 10,
                          selected: _picked?['id'] == t['id'],
                          selectedTileColor: AppColors.dmAccent.withValues(alpha: 0.14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          leading: Text(t['key'] as String? ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.dmAccentDark)),
                          title: Text(t['title'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: TicketStatusChip(t['status'] as String?),
                          onTap: () => widget.askShare ? setState(() => _picked = t) : Navigator.pop(context, t),
                        ),
                    ]);
                  },
                ),
              ),
              if (widget.askShare) ...[
                SwitchListTile(
                  value: _shared,
                  onChanged: (v) => setState(() => _shared = v),
                  title: const Text('Share the full content with everyone on the ticket'),
                  subtitle: Text('Otherwise people who weren’t part of it see a one-line summary.', style: TextStyle(color: workSoftText)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _picked == null ? null : () => Navigator.pop(context, {..._picked!, '_shared': _shared}),
                      child: Text(_picked == null ? 'Pick a ticket' : 'Tag to ${_picked!['key']}'),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tag a message, email or call to a ticket. Returns the ticket key, or null.
Future<String?> tagToTicket(BuildContext context, WorkContext work, String sourceType, int sourceId) async {
  final what = {'message': 'message', 'email': 'email', 'meeting': 'call or meeting'}[sourceType] ?? 'item';
  final t = await showModalBottomSheet<Map>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TicketPicker(work: work, title: 'Tag this $what to a ticket', askShare: true),
  );
  if (t == null) return null;
  try {
    await WorkApi.instance.tagTicket(work.orgId, t['id'] as int, sourceType, sourceId, shared: t['_shared'] == true);
    HapticFeedback.lightImpact();
    if (context.mounted) showWorkSnack(context, 'Tagged to ${t['key']}');
    return t['key'] as String?;
  } catch (e) {
    if (context.mounted) showWorkSnack(context, workError(e), error: true);
    return null;
  }
}

/// On a meeting or call: its tickets, suggestions to confirm, and "Tag to ticket".
class TicketsOnItem extends StatefulWidget {
  final WorkContext work;
  final String sourceType;
  final int sourceId;
  const TicketsOnItem({super.key, required this.work, required this.sourceType, required this.sourceId});

  @override
  State<TicketsOnItem> createState() => _TicketsOnItemState();
}

class _TicketsOnItemState extends State<TicketsOnItem> {
  List<Map>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await WorkApi.instance.ticketsOn(widget.work.orgId, widget.sourceType, widget.sourceId);
      if (mounted) setState(() => _items = List<Map>.from(r['tickets'] ?? []));
    } catch (_) {
      if (mounted) setState(() => _items = []);
    }
  }

  Future<void> _decide(Map t, String action) async {
    try {
      await WorkApi.instance.ticketSuggestion(widget.work.orgId, t['id'] as int, t['link_id'] as int, action);
      HapticFeedback.lightImpact();
      if (mounted) showWorkSnack(context, action == 'confirm' ? 'Linked to ${t['key']}' : 'Dismissed');
      _load();
    } catch (e) {
      if (mounted) showWorkSnack(context, workError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const SizedBox.shrink();
    final linked = items.where((t) => t['status'] == 'linked').toList();
    final suggested = items.where((t) => t['status'] == 'suggested').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(
        'Tickets',
        count: linked.length,
        trailing: TextButton.icon(
          onPressed: () async {
            if (await tagToTicket(context, widget.work, widget.sourceType, widget.sourceId) != null) _load();
          },
          icon: const Icon(Icons.sell_outlined, size: 18),
          label: const Text('Tag to ticket'),
        ),
      ),
      for (final t in suggested)
        WorkCard(
          edge: const Color(0xFF7B5BD6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Was this about '),
                  TextSpan(text: '${t['key']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: ' ${t['title']}?'),
                ]),
                style: TextStyle(color: AppColors.dmText, fontSize: 14.5)),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton(onPressed: () => _decide(t, 'confirm'), child: const Text('Yes, link it')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _decide(t, 'reject'), child: const Text('No')),
            ]),
          ]),
        ),
      if (linked.isEmpty && suggested.isEmpty) const Muted('Not tagged to any ticket.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in linked)
          ActionChip(
            avatar: const Icon(Icons.confirmation_number_outlined, size: 18),
            label: Text('${t['key']} · ${t['title']}', overflow: TextOverflow.ellipsis),
            onPressed: () => openTicket(context, widget.work, id: t['id'] as int),
          ),
      ]),
    ]);
  }
}

/// One ticket and its trace.
class TicketScreen extends StatefulWidget {
  final WorkContext work;
  final int id;
  const TicketScreen({super.key, required this.work, required this.id});

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  final _api = WorkApi.instance;
  final _comment = TextEditingController();
  Map? _d;
  String? _error;
  bool _busy = false;

  int get _org => widget.work.orgId;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final cached = await _api.cached('ticket:$_org:${widget.id}');
    if (cached is Map && mounted && _d == null) setState(() => _d = cached);
    await _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.ticket(_org, widget.id);
      if (mounted) {
        setState(() {
          _d = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = workError(e));
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _run(Future<dynamic> Function() f, [String? done]) async {
    setState(() => _busy = true);
    try {
      final r = await f();
      HapticFeedback.lightImpact();
      if (r is Map && r['ticket'] != null) {
        setState(() => _d = r);
      } else {
        await _load();
      }
      if (done != null && mounted) showWorkSnack(context, done);
    } catch (e) {
      if (mounted) showWorkSnack(context, workError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return WorkPage(
        title: 'Ticket',
        body: _error == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
            : EmptyNote(icon: Icons.error_outline, title: "Couldn't open this ticket", text: _error),
      );
    }
    final t = d['ticket'] as Map;
    final people = d['people'] as Map;
    final canEdit = d['can_edit'] == true;
    final suggestions = List<Map>.from(d['suggestions'] ?? []);
    final timeline = List<Map>.from(d['timeline'] ?? []);
    final assignees = List<Map>.from(people['assignees'] ?? []);
    final following = List<Map>.from(people['watchers'] ?? []).any((p) => p['user_id'] == widget.work.meId);
    return WorkPage(
      title: t['key'] as String? ?? 'Ticket',
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(() => _api.ticketPerson(_org, widget.id, widget.work.meId, 'watcher', add: !following),
                  following ? 'Stopped following' : 'Following'),
          child: Text(following ? 'Following ✓' : 'Follow'),
        ),
      ],
      body: Column(children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
              Muted('${t['project_name']} · ${t['key']}'),
              const SizedBox(height: 4),
              Text(t['title'] as String? ?? '',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.dmText, height: 1.25)),
              const SizedBox(height: 14),
              _fields(t, canEdit, assignees),
              if ((t['description'] as String?)?.isNotEmpty == true) ...[
                const SectionTitle('Description'),
                FormattedText(t['description'] as String, style: TextStyle(fontSize: 14.5, color: AppColors.dmText, height: 1.45)),
              ],
              _brief(t),
              if (suggestions.isNotEmpty) ...[
                SectionTitle('Was this about ${t['key']}?', count: suggestions.length),
                for (final s in suggestions)
                  WorkCard(
                    edge: const Color(0xFF7B5BD6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s['label'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.dmText)),
                      if (s['summary'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Muted(s['summary'] as String)),
                      const SizedBox(height: 8),
                      Row(children: [
                        FilledButton(
                          onPressed:
                              _busy ? null : () => _run(() => _api.ticketSuggestion(_org, widget.id, s['id'] as int, 'confirm'), 'Linked'),
                          child: const Text('Yes, link it'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() => _api.ticketSuggestion(_org, widget.id, s['id'] as int, 'reject'), 'Dismissed'),
                          child: const Text('No'),
                        ),
                      ]),
                    ]),
                  ),
              ],
              const SectionTitle('Activity'),
              for (final x in timeline) _TimelineEntry(x: x),
            ]),
          ),
        ),
        _composer(),
      ]),
    );
  }

  Widget _fields(Map t, bool canEdit, List<Map> assignees) {
    Widget pick<T>(String label, String value, Map<String, String> options, ValueChanged<String> onPick) => Expanded(
          child: Frosted(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                dropdownColor: AppColors.dmBubbleIn,
                hint: Text(label),
                onChanged: canEdit && !_busy ? (v) => v == null ? null : onPick(v) : null,
                items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              ),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        pick('Status', t['status'] as String, ticketStatus, (v) => _run(() => _api.editTicket(_org, widget.id, {'status': v}))),
        const SizedBox(width: 10),
        pick('Priority', t['priority'] as String, ticketPriority, (v) => _run(() => _api.editTicket(_org, widget.id, {'priority': v}))),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Icon(Icons.person_outline, size: 18, color: workSoftText),
        if (assignees.isEmpty) const Muted('Nobody assigned'),
        for (final p in assignees)
          InputChip(
            label: Text(p['username'] as String? ?? ''),
            onDeleted: canEdit ? () => _run(() => _api.ticketPerson(_org, widget.id, p['user_id'] as int, 'assignee', add: false)) : null,
            deleteButtonTooltipMessage: 'Unassign',
          ),
        if (canEdit && !assignees.any((p) => p['user_id'] == widget.work.meId))
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Assign to me'),
            onPressed: () => _run(() => _api.ticketPerson(_org, widget.id, widget.work.meId, 'assignee', add: true), 'Assigned to you'),
          ),
        if (t['due_date'] != null) ...[
          Icon(Icons.event_outlined, size: 18, color: workSoftText),
          Muted('due ${fmtDay(t['due_date'] as String)}', size: 13.5),
        ],
      ]),
    ]);
  }

  Widget _brief(Map t) {
    final summary = t['summary'] as String?;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Frosted(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, size: 18, color: AppColors.dmAccentDark),
            const SizedBox(width: 8),
            Expanded(child: Text('What we know so far', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.dmText))),
            TextButton(
              onPressed: _busy ? null : () => _run(() => _api.ticketBrief(_org, widget.id)),
              child: Text(_busy
                  ? 'Writing…'
                  : summary == null
                      ? 'Write it'
                      : 'Refresh'),
            ),
          ]),
          if (summary != null)
            Text(summary, style: TextStyle(fontSize: 14, color: AppColors.dmText, height: 1.5))
          else
            const Muted('A short brief from everything linked and said here.'),
        ]),
      ),
    );
  }

  Widget _composer() => Container(
        padding: EdgeInsets.fromLTRB(14, 6, 6, 6 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(color: AppColors.dmBubbleIn, border: Border(top: BorderSide(color: AppColors.dmBubbleBorder))),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _comment,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(border: InputBorder.none, hintText: 'Add a comment'),
            ),
          ),
          IconButton(
            tooltip: 'Comment',
            onPressed: _busy
                ? null
                : () async {
                    final text = _comment.text.trim();
                    if (text.isEmpty) return;
                    await _run(() => _api.ticketComment(_org, widget.id, text));
                    _comment.clear();
                  },
            icon: const Icon(Icons.send_rounded, color: AppColors.dmAccent),
          ),
        ]),
      );
}

class _TimelineEntry extends StatefulWidget {
  final Map x;
  const _TimelineEntry({required this.x});

  @override
  State<_TimelineEntry> createState() => _TimelineEntryState();
}

class _TimelineEntryState extends State<_TimelineEntry> {
  bool _open = false;

  String _sentence(Map e) {
    final d = (e['detail'] is Map) ? e['detail'] as Map : const {};
    final who = e['actor'] as String? ?? 'Throughline';
    switch (e['kind']) {
      case 'created':
        return '$who created this';
      case 'status':
        return '$who moved it from ${ticketStatus[d['from']] ?? d['from']} to ${ticketStatus[d['to']] ?? d['to']}';
      case 'priority':
        return '$who set priority to ${ticketPriority[d['to']] ?? d['to']}';
      case 'due':
        return d['to'] != null ? '$who set the due date to ${fmtDay(d['to'] as String)}' : '$who removed the due date';
      case 'title':
        return '$who renamed it';
      case 'description':
        return '$who edited the description';
      case 'assigned':
        return '$who assigned ${e['person'] ?? 'someone'}';
      case 'unassigned':
        return '$who unassigned ${e['person'] ?? 'someone'}';
      case 'watching':
        return '${e['person'] ?? 'Someone'} is following';
      case 'unwatched':
        return '${e['person'] ?? 'Someone'} stopped following';
      case 'unlinked':
        return '$who removed a ${(d['label'] ?? d['type'] ?? 'link').toString().toLowerCase()}';
      default:
        return '$who: ${(e['kind'] as String? ?? '').replaceAll('_', ' ')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.x;
    final type = x['type'];
    if (type == 'comment') {
      return WorkCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(x['actor'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.dmText)),
            const SizedBox(width: 8),
            Muted(fmtTime(x['at'] as String?), size: 12),
          ]),
          const SizedBox(height: 4),
          Text(x['body'] as String? ?? '', style: TextStyle(fontSize: 14.5, color: AppColors.dmText, height: 1.4)),
        ]),
      );
    }
    if (type == 'link') {
      final source = x['source_type'] as String?;
      final icon = switch (source) {
        'email' => Icons.mail_outline,
        'meeting' => Icons.call_outlined,
        'commitment' => Icons.task_alt_outlined,
        _ => Icons.chat_bubble_outline,
      };
      final how = {'key': 'mentioned by key', 'manual': 'tagged', 'ai': 'suggested, confirmed'}[x['how']] ?? '';
      final content = x['content'] as String?;
      return WorkCard(
        edge: const Color(0xFF7B5BD6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 17, color: const Color(0xFF7B5BD6)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(x['label'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.dmText)),
            ),
          ]),
          const SizedBox(height: 2),
          Muted(
              [if (x['tagged_by'] != null) x['tagged_by'], how, if (x['shared'] == true) 'shared', fmtTime(x['at'] as String?)].join(' · '),
              size: 12),
          const SizedBox(height: 6),
          if (x['summary'] != null)
            Text(x['summary'] as String, style: TextStyle(fontSize: 14, color: AppColors.dmText, height: 1.4))
          else
            const Muted('Summary on its way…'),
          if (content != null) ...[
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: () => setState(() => _open = !_open),
              child: Text(_open
                  ? 'Hide'
                  : source == 'meeting'
                      ? 'Show what was said'
                      : 'Show the $source'),
            ),
            if (_open) SelectableText(content, style: TextStyle(fontSize: 13.5, color: AppColors.dmText, height: 1.45)),
          ] else if (x['open'] == null)
            const Padding(padding: EdgeInsets.only(top: 4), child: Muted('Private to the people who were in it.', size: 12)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 5), child: Icon(Icons.circle, size: 8, color: workSoftText)),
        const SizedBox(width: 10),
        Expanded(child: Muted('${_sentence(x)} · ${fmtTime(x['at'] as String?)}', size: 13)),
      ]),
    );
  }
}
