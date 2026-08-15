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
import '../../widgets/category_menu.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/offline_banner.dart';
import '../chats/chat_thread_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

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
    setState(() => _deletedIds.add(task.id));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            initialValue: _status,
            onSelected: _switchStatus,
            itemBuilder: (context) => _statusLabels.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
          ),
          CategoryMenu(selected: _category, onChanged: (v) => setState(() => _category = v)),
        ],
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
    );
  }

  Widget _buildBody() {
    if (_tasks == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
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
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border, indent: 56),
      itemBuilder: (context, i) {
        final task = items[i];
        return FadeSlideIn(
          key: ValueKey('fade_${task.id}'),
          index: i,
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
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _TaskRow({required this.task, required this.onToggle, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final details = [
      if (task.owner != null) 'Owner: ${task.owner}',
      if (task.dueDate != null) 'Due: ${task.dueDate}',
    ].join('  ·  ');

    return Material(
      color: AppColors.panel,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: task.isDone ? AppColors.accent : AppColors.textSoft,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.description,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: task.isDone ? AppColors.textSoft : AppColors.text,
                        decoration: task.isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(details, style: TextStyle(fontSize: 13.5, color: AppColors.textSoft)),
                    ],
                  ],
                ),
              ),
              if (task.emailSent)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Icon(Icons.mail_outline, size: 18, color: AppColors.textSoft),
                ),
              IconButton(
                icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.textSoft),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              if (task.conversationId != null)
                IconButton(
                  icon: Icon(Icons.chat_bubble_outline, size: 20, color: AppColors.textSoft),
                  tooltip: 'View source conversation',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: task.conversationId!)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
