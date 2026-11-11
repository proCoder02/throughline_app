import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'work_api.dart';
import 'work_client.dart';
import 'work_context.dart';
import 'work_tickets.dart';
import 'work_ui.dart';

/// Commitments: what I owe, what's owed to me, and everything in my teams.
/// Day-to-day actions only -- confirm, done, reopen, drop, updates and
/// blockers. Creating projects or reassigning across teams is website work.
class CommitmentsTab extends StatefulWidget {
  final WorkContext work;
  const CommitmentsTab({super.key, required this.work});

  @override
  State<CommitmentsTab> createState() => _CommitmentsTabState();
}

class _CommitmentsTabState extends State<CommitmentsTab> {
  String _scope = 'mine';
  bool _showClosed = false;

  static const _scopes = {'mine': 'Mine', 'owed': 'Owed to me', 'team': 'My teams'};

  @override
  Widget build(BuildContext context) {
    final org = widget.work.orgId;
    return WorkPage(
      title: 'Commitments',
      leading: widget.work.leading(context),
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
            FilterChip(
              label: const Text('Show closed'),
              selected: _showClosed,
              onSelected: (v) => setState(() => _showClosed = v),
            ),
          ]),
        ),
      ),
      body: CachedLoad(
        key: ValueKey('$org:$_scope'),
        cacheKey: 'commitments:$org:$_scope',
        fetch: () => WorkApi.instance.commitments(org, _scope),
        builder: (context, data, reload) {
          final all = List<Map>.from((data as Map)['commitments'] ?? []);
          final items = _showClosed ? all : all.where((c) => !const {'done', 'dropped', 'declined'}.contains(c['status'])).toList();
          if (items.isEmpty) {
            return ListView(children: [
              EmptyNote(
                icon: Icons.task_alt,
                title: _scope == 'mine' ? 'Nothing on your plate' : 'Nothing here',
                text: 'Commitments come from meetings, calls, work chat and email, and from requests your team accepts.',
              ),
            ]);
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(14, 6, 14, listEnd(context)),
            children: [
              for (final c in items)
                CommitmentTile(
                  c: c,
                  showOwner: _scope != 'mine',
                  onTap: () async {
                    await openCommitment(context, widget.work, c['id'] as int);
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

Future<void> openCommitment(BuildContext context, WorkContext work, int id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommitmentScreen(work: work, id: id)));

class CommitmentTile extends StatelessWidget {
  final Map c;
  final bool showOwner;
  final VoidCallback? onTap;
  final Widget? trailing;
  const CommitmentTile({super.key, required this.c, this.showOwner = true, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (c['unit_name'] != null) c['unit_name'] as String,
      if (showOwner && c['owner'] != null) c['owner'] as String,
      if (c['owed_to'] != null) 'for ${c['owed_to']}',
      if (c['due_date'] != null) 'due ${fmtDay(c['due_date'] as String)}',
    ];
    return WorkCard(
      onTap: onTap,
      edge: statusColor(c['status'] as String?),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(c['text'] as String? ?? '',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.dmText, height: 1.3)),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 6),
        Row(children: [
          StatusChip(c['status'] as String?, atRisk: c['at_risk'] == true),
          Expanded(child: Muted(meta.join(' · '), maxLines: 1)),
        ]),
        if (c['risk_note'] != null && (c['risk_note'] as String).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(c['risk_note'] as String, style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
        ],
      ]),
    );
  }
}

/// One commitment: what it is, the actions I'm allowed, and its activity
/// thread (updates, blockers and what happened, oldest first).
class CommitmentScreen extends StatefulWidget {
  final WorkContext work;
  final int id;
  const CommitmentScreen({super.key, required this.work, required this.id});

  @override
  State<CommitmentScreen> createState() => _CommitmentScreenState();
}

class _CommitmentScreenState extends State<CommitmentScreen> {
  final _api = WorkApi.instance;
  final _text = TextEditingController();
  Map? _c;
  Map? _activity;
  String? _error;
  bool _busy = false;
  String _kind = 'update';

  int get _org => widget.work.orgId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([_api.commitment(_org, widget.id), _api.activity(_org, widget.id)]);
      if (mounted) {
        setState(() {
          _c = r[0]['commitment'] as Map;
          _activity = r[1];
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = workError(e));
    }
  }

  /// [f] returns false when there was no connection and the change was
  /// kept on the phone; [whileKept] then shows it here until it's sent.
  Future<void> _run(Future<bool> Function() f, String done, {VoidCallback? whileKept}) async {
    setState(() => _busy = true);
    try {
      final sentNow = await f();
      HapticFeedback.lightImpact();
      if (sentNow) {
        if (mounted) showWorkSnack(context, done);
        await _load();
      } else {
        if (mounted) {
          setState(() => whileKept?.call());
          showWorkSnack(context, "You're offline. Saved on this phone; it sends when you're back online.");
        }
      }
    } catch (e) {
      if (mounted) showWorkSnack(context, workError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(String action, [Map<String, dynamic>? data]) => _run(
        () => _api.act(_org, widget.id, action, data),
        switch (action) {
          'confirm' => 'Confirmed',
          'done' => 'Marked done',
          'reopen' => 'Reopened',
          'drop' => 'Dropped',
          _ => 'Saved',
        },
        whileKept: () {
          final status = {'confirm': 'open', 'done': 'done', 'reopen': 'open', 'drop': 'dropped'}[action];
          if (status != null && _c != null) _c = {..._c!, 'status': status, 'waiting': true};
        },
      );

  Future<void> _request(bool accept) async {
    String? reason;
    if (!accept) {
      reason = await askText(context, title: 'Decline request', hint: 'Why, so they can plan around it', action: 'Decline');
      if (reason == null) return;
    }
    await _run(() async {
      if (accept) {
        await _api.acceptRequest(_org, widget.id);
      } else {
        await _api.declineRequest(_org, widget.id, reason!);
      }
      return true;
    }, accept ? 'Accepted. It’s now your team’s commitment.' : 'Declined');
  }

  Future<void> _post() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    final kind = _kind;
    await _run(
      () => _api.update(_org, widget.id, kind, t),
      switch (kind) {
        'blocker' => 'Blocker flagged. The people involved are told.',
        'unblocked' => 'Marked unblocked',
        _ => 'Update posted',
      },
      whileKept: () {
        final thread = List<Map>.from(_activity?['thread'] ?? [])
          ..add({'type': 'note', 'kind': kind, 'text': t, 'actor': 'You (waiting to send)', 'at': DateTime.now().toIso8601String()});
        _activity = {...?_activity, 'thread': thread};
      },
    );
    _text.clear();
    setState(() => _kind = 'update');
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return WorkPage(
      title: 'Commitment',
      body: c == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
              : EmptyNote(icon: Icons.error_outline, title: "Couldn't open this", text: _error))
          : Column(children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                    _header(c),
                    _actions(c),
                    if (_activity?['supports'] != null) _supports(_activity!['supports'] as Map),
                    if (_activity?['tickets'] is Map) _tickets(_activity!['tickets'] as Map),
                    if ((_activity?['supporting'] as List?)?.isNotEmpty == true) _supporting(_activity!['supporting'] as List),
                    const SectionTitle('Activity'),
                    ..._thread(),
                  ]),
                ),
              ),
              if (_activity?['closed'] != true) _composer(),
            ]),
    );
  }

  Widget _header(Map c) {
    final rows = <(IconData, String)>[
      if (c['owner'] != null || c['owner_name'] != null) (Icons.person_outline, 'Owner: ${c['owner'] ?? c['owner_name']}'),
      if (c['owed_to'] != null || c['owed_to_name'] != null) (Icons.handshake_outlined, 'Owed to: ${c['owed_to'] ?? c['owed_to_name']}'),
      if (c['due_date'] != null) (Icons.event_outlined, 'Due ${fmtDay(c['due_date'] as String)}'),
      if (c['unit_name'] != null) (Icons.groups_outlined, c['unit_name'] as String),
      if (c['project_name'] != null) (Icons.folder_outlined, 'Project: ${c['project_name']}'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      StatusChip(c['status'] as String?, atRisk: c['at_risk'] == true),
      const SizedBox(height: 10),
      Text(c['text'] as String? ?? '', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.dmText, height: 1.3)),
      const SizedBox(height: 10),
      for (final (icon, t) in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Icon(icon, size: 16, color: AppColors.dmTextSoft),
            const SizedBox(width: 8),
            Expanded(child: Text(t, style: TextStyle(fontSize: 13.5, color: AppColors.dmText))),
          ]),
        ),
      if (c['quote'] != null && (c['quote'] as String).isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: const Border(left: BorderSide(color: AppColors.dmAccent, width: 3)),
            color: AppColors.dmPillFill,
          ),
          child: Text('“${c['quote']}”', style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.dmText, fontSize: 13.5)),
        ),
    ]);
  }

  Widget _actions(Map c) {
    if (c['status'] == 'requested' && (widget.work.managesATeam || widget.work.role != 'member')) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
              onPressed: _busy ? null : () => _request(true), icon: const Icon(Icons.check), label: const Text('Accept request')),
          OutlinedButton(onPressed: _busy ? null : () => _request(false), child: const Text('Decline')),
        ]),
      );
    }
    if (c['waiting'] == true) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Icon(Icons.cloud_upload_outlined, size: 16, color: workSoftText),
          const SizedBox(width: 6),
          const Expanded(child: Muted('Changed on this phone. Sends when you’re back online.')),
        ]),
      );
    }
    if (c['can_change'] != true) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Muted('Only the people involved, or a manager of the team, can change this.'),
      );
    }
    final s = c['status'] as String?;
    final buttons = <Widget>[
      if (s == 'detected')
        FilledButton.icon(onPressed: _busy ? null : () => _action('confirm'), icon: const Icon(Icons.check), label: const Text('Confirm')),
      if (s == 'open' || s == 'overdue')
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final note = await askText(context, title: 'Mark done', hint: 'What was delivered? (optional)', action: 'Done');
                  if (note != null) _action('done', {'note': note});
                },
          icon: const Icon(Icons.task_alt),
          label: const Text('Mark done'),
        ),
      if (s == 'done' || s == 'dropped') OutlinedButton(onPressed: _busy ? null : () => _action('reopen'), child: const Text('Reopen')),
      if (s == 'open' || s == 'overdue' || s == 'detected')
        OutlinedButton(
          onPressed: _busy
              ? null
              : () async {
                  final reason =
                      await askText(context, title: 'Drop this commitment', hint: "Why it's no longer happening", action: 'Drop');
                  if (reason != null) _action('drop', {'reason': reason});
                },
          child: const Text('Drop'),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox(height: 4);
    return Padding(padding: const EdgeInsets.only(top: 14), child: Wrap(spacing: 8, runSpacing: 8, children: buttons));
  }

  Widget _supports(Map p) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: WorkCard(
          child: p['hidden'] == true
              ? const Muted("Supports another team's commitment you can't see.")
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Muted('Supports'),
                  const SizedBox(height: 2),
                  Text(p['text'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dmText)),
                  if (p['due_date'] != null) Muted('due ${fmtDay(p['due_date'] as String)}'),
                ]),
        ),
      );

  /// The tickets behind this promise (e.g. a client deliverable): progress, and each ticket.
  Widget _tickets(Map r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Tickets', count: (r['total'] as num?)?.toInt()),
        TicketProgressBar(p: r),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in List<Map>.from(r['tickets'] ?? []))
            ActionChip(
              avatar: Icon(k['status'] == 'done' ? Icons.check_circle : Icons.confirmation_number_outlined,
                  size: 18, color: k['status'] == 'blocked' || k['late'] == true ? AppColors.danger : null),
              label: Text('${k['key']} · ${ticketStatus[k['status']] ?? k['status']}${k['late'] == true ? ' · late' : ''}'),
              onPressed: () => openTicket(context, widget.work, id: k['id'] as int),
            ),
        ]),
      ]);

  Widget _supporting(List kids) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Depends on', count: kids.length),
        for (final k in kids.cast<Map>())
          WorkCard(
            edge: statusColor(k['status'] as String?),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k['text'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dmText)),
              const SizedBox(height: 4),
              Row(children: [
                StatusChip(k['status'] as String?),
                Expanded(
                  child: Muted(
                      [
                        if (k['unit_name'] != null) k['unit_name'],
                        if (k['owner'] != null) k['owner'],
                        if (k['due_date'] != null) 'due ${fmtDay(k['due_date'] as String)}',
                      ].join(' · '),
                      maxLines: 1),
                ),
              ]),
              if (k['blocker'] != null) ...[
                const SizedBox(height: 4),
                Text('Blocked: ${(k['blocker'] is Map ? k['blocker']['text'] : k['blocker']) ?? ''}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
              ],
            ]),
          ),
      ]);

  List<Widget> _thread() {
    final items = List<Map>.from(_activity?['thread'] ?? []);
    if (items.isEmpty) return [const Muted('Nothing yet.')];
    return [for (final e in items) _ActivityRow(e: e)];
  }

  Widget _composer() {
    final kinds = {'update': 'Update', 'blocker': 'Blocker', 'unblocked': 'Unblocked'};
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: AppColors.dmBubbleIn, border: Border(top: BorderSide(color: AppColors.dmBubbleBorder))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          for (final e in kinds.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(e.value),
                selected: _kind == e.key,
                selectedColor: (e.key == 'blocker' ? AppColors.danger : AppColors.dmAccent).withValues(alpha: 0.22),
                onSelected: (_) => setState(() => _kind = e.key),
              ),
            ),
        ]),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                counterText: '',
                border: InputBorder.none,
                hintText: switch (_kind) {
                  'blocker' => "What's blocking this?",
                  'unblocked' => 'What changed?',
                  _ => 'Post an update…',
                },
              ),
            ),
          ),
          IconButton(
            onPressed: _busy ? null : _post,
            icon: Icon(Icons.send_rounded, color: _kind == 'blocker' ? AppColors.danger : AppColors.dmAccent),
            tooltip: 'Post',
          ),
        ]),
      ]),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final Map e;
  const _ActivityRow({required this.e});

  static Map _detail(dynamic d) {
    if (d is Map) return d;
    if (d is String && d.isNotEmpty) {
      try {
        final j = jsonDecode(d);
        if (j is Map) return j;
      } catch (_) {}
    }
    return const {};
  }

  String _sentence() {
    final d = _detail(e['detail']);
    final who = (e['actor'] as String?) ?? 'Throughline';
    switch (e['kind']) {
      case 'created':
        final src = d['source'];
        return '$who created this${src == 'meeting' ? ' from a meeting' : src == 'thread' ? ' from a chat' : src == 'request' ? ' as a request' : ''}';
      case 'confirm':
        return '$who confirmed it';
      case 'done':
        if (d['by'] == 'evidence check') return 'Throughline found it was done${d['evidence'] != null ? ': “${d['evidence']}”' : ''}';
        return '$who marked it done${d['note'] != null && d['note'] != 'Marked done' ? ': ${d['note']}' : ''}';
      case 'drop':
        return '$who dropped it${d['reason'] != null ? ': ${d['reason']}' : ''}';
      case 'reopen':
        return '$who reopened it';
      case 'edit':
        if (d.containsKey('due_date')) {
          return '$who moved the due date to ${d['due_date'] != null ? fmtDay(d['due_date'] as String) : 'none'}';
        }
        if (d.containsKey('owner_id')) return '$who changed the owner';
        return '$who reworded it';
      case 'overdue':
        return 'It became overdue';
      case 'at_risk':
        return 'At risk: ${d['why'] ?? ''}';
      case 'risk_cleared':
        return 'No longer at risk';
      case 'accepted':
        return '$who accepted the request${d['due_date'] != null ? ', due ${fmtDay(d['due_date'] as String)}' : ''}';
      case 'declined':
        return '$who declined${d['reason'] != null ? ': ${d['reason']}' : ''}';
      case 'reassigned':
        return 'Handed over from ${d['from_user'] ?? 'a former member'}';
      default:
        return '$who: ${(e['kind'] as String? ?? '').replaceAll('_', ' ')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = e['type'] == 'note';
    final kind = e['kind'] as String?;
    final color = switch (kind) {
      'blocker' || 'at_risk' || 'overdue' || 'declined' => AppColors.danger,
      'done' || 'risk_cleared' || 'unblocked' => const Color(0xFF2E9D6A),
      _ => AppColors.dmTextSoft,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 5),
          width: 9,
          height: 9,
          decoration:
              BoxDecoration(color: note ? color : Colors.transparent, shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (note) ...[
              Text(
                '${e['actor'] ?? 'Someone'}${kind == 'blocker' ? ' flagged a blocker' : kind == 'unblocked' ? ' marked it unblocked' : ''}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kind == 'update' ? AppColors.dmText : color),
              ),
              const SizedBox(height: 2),
              Text(e['text'] as String? ?? '', style: TextStyle(fontSize: 14, color: AppColors.dmText, height: 1.35)),
            ] else
              Text(_sentence(), style: TextStyle(fontSize: 13.5, color: AppColors.dmText, height: 1.35)),
            const SizedBox(height: 2),
            Muted(fmtTime(e['at'] as String?), size: 12),
          ]),
        ),
      ]),
    );
  }
}
