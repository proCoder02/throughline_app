import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../widgets/formatted_text.dart';
import 'work_api.dart';
import 'work_commitments.dart';
import 'work_context.dart';
import 'work_meetings.dart';
import 'mode_switch.dart';
import 'work_ui.dart';

/// Work home: what needs me today. To confirm, blockers, what I owe, what
/// I'm waiting on, requests to my team (managers), and recent decisions.
class HomeTab extends StatefulWidget {
  final WorkContext work;
  const HomeTab({super.key, required this.work});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _api = WorkApi.instance;
  int _version = 0;

  int get _org => widget.work.orgId;
  bool get _receivesRequests => widget.work.managesATeam || widget.work.role != 'member';

  Future<Map> _fetch() async {
    final brief = await _api.brief(_org);
    Map requests = const {'requests': []};
    if (_receivesRequests) {
      try {
        requests = await _api.incomingRequests(_org);
      } catch (_) {}
    }
    return {...brief, 'requests': requests['requests'] ?? []};
  }

  Future<void> _quick(Future<void> Function() f, String done) async {
    try {
      await f();
      HapticFeedback.lightImpact();
      if (mounted) {
        showWorkSnack(context, done);
        setState(() => _version++);
      }
    } catch (e) {
      if (mounted) showWorkSnack(context, workError(e), error: true);
    }
  }

  Future<void> _confirm(int id) async {
    try {
      final sent = await _api.act(_org, id, 'confirm');
      HapticFeedback.lightImpact();
      if (!mounted) return;
      showWorkSnack(context, sent ? 'Confirmed' : "You're offline. Saved on this phone; it sends when you're back online.");
      if (sent) setState(() => _version++);
    } catch (e) {
      if (mounted) showWorkSnack(context, workError(e), error: true);
    }
  }

  Future<void> _open(int id) async {
    await openCommitment(context, widget.work, id);
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    return WorkPage(
      title: work.orgName,
      leading: work.leading(context),
      actions: [
        if (work.orgs.length > 1)
          IconButton(tooltip: 'Switch organisation', onPressed: work.onSwitchOrg, icon: const Icon(Icons.swap_horiz_rounded)),
      ],
      body: CachedLoad(
        key: ValueKey('home:$_org:$_version'),
        cacheKey: 'brief:$_org',
        fetch: _fetch,
        builder: (context, data, reload) {
          final d = data as Map;
          final toConfirm = List<Map>.from(d['to_confirm'] ?? []);
          final owe = List<Map>.from(d['owe'] ?? []).where((c) => c['status'] != 'detected').toList();
          final owed = List<Map>.from(d['owed'] ?? []).where((c) => c['status'] != 'detected').toList();
          final risks = List<Map>.from(d['risks'] ?? []);
          final requests = List<Map>.from(d['requests'] ?? []);
          final decisions = List<Map>.from(d['decisions'] ?? []);
          final nothing = toConfirm.isEmpty && owe.isEmpty && owed.isEmpty && risks.isEmpty && requests.isEmpty;
          return ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 28), children: [
            const Padding(padding: EdgeInsets.only(bottom: 10), child: Center(child: ModeSwitch(work: true))),
            _CatchUpCard(work: work),
            if (nothing)
              const EmptyNote(
                icon: Icons.wb_sunny_outlined,
                title: 'Nothing needs you right now',
                text: 'Promises from your meetings, calls, work chat and email land here.',
              ),
            if (risks.isNotEmpty) ...[
              SectionTitle('Blocked or at risk', count: risks.length),
              for (final r in risks)
                WorkCard(
                  edge: AppColors.danger,
                  onTap: r['commitment'] != null ? () => _open(r['commitment_id'] as int) : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r['commitment'] as String? ?? "${r['commitment_unit'] ?? 'Another team'}'s work",
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dmText)),
                    const SizedBox(height: 4),
                    Text(
                      'Blocked by ${r['blocker_unit'] ?? 'another team'}${r['blocker'] != null ? ': ${r['blocker']}' : ''}',
                      style: const TextStyle(fontSize: 13, color: AppColors.danger),
                    ),
                    if (r['due_date'] != null) Muted('due ${fmtDay(r['due_date'] as String)}'),
                  ]),
                ),
            ],
            if (toConfirm.isNotEmpty) ...[
              SectionTitle('To confirm', count: toConfirm.length),
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 2),
                child: Muted('Throughline heard these. Confirm the real ones; drop the rest.'),
              ),
              for (final c in toConfirm)
                CommitmentTile(
                  c: c,
                  onTap: () => _open(c['id'] as int),
                  trailing: IconButton(
                    tooltip: 'Confirm',
                    icon: const Icon(Icons.check_circle_outline, color: Color(0xFF2E9D6A)),
                    onPressed: () => _confirm(c['id'] as int),
                  ),
                ),
            ],
            if (requests.isNotEmpty) ...[
              SectionTitle('Requests to your team', count: requests.length),
              for (final r in requests) _requestCard(r),
            ],
            if (owe.isNotEmpty) ...[
              SectionTitle('You owe', count: owe.length),
              for (final c in owe) CommitmentTile(c: c, showOwner: false, onTap: () => _open(c['id'] as int)),
            ],
            if (owed.isNotEmpty) ...[
              SectionTitle('Waiting on others', count: owed.length),
              for (final c in owed) CommitmentTile(c: c, onTap: () => _open(c['id'] as int)),
            ],
            SectionTitle(
              'Recent decisions',
              trailing: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DecisionsScreen(work: work))),
                child: const Text('All'),
              ),
            ),
            if (decisions.isEmpty) const Muted('No decisions in the last 7 days.'),
            for (final dec in decisions)
              WorkCard(
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DecisionScreen(work: work, id: dec['id'] as int))),
                child: Row(children: [
                  const Icon(Icons.gavel_rounded, size: 18, color: AppColors.dmAccentDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(dec['title'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dmText)),
                      Muted([if (dec['unit_name'] != null) dec['unit_name'], 'v${dec['version']}', fmtDay(dec['updated_at'] as String?)]
                          .join(' · ')),
                    ]),
                  ),
                ]),
              ),
            if (work.role != 'member' || work.managesATeam)
              const Padding(
                padding: EdgeInsets.only(top: 22),
                child: Row(children: [
                  Icon(Icons.desktop_windows_outlined, size: 16, color: Color(0xFF8A7C6E)),
                  SizedBox(width: 8),
                  Expanded(child: Muted('People, teams, invitations and projects are managed on the website.')),
                ]),
              ),
          ]);
        },
      ),
    );
  }

  Widget _requestCard(Map r) => WorkCard(
        edge: statusColor('requested'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r['text'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dmText)),
          const SizedBox(height: 4),
          Muted([
            if (r['requested_by_name'] != null) 'from ${r['requested_by_name']}',
            if (r['unit_name'] != null) 'to ${r['unit_name']}',
            if (r['requested_due'] != null) 'needed ${fmtDay(r['requested_due'] as String)}',
          ].join(' · ')),
          if (r['supports_text'] != null) Muted('For: ${r['supports_text']}', maxLines: 2),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(
              onPressed: () => _quick(() => _api.acceptRequest(_org, r['id'] as int), 'Accepted. It’s now your team’s commitment.'),
              child: const Text('Accept'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                final reason = await askText(context, title: 'Decline request', hint: 'Why, so they can plan around it', action: 'Decline');
                if (reason != null) _quick(() => _api.declineRequest(_org, r['id'] as int, reason), 'Declined');
              },
              child: const Text('Decline'),
            ),
          ]),
        ]),
      );
}

