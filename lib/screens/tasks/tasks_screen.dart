import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show notifyProvider;
import '../../models/task.dart';
import '../../services/task_service.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../widgets/animated_task_checkbox.dart';
import '../../widgets/category_chip_bar.dart';
import '../../widgets/chat_list_skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/fade_collapse.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/offline_banner.dart';
import '../chats/chat_thread_screen.dart';

class TasksScreen extends StatefulWidget {
  /// Opens HomeShell's side drawer (the retired bottom nav's replacement) --
  /// null when this screen is reached some other way than the shell (there
  /// isn't one today, but this keeps the screen usable standalone).
  final VoidCallback? onOpenDrawer;

  const TasksScreen({super.key, this.onOpenDrawer});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _service = TaskService();
  List<Task>? _tasks;
  bool _loading = true;
  Object? _error;
  bool _offline = false;
  String _status = 'open';
  String? _category;

  // Removed the instant a delete is confirmed (see _confirmDelete), before
  // the DELETE request even starts -- without this, the swiped row stays
  // tappable for the full network round-trip + _reload(), so a second tap
  // (or the same swipe registering twice) hits an already-deleted task and
  // gets a 404, which then surfaced as a confusing "Failed to delete task"
  // even though the first delete had actually already succeeded.
  final Set<int> _deletedIds = {};

  // Rows currently fading+collapsing out (FadeCollapse) -- distinct from
  // _deletedIds above: a row stays in the visible list while its id is
  // only here, so the delete reads as a smooth fade rather than an
  // instant pop. It only actually leaves the list (added to _deletedIds)
  // once that animation finishes -- see _performDelete.
  final Set<int> _fadingIds = {};

  static const _statusLabels = {'open': 'Open', 'done': 'Done', 'all': 'All'};

  @override
  void initState() {
    super.initState();
    // Show the on-device copy instantly if there is one, then always refresh
    // from the network in the background -- same cache-first pattern as
    // ChatsScreen, so this tab still shows its last-known list offline.
    final cached = _service.listCached(_status);
    if (cached != null) {
      _tasks = cached;
      _loading = false;
    }
    _load();
    notifyProvider.clearTaskBadge();
    notifyProvider.addListener(_onNotify);
  }

  // HomeShell's IndexedStack keeps this screen's state alive across tab
  // switches (see its own doc comment), so initState's _load() above only
  // ever runs once per app session -- a task created later (e.g. a reminder
  // detected in chat, well after this tab was first visited) would
  // otherwise never appear without a manual pull-to-refresh. taskBadge
  // already increments on every task_created event regardless of which tab
  // is showing, so it doubles as "a task arrived since we last checked".
  void _onNotify() {
    if (notifyProvider.taskBadge > 0) {
      notifyProvider.clearTaskBadge();
      _load();
    }
  }

