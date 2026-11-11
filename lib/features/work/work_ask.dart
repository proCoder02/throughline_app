import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../widgets/formatted_text.dart';
import 'work_api.dart';
import 'work_commitments.dart';
import 'work_context.dart';
import 'work_glass.dart';
import 'work_meetings.dart';
import 'work_messages.dart';
import 'work_ui.dart';

/// Ask about my teams' history -- same as the website's Ask: answers come
/// only from meetings, decisions, commitments and chat in teams I'm in, and
/// every answer links to where it came from. Each question is answered on
/// its own; the thread stays while the Work section is open.
class AskTab extends StatefulWidget {
  final WorkContext work;
  const AskTab({super.key, required this.work});

  @override
  State<AskTab> createState() => _AskTabState();
}

class _AskTabState extends State<AskTab> with AutomaticKeepAliveClientMixin {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _turns = [];
  int? _threadId; // the saved conversation on screen (null: a new chat)
  String? _threadTitle;
  bool _loadingThread = false;
  int? _unitId;
  bool _sending = false;

  static const _starters = [
    ('Decisions', 'What did we decide about the database migration?'),
    ('Pending', 'What is still pending from our last meetings?'),
    ('This week', 'Who owes what this week?'),
    ('Risks', 'Which commitments are overdue or at risk?'),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _ask(String q, {int? unit}) async {
    setState(() {
      _sending = true;
    });
    _toEnd();
    try {
      final asked = _threadId;
      final r = await WorkApi.instance.ask(widget.work.orgId, q, unitId: unit, threadId: asked);
      if (_threadId != asked) return; // switched chats meanwhile; it's saved in its own thread
      _threadId ??= r['thread_id'] as int?;
      _threadTitle ??= q;
      _turns.add({'role': 'assistant', 'text': r['answer'] ?? 'No answer.', 'sources': r['sources'] ?? []});
    } catch (e) {
      _turns.add({'role': 'assistant', 'text': "Couldn't get an answer -- ${workError(e)}", 'error': true, 'q': q, 'unit': unit});
    }
    if (mounted) setState(() => _sending = false);
    _toEnd();
  }

  void _newChat() => setState(() {
        _turns.clear();
        _threadId = null;
        _threadTitle = null;
      });

  Future<void> _openThread(Map t) async {
    setState(() {
      _turns.clear();
      _threadId = t['id'] as int;
      _threadTitle = t['title'] as String?;
      _loadingThread = true;
    });
    try {
      final d = await WorkApi.instance.askThread(widget.work.orgId, t['id'] as int);
      if (!mounted || _threadId != t['id']) return;
      setState(() {
        for (final m in List<Map>.from(d['messages'] ?? [])) {
          _turns.add(m['role'] == 'user'
              ? {'role': 'user', 'text': m['content'], 'scope': m['unit_name']}
              : {'role': 'assistant', 'text': m['content'], 'sources': m['sources'] ?? []});
        }
      });
      _toEnd();
    } catch (e) {
      if (mounted) showWorkSnack(context, workError(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingThread = false);
    }
  }

  /// My saved Ask conversations: open one, or delete it.
  Future<void> _showChats() async {
    final picked = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatsSheet(work: widget.work, current: _threadId),
    );
    if (!mounted) return;
    if (picked == null) return;
    if (picked['_deleted'] == _threadId) {
      _newChat();
    } else if (picked['id'] != null) {
      _openThread(picked);
    }
  }

  void _submit([String? text]) {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _sending) return;
    _input.clear();
    final unit = widget.work.myUnits.where((u) => u['id'] == _unitId).firstOrNull;
    _turns.add({'role': 'user', 'text': q, 'scope': unit?['name']});
    _ask(q, unit: _unitId);
  }

