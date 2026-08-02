import 'package:flutter/material.dart';

import '../../main.dart' show notifyProvider;
import '../../models/task.dart';
import '../../services/task_service.dart';
import '../../theme.dart';
import '../../widgets/category_menu.dart';
import '../chats/chat_thread_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _service = TaskService();
  late Future<List<Task>> _future;
  String _status = 'open';
  String? _category;

  static const _statusLabels = {'open': 'Open', 'done': 'Done', 'all': 'All'};

  @override
  void initState() {
    super.initState();
    _future = _service.list(status: _status);
    notifyProvider.clearTaskBadge();
  }

  void _reload() => setState(() => _future = _service.list(status: _status));

  Future<void> _toggle(Task task) async {
    if (task.isDone) {
      await _service.reopen(task.id);
    } else {
      await _service.complete(task.id);
    }
    _reload();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            initialValue: _status,
            onSelected: (v) => setState(() {
              _status = v;
              _future = _service.list(status: _status);
            }),
            itemBuilder: (context) => _statusLabels.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
          ),
          CategoryMenu(selected: _category, onChanged: (v) => setState(() => _category = v)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Task>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Failed to load tasks: ${snap.error}'));
            }
            var items = snap.data ?? [];
            if (_category != null) items = items.where((t) => t.category == _category).toList();
            if (items.isEmpty) {
              return Center(
                child: Text(
                  _status == 'open' ? 'No open tasks' : 'No ${_statusLabels[_status]!.toLowerCase()} tasks',
                  style: const TextStyle(color: AppColors.textSoft),
                ),
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border, indent: 56),
              itemBuilder: (context, i) => _TaskRow(
                task: items[i],
                onToggle: () => _toggle(items[i]),
                onEdit: () => _edit(items[i]),
              ),
            );
          },
        ),
      ),
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
                      Text(details, style: const TextStyle(fontSize: 13.5, color: AppColors.textSoft)),
                    ],
                  ],
                ),
              ),
              if (task.emailSent)
                const Padding(
                  padding: EdgeInsets.only(left: 4, top: 2),
                  child: Icon(Icons.mail_outline, size: 18, color: AppColors.textSoft),
                ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.textSoft),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              if (task.conversationId != null)
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, size: 20, color: AppColors.textSoft),
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