  @override
  void dispose() {
    notifyProvider.removeListener(_onNotify);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _service.list(status: _status);
      if (!mounted) return;
      setState(() {
        _tasks = items;
        _loading = false;
        _error = null;
        _offline = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
        if (_tasks == null) _error = e;
      });
    }
  }

  Future<void> _reload() => _load();

  void _switchStatus(String status) {
    setState(() {
      _status = status;
      _tasks = _service.listCached(status);
      _loading = _tasks == null;
    });
    _load();
  }

  Future<void> _toggle(Task task) async {
    HapticFeedback.lightImpact();
    final wasCompleting = !task.isDone;
    if (task.isDone) {
      await _service.reopen(task.id);
    } else {
      await _service.complete(task.id);
    }
    // _TaskRow already shows the change immediately (its own optimistic
    // local state) and is mid-animation right now -- reloading is what
    // actually re-fetches the list (usually filtered to "open"), which
    // would otherwise remove/reorder this row out from under that
    // animation well before it's had time to finish playing.
    await Future.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    _reload();
    // A little celebration exactly when this was the one that cleared the
    // open list -- not shown on every completion, just the moment it
    // actually means "you're done for now".
    if (wasCompleting && _status == 'open' && mounted) {
      final remaining = await _service.list(status: 'open');
      if (remaining.isEmpty && mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 All caught up! No open tasks left.'), duration: Duration(seconds: 3)),
        );
      }
    }
  }

  Future<void> _edit(Task task) async {
    final descController = TextEditingController(text: task.description);
    final dueController = TextEditingController(text: task.dueDate ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: descController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dueController,
              decoration: const InputDecoration(labelText: 'Due (e.g. Friday)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || descController.text.trim().isEmpty) return;
    await _service.edit(task.id, description: descController.text.trim(), dueDate: dueController.text.trim());
    _reload();
  }

  Future<void> _confirmDelete(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete task?'),
        content: const Text('This permanently removes the task.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    HapticFeedback.mediumImpact();
    // Starts the fade+collapse (see FadeCollapse wrapping this row below);
    // _performDelete actually removes it and calls the API once that
    // animation finishes, not before -- was an instant disappearance.
    setState(() => _fadingIds.add(task.id));
  }

  Future<void> _performDelete(Task task) async {
    if (!mounted) return;
    setState(() {
      _fadingIds.remove(task.id);
      _deletedIds.add(task.id);
    });
    try {
      await _service.delete(task.id);
      _reload();
    } on DioException catch (e) {
      // A 404 means it's already gone (a stale double-tap from before this
      // optimistic-removal fix, or deleted from another device) -- that's
      // the end state the user wanted anyway, not a real failure, so it
      // stays removed and no error shows. Anything else is a genuine
      // failure: roll back so the task reappears.
      if (e.response?.statusCode == 404) {
        _reload();
        return;
      }
      if (mounted) {
        setState(() => _deletedIds.remove(task.id));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete task')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _deletedIds.remove(task.id));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete task')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.dmGradient,
        ),
      ),
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.dmText),
        titleTextStyle: appHeadlineFont(color: AppColors.dmText, fontSize: 19),
        leading: widget.onOpenDrawer != null
            ? IconButton(icon: const Icon(Icons.menu), tooltip: 'Open menu', onPressed: widget.onOpenDrawer)
            : null,
        title: const Text('Tasks'),
        // Both filters used to live behind hidden icon-menus with no
        // visible indicator of what was currently selected -- a different,
        // less discoverable pattern than Chats' persistent chip bar for
        // the same "filter by category" concept (see this session's UX
        // audit). Now a persistent, always-visible pair of chip rows,
        // matching Chats exactly for category.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Column(
            children: [
              _StatusChipBar(selected: _status, onChanged: _switchStatus),
              const SizedBox(height: 6),
              CategoryChipBar(selected: _category, onChanged: (v) => setState(() => _category = v)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_offline) const OfflineBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: _buildBody(),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBody() {
    if (_tasks == null) {
      // Same shimmer skeleton as Chats' cold-start load -- was a bare
      // spinner here, a different loading treatment for a structurally
      // identical "list is loading" state (see this session's UX audit).
      if (_loading) return const ChatListSkeleton();
      return Center(child: Text('Failed to load tasks: $_error'));
    }
    var items = _tasks!.where((t) => !_deletedIds.contains(t.id)).toList();
    if (_category != null) items = items.where((t) => t.category == _category).toList();
    if (items.isEmpty) {
      return _status == 'open'
          ? const EmptyState(
              icon: Icons.celebration_outlined,
              title: 'All caught up!',
              subtitle: 'No open tasks right now.',
            )
          : EmptyState(
              icon: Icons.checklist_outlined,
              title: 'No ${_statusLabels[_status]!.toLowerCase()} tasks',
            );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final task = items[i];
        return FadeSlideIn(
          key: ValueKey('fade_${task.id}'),
          index: i,
          child: FadeCollapse(
            fading: _fadingIds.contains(task.id),
            onFadedOut: () => _performDelete(task),
            child: Slidable(
              key: ValueKey(task.id),
              endActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.25,
                children: [
                  SlidableAction(
                    onPressed: (_) => _confirmDelete(task),
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    icon: Icons.delete_outline,
                    label: 'Delete',
                  ),
                ],
              ),
              child: _TaskRow(
                task: task,
                onToggle: () => _toggle(task),
                onEdit: () => _edit(task),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Persistent status filter chips (Open/Done/All) -- same visual language
/// as CategoryChipBar (ChoiceChip, dmAccent when selected) so the two rows
/// read as one consistent filter bar rather than two different controls.
class _StatusChipBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _StatusChipBar({required this.selected, required this.onChanged});

  static const _labels = {'open': 'Open', 'done': 'Done', 'all': 'All'};

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final entry in _labels.entries) ...[
            _chip(label: entry.value, value: entry.key),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _chip({required String label, required String value}) {
    final isSelected = selected == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onChanged(value),
      selectedColor: AppColors.dmAccent,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.dmText,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: AppColors.dmPillFill,
      side: BorderSide(color: isSelected ? AppColors.dmAccent : AppColors.dmBubbleBorder),
    );
  }
}

/// Stateful now, not stateless -- purely so the checkbox can flip (and
/// start its draw-in animation) the instant this row is tapped. Previously
/// it just reflected `task.isDone` directly, which doesn't actually change
/// until the parent's own _toggle() finishes its API call *and* reloads the
/// list -- by which point (this list is usually filtered to "open") a
/// completed task's row had already been removed/reordered out from under
/// the animation, so it never had a chance to visibly play. This local
/// optimistic flag shows the change immediately; onToggle still does the
/// real completion, now with a matching delay before reload (see
/// _TasksScreenState._toggle) so this row survives long enough to animate.
class _TaskRow extends StatefulWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _TaskRow({required this.task, required this.onToggle, required this.onEdit});

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool? _optimisticDone;

  bool get _done => _optimisticDone ?? widget.task.isDone;

  void _handleTap() {
    setState(() => _optimisticDone = !_done);
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final details = [
      if (task.owner != null) 'Owner: ${task.owner}',
      if (task.dueDate != null) 'Due: ${task.dueDate}',
    ].join('  ·  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _handleTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: AnimatedTaskCheckbox(checked: _done),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task.description,
                        // Capped at 2 lines -- was unbounded, unlike every
                        // other row-title text in the app (see this
                        // session's UX audit).
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _done ? AppColors.dmTextSoft : AppColors.dmText,
                          decoration: _done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(details, style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft)),
                      ],
                    ],
                  ),
                ),
                if (task.emailSent)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2),
                    child: Icon(Icons.mail_outline, size: 18, color: AppColors.dmTextSoft),
                  ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.dmTextSoft),
                  tooltip: 'Edit',
                  onPressed: widget.onEdit,
                ),
                if (task.conversationId != null)
                  IconButton(
                    icon: Icon(Icons.chat_bubble_outline, size: 20, color: AppColors.dmTextSoft),
                    tooltip: 'View source conversation',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: task.conversationId!)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
