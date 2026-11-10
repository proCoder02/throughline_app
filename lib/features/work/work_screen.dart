import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'work_api.dart';
import 'work_ask.dart';
import 'work_commitments.dart';
import 'work_context.dart';
import 'work_glass.dart';
import 'work_home.dart';
import 'work_live.dart';
import 'work_meetings.dart';
import 'work_messages.dart';
import 'work_ui.dart';

/// The phone's Work (Corporate) section -- the employee side only.
///
/// What's here: what needs me, work messages, commitments (with updates and
/// blockers), meetings, decisions, Ask and catch-up, and joining an
/// organisation I've been invited to.
/// What's deliberately not here: creating an organisation, departments and
/// teams, adding or removing people, roles, invitations, projects and
/// organisation settings. Those are done by admins on the website.
class WorkScreen extends StatefulWidget {
  /// Opened from a notification: the conversation or commitment to show.
  final WorkTarget? target;
  const WorkScreen({super.key, this.target});

  static const routeName = '/work';

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> {
  final _api = WorkApi.instance;
  List<Map>? _orgs;
  Map? _orgData;
  String? _error;
  int _tab = 0;
  final Set<int> _visited = {0}; // a tab loads the first time it's opened
  Map<int, int> _unreadByOrg = {};
  Timer? _unreadPoll;
  WorkTarget? _target; // waiting until its organisation is loaded
  StreamSubscription? _refusedSub;
  StreamSubscription? _liveSub;

  @override
  void initState() {
    super.initState();
    _target = widget.target;
    WorkLive.instance.openInPlace = _goTo;
    _refusedSub = _api.refused.stream.listen((m) {
      if (mounted) showWorkSnack(context, m, error: true);
    });
    // Live work messages: keep the Messages badge current without waiting for the poll.
    _liveSub = WorkLive.instance.messages.listen((e) {
      final org = (e['org_id'] as num?)?.toInt();
      if (org != null && mounted && e['thread_id'] != WorkLive.instance.activeThreadId) {
        setState(() => _unreadByOrg[org] = (_unreadByOrg[org] ?? 0) + 1);
      }
    });
    _start();
    _api.flush();
    _unreadPoll = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshUnread();
      _api.flush();
    });
  }

  @override
  void dispose() {
    _unreadPoll?.cancel();
    _refusedSub?.cancel();
    _liveSub?.cancel();
    if (WorkLive.instance.openInPlace == _goTo) WorkLive.instance.openInPlace = null;
    WorkLive.instance.rememberMode('personal');
    super.dispose();
  }

  /// A notification tapped while Work is open: switch organisation if
  /// needed, then open the item.
  void _goTo(WorkTarget t) {
    _target = t;
    final current = _orgData?['org']?['id'];
    if (t.orgId != null && t.orgId != current && (_orgs ?? []).any((o) => o['id'] == t.orgId)) {
      _api.remember('selected_org', t.orgId!);
      setState(() {
        _orgData = null;
        _tab = 0;
        _visited
          ..clear()
          ..add(0);
      });
      _refresh(t.orgId);
    } else {
      _openTarget();
    }
  }

  void _openTarget() {
    final t = _target;
    final data = _orgData;
    if (t == null || data == null || _orgs == null) return;
    if (t.orgId != null && data['org']?['id'] != t.orgId) return; // still loading the right org
    _target = null;
    final work = WorkContext.fromOrg(data, _orgs!, _switchOrg);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      // Close whatever detail screen is open on top of Work first.
      nav.popUntil((r) => r.settings.name == WorkScreen.routeName || r.isFirst);
      if (t.threadId != null) {
        setState(() {
          _tab = 1;
          _visited.add(1);
        });
        nav.push(MaterialPageRoute(
          builder: (_) => ThreadScreen(work: work, threadId: t.threadId!, title: t.threadTitle ?? 'Conversation', team: t.team),
        ));
      } else if (t.commitmentId != null) {
        openCommitment(context, work, t.commitmentId!);
      } else {
        setState(() {
          _tab = 0;
          _visited.add(0);
        });
      }
    });
  }

  Future<void> _start() async {
    // Instant: last-known organisation from this phone.
    final cachedMe = await _api.cached('me');
    final saved = widget.target?.orgId ?? await _api.cached('selected_org');
    if (cachedMe is Map && mounted) {
      final orgs = _active(cachedMe);
      final id = _pick(orgs, saved);
      final cachedOrg = id == null ? null : await _api.cached('org:$id');
      if (mounted && _orgs == null) {
        setState(() {
          _orgs = orgs;
          _orgData = cachedOrg is Map ? cachedOrg : null;
        });
      }
    }
    await _refresh(saved);
  }

  List<Map> _active(Map me) => List<Map>.from(me['orgs'] ?? []).where((o) => o['status'] != 'left').toList();

  int? _pick(List<Map> orgs, dynamic saved) {
    if (orgs.isEmpty) return null;
    return orgs.any((o) => o['id'] == saved) ? saved as int : orgs.first['id'] as int;
  }

  Future<void> _refresh([dynamic saved]) async {
    try {
      final me = await _api.me();
      final orgs = _active(me);
      final id = _pick(orgs, saved ?? _orgData?['org']?['id']);
      final org = id == null ? null : await _api.org(id);
      if (!mounted) return;
      setState(() {
        _orgs = orgs;
        _orgData = org;
        _error = null;
      });
      _refreshUnread();
      _openTarget();
    } catch (e) {
      if (mounted) setState(() => _error = workError(e));
    }
  }

  Future<void> _refreshUnread() async {
    try {
      final r = await _api.unread();
      final by = (r['by_org'] as Map?) ?? {};
      if (mounted) setState(() => _unreadByOrg = {for (final e in by.entries) int.parse('${e.key}'): (e.value as num).toInt()});
      WorkLive.instance.unread.value = (r['total'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  Future<void> _switchOrg() async {
    final orgs = _orgs ?? [];
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.dmBubbleIn,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
              padding: EdgeInsets.all(16), child: Text('Organisation', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          for (final o in orgs)
            ListTile(
              leading: const Icon(Icons.apartment_rounded),
              title: Text(o['name'] as String? ?? ''),
              subtitle: Text('${o['member_count']} people'),
              trailing: o['id'] == _orgData?['org']?['id'] ? const Icon(Icons.check, color: AppColors.dmAccent) : null,
              onTap: () => Navigator.pop(ctx, o['id'] as int),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    await _api.remember('selected_org', picked);
    setState(() {
      _orgData = null;
      _tab = 0;
      _visited
        ..clear()
        ..add(0);
    });
    final cached = await _api.cached('org:$picked');
    if (mounted && cached is Map) setState(() => _orgData = cached);
    await _refresh(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (_orgs == null) {
      return WorkPage(
        title: 'Work',
        body: _error == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(children: [EmptyNote(icon: Icons.cloud_off_outlined, title: "Couldn't open Work", text: _error)]),
              ),
      );
    }
    if (_orgs!.isEmpty) return _NoOrg(onJoined: _refresh);
    if (_orgData == null) {
      return const WorkPage(title: 'Work', body: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    final work = WorkContext.fromOrg(_orgData!, _orgs!, _switchOrg);
    final unread = _unreadByOrg[work.orgId] ?? 0;
    final tabs = [
      HomeTab(key: ValueKey('home${work.orgId}'), work: work),
      MessagesTab(key: ValueKey('msg${work.orgId}'), work: work, onUnreadChanged: _refreshUnread),
      CommitmentsTab(key: ValueKey('com${work.orgId}'), work: work),
      MeetingsTab(key: ValueKey('meet${work.orgId}'), work: work),
      AskTab(key: ValueKey('ask${work.orgId}'), work: work),
    ];
    return Scaffold(
      // The bar floats over the content (glass); lists get its height as bottom padding.
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: IndexedStack(
          index: _tab, children: [for (var i = 0; i < tabs.length; i++) _visited.contains(i) ? tabs[i] : const SizedBox.shrink()]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const _OutboxStrip(),
        GlassNavBar(
          index: _tab,
          onTap: (i) {
            setState(() {
              _tab = i;
              _visited.add(i);
            });
            if (i == 1) _refreshUnread();
          },
          items: [
            const GlassNavItem(Icons.wb_sunny_outlined, Icons.wb_sunny, 'Home'),
            GlassNavItem(Icons.forum_outlined, Icons.forum, 'Messages', badge: unread),
            const GlassNavItem(Icons.task_alt_outlined, Icons.task_alt, 'Commitments'),
            const GlassNavItem(Icons.groups_2_outlined, Icons.groups_2, 'Meetings'),
            const GlassNavItem(Icons.auto_awesome_outlined, Icons.auto_awesome, 'Ask'),
          ],
        ),
      ]),
    );
  }
}

/// Changes made offline that haven't been sent yet.
class _OutboxStrip extends StatelessWidget {
  const _OutboxStrip();

  @override
  Widget build(BuildContext context) {
    final api = WorkApi.instance;
    return ValueListenableBuilder<int>(
      valueListenable: api.pending,
      builder: (context, n, _) => n == 0
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: GlassPanel(
                radius: 18,
                padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
                child: Row(children: [
                  Icon(Icons.cloud_upload_outlined, size: 18, color: AppColors.dmText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      n == 1 ? '1 change waiting to send' : '$n changes waiting to send',
                      style: TextStyle(fontSize: 13, color: AppColors.dmText),
                    ),
                  ),
                  TextButton(onPressed: api.flush, child: const Text('Send now')),
                ]),
              ),
            ),
    );
  }
}

/// Not in any organisation yet: show invitations to join. There is no
/// "create an organisation" here -- that's done on the website.
class _NoOrg extends StatelessWidget {
  final Future<void> Function() onJoined;
  const _NoOrg({required this.onJoined});

  @override
  Widget build(BuildContext context) {
    return WorkPage(
      title: 'Work',
      body: CachedLoad(
        cacheKey: null,
        fetch: () => WorkApi.instance.myInvites(),
        builder: (context, data, reload) {
          final invites = List<Map>.from((data as Map)['invites'] ?? []);
          final email = data['email'] as String?;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            if (invites.isEmpty)
              EmptyNote(
                icon: Icons.apartment_rounded,
                title: "You're not in an organisation yet",
                text: 'Your company sets Throughline up on the website, then invites you'
                    '${email != null ? ' at $email' : ''}. Invitations show up here.',
              )
            else ...[
              SectionTitle('Invitations', count: invites.length),
              for (final i in invites)
                WorkCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i['org_name'] as String? ?? '',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dmText)),
                    const SizedBox(height: 4),
                    Muted([
                      if (i['unit_name'] != null) 'Team: ${i['unit_name']}',
                      if (i['invited_by'] != null) 'Invited by ${i['invited_by']}',
                    ].join(' · ')),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () async {
                        try {
                          await WorkApi.instance.acceptInvite(i['id'] as int);
                          await onJoined();
                        } catch (e) {
                          if (context.mounted) showWorkSnack(context, workError(e), error: true);
                        }
                      },
                      child: const Text('Join'),
                    ),
                  ]),
                ),
            ],
          ]);
        },
      ),
    );
  }
}
