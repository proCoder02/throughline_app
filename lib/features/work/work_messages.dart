import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/formatted_text.dart';
import 'work_api.dart';
import 'work_context.dart';
import 'work_glass.dart';
import 'work_live.dart';
import 'work_ui.dart';

/// Work chat: a thread per team I'm in, plus direct messages with anyone in
/// the organisation. What's said here feeds the organisation's memory
/// (commitments and decisions are picked up from it), same as on the web.
class MessagesTab extends StatefulWidget {
  final WorkContext work;
  final VoidCallback? onUnreadChanged;
  const MessagesTab({super.key, required this.work, this.onUnreadChanged});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final _listKey = GlobalKey<CachedLoadState>();

  Future<void> _open(Map t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ThreadScreen(
          work: widget.work, threadId: t['id'] as int, title: t['name'] as String? ?? 'Conversation', team: t['kind'] == 'team'),
    ));
    _listKey.currentState?.reload();
    widget.onUnreadChanged?.call();
  }

  Widget _tile(Map t) {
    final team = t['kind'] == 'team';
    final unread = (t['unread'] as num?)?.toInt() ?? 0;
    final name = t['name'] as String? ?? '';
    return ListTile(
      onTap: () => _open(t),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: (team ? AppColors.dmAccent : const Color(0xFF6B8FD9)).withValues(alpha: 0.18),
        child: team
            ? const Icon(Icons.groups_rounded, color: AppColors.dmAccentDark)
            : Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF3F64B0))),
      ),
      title: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600, color: AppColors.dmText)),
      subtitle: Muted(t['last_body'] as String? ?? (team ? 'Team conversation' : 'Direct message'), maxLines: 1),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Muted(fmtDay(t['last_message_at'] as String?), size: 12),
        if (unread > 0) ...[
          const SizedBox(height: 4),
          Badge(label: Text('$unread'), backgroundColor: AppColors.dmAccent),
        ],
      ]),
    );
  }

  Future<void> _newDirect() async {
    final person = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dmBubbleIn,
      builder: (_) => _PeoplePicker(work: widget.work),
    );
    if (person == null || !mounted) return;
    try {
      final tid = await WorkApi.instance.directThread(widget.work.orgId, person['user_id'] as int);
      if (!mounted) return;
      await _open({'id': tid, 'name': person['username'], 'kind': 'direct'});
    } catch (e) {
      if (mounted) showWorkSnack(context, workError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = widget.work.orgId;
    return WorkPage(
      title: 'Messages',
      leading: widget.work.leading(context),
      fab: FloatingActionButton(
        onPressed: _newDirect,
        backgroundColor: AppColors.dmAccent,
        foregroundColor: Colors.white,
        tooltip: 'New message',
        child: const Icon(Icons.edit_outlined),
      ),
      body: CachedLoad(
        key: _listKey,
        cacheKey: 'threads:$org',
        fetch: () => WorkApi.instance.threads(org),
        builder: (context, data, reload) {
          final threads = List<Map>.from((data as Map)['threads'] ?? []);
          if (threads.isEmpty) {
            return ListView(children: const [
              EmptyNote(
                  icon: Icons.forum_outlined,
                  title: 'No conversations yet',
                  text: 'You get a thread for each team you join. Tap ✎ to message someone.'),
            ]);
          }
          return ListView(padding: EdgeInsets.fromLTRB(12, 4, 12, listEnd(context, 90)), children: [
            Frosted(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                for (var i = 0; i < threads.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 72, endIndent: 16, color: AppColors.dmBubbleBorder),
                  _tile(threads[i]),
                ],
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _PeoplePicker extends StatefulWidget {
  final WorkContext work;
  const _PeoplePicker({required this.work});

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Message someone at ${widget.work.orgName}',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Expanded(
            child: CachedLoad(
              cacheKey: 'members:${widget.work.orgId}',
              fetch: () => WorkApi.instance.members(widget.work.orgId),
              builder: (context, data, _) {
                final people = List<Map>.from((data as Map)['members'] ?? [])
                    .where((m) => m['user_id'] != widget.work.meId && m['status'] != 'left')
                    .where((m) => _q.isEmpty || '${m['username']} ${m['title'] ?? ''}'.toLowerCase().contains(_q))
                    .toList();
                return ListView(children: [
                  for (final m in people)
                    ListTile(
                      leading: CircleAvatar(child: Text((m['username'] as String? ?? '?')[0].toUpperCase())),
                      title: Text(m['username'] as String? ?? ''),
                      subtitle: Muted(
                          [
                            if (m['title'] != null && (m['title'] as String).isNotEmpty) m['title'],
                            ...List<Map>.from(m['units'] ?? []).map((u) => u['name']),
                          ].join(' · '),
                          maxLines: 1),
                      onTap: () => Navigator.pop(context, m),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// One conversation. New messages arrive live over the app's /ws/notify
/// connection (see WorkLive); a slow poll covers a dropped connection.
/// Messages written offline show as "Waiting to send" until they go.
class ThreadScreen extends StatefulWidget {
  final WorkContext work;
  final int threadId;
  final String title;
  final bool team;
  const ThreadScreen({super.key, required this.work, required this.threadId, required this.title, required this.team});

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _api = WorkApi.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map> _messages = [];
  List<Map> _kept = []; // written offline, not sent yet
  StreamSubscription? _live;
  bool _loaded = false;
  bool _sending = false;
  String? _error;
  Timer? _poll;

  int get _org => widget.work.orgId;
  int get _lastId => _messages.isEmpty ? 0 : (_messages.last['id'] as int);

  @override
  void initState() {
    super.initState();
    WorkLive.instance.activeThreadId = widget.threadId;
    _live = WorkLive.instance.messages.listen((e) {
      if (e['thread_id'] == widget.threadId) _fetchNew();
    });
    WorkApi.instance.pending.addListener(_loadKept);
    _loadKept();
    _start();
  }

  Future<void> _loadKept() async {
    final kept = await _api.keptFor(_api.messagesPath(_org, widget.threadId));
    if (!mounted) return;
    final hadKept = _kept.isNotEmpty;
    setState(() => _kept = kept);
    if (hadKept && kept.isEmpty) _fetchNew(); // they were just sent
  }

  Future<void> _start() async {
    final cached = await _api.cached('messages:$_org:${widget.threadId}');
    if (cached != null && mounted && !_loaded) {
      setState(() => _messages = List<Map>.from((cached as Map)['messages'] ?? []));
    }
    try {
      final r = await _api.messages(_org, widget.threadId);
      if (!mounted) return;
      setState(() {
        _messages = List<Map>.from(r['messages'] ?? []);
        _loaded = true;
        _error = null;
      });
      _markRead();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = workError(e);
        });
      }
    }
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _fetchNew());
  }

  Future<void> _fetchNew() async {
    try {
      final r = await _api.messages(_org, widget.threadId, after: _lastId);
      final more = List<Map>.from(r['messages'] ?? []);
      if (more.isEmpty || !mounted) return;
      final have = _messages.map((m) => m['id']).toSet();
      setState(() => _messages = [..._messages, ...more.where((m) => !have.contains(m['id']))]);
      _markRead();
    } catch (_) {/* keep what's on screen; next tick retries */}
  }

  void _markRead() {
    if (_lastId > 0) _api.markRead(_org, widget.threadId, _lastId).catchError((_) {});
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final sentNow = await _api.sendMessage(_org, widget.threadId, text);
      _input.clear();
      if (sentNow) {
        await _fetchNew();
      } else {
        await _loadKept();
      }
    } catch (e) {
      if (mounted) showWorkSnack(context, workError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _live?.cancel();
    WorkApi.instance.pending.removeListener(_loadKept);
    if (WorkLive.instance.activeThreadId == widget.threadId) WorkLive.instance.activeThreadId = null;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = [
      for (final k in _kept.reversed)
        {'id': -1, 'sender_id': widget.work.meId, 'kind': 'text', 'body': (k['data'] as Map)['body'], 'created_at': k['at'], 'kept': true},
      ..._messages.reversed,
    ];
    return WorkPage(
      title: widget.title,
      body: Column(children: [
        Expanded(
          child: !_loaded && _messages.isEmpty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
              : list.isEmpty
                  ? EmptyNote(
                      icon: Icons.chat_bubble_outline,
                      title: _error == null ? 'Say hello' : "Couldn't load messages",
                      text:
                          _error ?? (widget.team ? 'Everyone in ${widget.title} sees this conversation.' : 'Only the two of you see this.'),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final m = list[i];
                        final older = i + 1 < list.length ? list[i + 1] : null;
                        return _Bubble(
                          m: m,
                          mine: m['sender_id'] == widget.work.meId,
                          showName: widget.team && older?['sender_id'] != m['sender_id'],
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            padding: const EdgeInsets.only(left: 14, right: 4),
            decoration: BoxDecoration(
              color: AppColors.dmBubbleIn,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.dmBubbleBorder),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(border: InputBorder.none, hintText: 'Message ${widget.title}'),
                ),
              ),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send_rounded, color: AppColors.dmAccent),
                tooltip: 'Send',
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Map m;
  final bool mine;
  final bool showName;
  const _Bubble({required this.m, required this.mine, required this.showName});

  @override
  Widget build(BuildContext context) {
    final special = m['kind'] != null && m['kind'] != 'text';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: EdgeInsets.only(top: showName ? 10 : 3, bottom: 1),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: special ? AppColors.dmAccent.withValues(alpha: 0.12) : (mine ? AppColors.dmBubbleOut : AppColors.dmBubbleIn),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dmBubbleBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (showName && !mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(m['sender'] as String? ?? 'Throughline',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dmAccentDark)),
            ),
          if (special)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome, size: 14, color: AppColors.dmAccentDark),
                const SizedBox(width: 4),
                Text((m['kind'] as String).replaceAll('_', ' '),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dmAccentDark)),
              ]),
            ),
          FormattedText(_body(), style: TextStyle(fontSize: 14.5, color: AppColors.dmText, height: 1.35)),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.bottomRight,
            child: m['kept'] == true
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.schedule, size: 13, color: workSoftText),
                    const SizedBox(width: 3),
                    const Muted('Waiting to send', size: 12),
                  ])
                : Muted(fmtTime(m['created_at'] as String?), size: 12),
          ),
        ]),
      ),
    );
  }

  String _body() {
    if (m['kind'] == 'common_ground' && m['meta'] is Map) {
      final meta = (m['meta'] as Map)['result'] is Map ? (m['meta'] as Map)['result'] as Map : m['meta'] as Map;
      String list(String k) => (meta[k] as List).map((x) => '- ${x is Map ? '${x['name'] ?? ''}: ${x['position'] ?? ''}' : x}').join('\n');
      final parts = <String>[
        if (meta['positions'] is List && (meta['positions'] as List).isNotEmpty) '**Where people stand**\n${list('positions')}',
        if (meta['options'] is List && (meta['options'] as List).isNotEmpty) '**Options**\n${list('options')}',
        if (meta['agreed'] is List && (meta['agreed'] as List).isNotEmpty) '**Agreed**\n${list('agreed')}',
        if (meta['open'] is List && (meta['open'] as List).isNotEmpty) '**Still open**\n${list('open')}',
      ];
      if (parts.isNotEmpty) return parts.join('\n\n');
    }
    return m['body'] as String? ?? '';
  }
}