  void _openSource(Map s) {
    final id = s['id'] as int;
    final work = widget.work;
    final Widget page = switch (s['type']) {
      'meeting' => MeetingScreen(work: work, id: id, title: s['title'] as String? ?? 'Meeting'),
      'decision' => DecisionScreen(work: work, id: id),
      'message' => ThreadScreen(work: work, threadId: id, title: 'Conversation', team: true),
      _ => CommitmentScreen(work: work, id: id),
    };
    if (s['type'] == 'commitment') {
      openCommitment(context, work, id);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final units = widget.work.myUnits;
    return WorkPage(
      title: _threadTitle ?? 'Ask',
      leading: widget.work.leading(context),
      actions: [
        IconButton(tooltip: 'Your chats', onPressed: _sending ? null : _showChats, icon: const Icon(Icons.history)),
        if (_turns.isNotEmpty || _threadId != null)
          IconButton(tooltip: 'New chat', onPressed: _sending ? null : _newChat, icon: const Icon(Icons.add_comment_outlined)),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(MediaQuery.textScalerOf(context).scale(44).clamp(44, 96)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            Icon(Icons.groups_outlined, size: 18, color: AppColors.dmTextSoft),
            const SizedBox(width: 8),
            Text('Team', style: TextStyle(color: AppColors.dmTextSoft, fontSize: 13)),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  isExpanded: true,
                  value: _unitId,
                  dropdownColor: AppColors.dmBubbleIn,
                  style: TextStyle(color: AppColors.dmText, fontSize: 14, fontWeight: FontWeight.w600),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('All my teams')),
                    for (final u in units) DropdownMenuItem<int?>(value: u['id'] as int, child: Text(u['name'] as String? ?? '')),
                  ],
                  onChanged: (v) => setState(() => _unitId = v),
                ),
              ),
            ),
          ]),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: _loadingThread
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
              : _turns.isEmpty && !_sending
                  ? ListView(padding: const EdgeInsets.fromLTRB(18, 28, 18, 12), children: [
                      Center(
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.dmAccent.withValues(alpha: 0.15),
                          child: const Icon(Icons.auto_awesome, color: AppColors.dmAccentDark),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('What do you want to know about your work?',
                          textAlign: TextAlign.center, style: appHeadlineFont(color: AppColors.dmText, fontSize: 21)),
                      const SizedBox(height: 8),
                      const Center(
                        child: Muted(
                            'Answers come only from meetings, decisions, commitments and chat in teams you’re in, with links to where they came from.',
                            size: 13.5),
                      ),
                      const SizedBox(height: 20),
                      for (final (title, prompt) in _starters)
                        WorkCard(
                          onTap: () => setState(() => _input.text = prompt),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.dmText)),
                            const SizedBox(height: 2),
                            Muted(prompt, size: 13),
                          ]),
                        ),
                    ])
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      children: [
                        for (final t in _turns) t['role'] == 'user' ? _userTurn(t) : _answerTurn(t),
                        if (_sending)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 10),
                              Muted('Searching your teams’ history…', size: 13.5),
                            ]),
                          ),
                      ],
                    ),
        ),
        SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              padding: const EdgeInsets.only(left: 16, right: 4),
              decoration: BoxDecoration(
                color: AppColors.dmBubbleIn,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.dmAccent.withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 500,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                      hintText: _unitId == null
                          ? 'Ask about your team’s history…'
                          : 'Ask about ${units.where((u) => u['id'] == _unitId).firstOrNull?['name'] ?? 'this team'}…',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _submit,
                  icon: const Icon(Icons.arrow_upward_rounded, color: AppColors.dmAccent),
                  tooltip: 'Ask',
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Muted('Follow-ups use this chat’s earlier questions. Check the sources.', size: 12),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _userTurn(Map t) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 6, bottom: 12, left: 48),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(color: AppColors.dmAccent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(t['text'] as String, style: TextStyle(color: AppColors.dmText, fontSize: 14.5)),
            if (t['scope'] != null) ...[const SizedBox(height: 2), Muted('in ${t['scope']}', size: 12)],
          ]),
        ),
      );

  Widget _answerTurn(Map t) {
    final sources = List<Map>.from(t['sources'] ?? []);
    const kind = {'meeting': 'Meeting', 'decision': 'Decision', 'commitment': 'Commitment', 'message': 'Chat'};
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: AppColors.dmAccent.withValues(alpha: 0.15),
          child: const Icon(Icons.auto_awesome, size: 14, color: AppColors.dmAccentDark),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (t['error'] == true) ...[
              Text(t['text'] as String, style: const TextStyle(color: AppColors.danger)),
              TextButton.icon(
                onPressed: _sending
                    ? null
                    : () {
                        setState(() => _turns.remove(t));
                        _ask(t['q'] as String, unit: t['unit'] as int?);
                      },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ] else
              FormattedText(t['text'] as String, style: TextStyle(fontSize: 14.5, color: AppColors.dmText, height: 1.5)),
            if (sources.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in sources)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _openSource(s),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 260, minHeight: 48),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.dmPillFill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.dmBubbleBorder),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Muted('${kind[s['type']] ?? s['type']} · ${s['ref']}', size: 12),
                        Text(s['title'] as String? ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.dmText)),
                      ]),
                    ),
                  ),
              ]),
            ],
            if (t['error'] != true)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Copy',
                  icon: Icon(Icons.copy_rounded, size: 17, color: AppColors.dmTextSoft),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: t['text'] as String));
                    showWorkSnack(context, 'Copied');
                  },
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// The list of saved Ask conversations.
class _ChatsSheet extends StatefulWidget {
  final WorkContext work;
  final int? current;
  const _ChatsSheet({required this.work, required this.current});

  @override
  State<_ChatsSheet> createState() => _ChatsSheetState();
}

class _ChatsSheetState extends State<_ChatsSheet> {
  int _gen = 0;

  Future<void> _delete(Map t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${t['title']}”?'),
        content: const Text('This conversation is removed for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await WorkApi.instance.deleteAskThread(widget.work.orgId, t['id'] as int);
      if (!mounted) return;
      if (t['id'] == widget.current) {
        Navigator.pop(context, {'_deleted': t['id']});
      } else {
        setState(() => _gen++);
      }
    } catch (e) {
      if (mounted) showWorkSnack(context, workError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 28,
      blur: 24,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
              child: Row(children: [
                Expanded(child: Text('Your chats', style: appHeadlineFont(color: AppColors.dmText, fontSize: 18))),
                IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
            ),
            Expanded(
              child: CachedLoad(
                key: ValueKey('chats$_gen'),
                cacheKey: 'ask-threads:${widget.work.orgId}',
                fetch: () => WorkApi.instance.askThreads(widget.work.orgId),
                builder: (context, data, _) {
                  final items = List<Map>.from((data as Map)['threads'] ?? []);
                  if (items.isEmpty) {
                    return ListView(children: const [
                      EmptyNote(
                          icon: Icons.forum_outlined,
                          title: 'No chats yet',
                          text: 'Your Ask conversations are kept here, on the website too.'),
                    ]);
                  }
                  return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), children: [
                    for (final t in items)
                      ListTile(
                        minVerticalPadding: 10,
                        selected: t['id'] == widget.current,
                        selectedTileColor: AppColors.dmAccent.withValues(alpha: 0.14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        title: Text(t['title'] as String? ?? 'Untitled', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Muted(
                            [fmtTime(t['updated_at'] as String?), if ((t['questions'] as num? ?? 0) > 1) '${t['questions']} questions']
                                .join(' · '),
                            size: 12),
                        trailing: IconButton(tooltip: 'Delete', onPressed: () => _delete(t), icon: const Icon(Icons.delete_outline)),
                        onTap: () => Navigator.pop(context, t),
                      ),
                  ]);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