class _CatchUpCard extends StatelessWidget {
  final WorkContext work;
  const _CatchUpCard({required this.work});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: WorkCard(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.dmBubbleIn,
          builder: (_) => _CatchUpSheet(work: work),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.dmAccent.withValues(alpha: 0.18),
            child: const Icon(Icons.auto_awesome, size: 18, color: AppColors.dmAccentDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Catch me up', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.dmText)),
              const Muted('What changed, was decided, and is at risk in the last 7 days'),
            ]),
          ),
          Icon(Icons.chevron_right, color: AppColors.dmTextSoft),
        ]),
      ),
    );
  }
}

class _CatchUpSheet extends StatefulWidget {
  final WorkContext work;
  const _CatchUpSheet({required this.work});

  @override
  State<_CatchUpSheet> createState() => _CatchUpSheetState();
}

class _CatchUpSheetState extends State<_CatchUpSheet> {
  int _days = 7;
  Map? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _result = null;
      _error = null;
    });
    try {
      final r = await WorkApi.instance.catchUp(widget.work.orgId, days: _days);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = workError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Catch me up', style: appHeadlineFont(color: AppColors.dmText, fontSize: 20))),
              DropdownButton<int>(
                value: _days,
                underline: const SizedBox.shrink(),
                dropdownColor: AppColors.dmBubbleIn,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Today')),
                  DropdownMenuItem(value: 7, child: Text('7 days')),
                  DropdownMenuItem(value: 30, child: Text('30 days')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _days = v;
                  _load();
                },
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? EmptyNote(icon: Icons.error_outline, title: "Couldn't write the catch-up", text: _error)
                  : _result == null
                      ? const Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            CircularProgressIndicator(strokeWidth: 2.4),
                            SizedBox(height: 12),
                            Muted('Reading your teams’ meetings, decisions and commitments…'),
                          ]),
                        )
                      : ListView(children: [
                          FormattedText(_result!['brief'] as String? ?? '',
                              style: TextStyle(fontSize: 14.5, color: AppColors.dmText, height: 1.5)),
                          if ((_result!['sources'] as List?)?.isNotEmpty == true) ...[
                            const SectionTitle('Sources'),
                            for (final s in List<Map>.from(_result!['sources'])) Muted('${s['ref']} · ${s['title'] ?? ''}', maxLines: 1),
                          ],
                        ]),
            ),
          ]),
        ),
      ),
    );
  }
}
