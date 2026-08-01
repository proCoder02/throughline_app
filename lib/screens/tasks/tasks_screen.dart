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
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'open', child: Text('Open')),
              PopupMenuItem(value: 'done', child: Text('Done')),
              PopupMenuItem(value: 'all', child: Text('All')),
            ],
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
              return const Center(child: Text('No tasks', style: TextStyle(color: AppColors.textSoft)));
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final t = items[i];
                final subtitle = (t.owner != null || t.dueDate != null)
                    ? 'Owner: ${t.owner ?? "?"} · Due: ${t.dueDate ?? "?"}'
                    : 'No details';
                return ListTile(
                  tileColor: AppColors.panel,
                  leading: Icon(
                    t.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: t.isDone ? AppColors.accent : AppColors.textSoft,
                  ),
                  title: Text(
                    t.description,
                    style: t.isDone ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                  ),
                  subtitle: Text(subtitle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (t.emailSent) const Icon(Icons.mail_outline, size: 18, color: AppColors.textSoft),
                      if (t.conversationId != null)
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline, size: 18),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatThreadScreen(conversationId: t.conversationId!),
                            ),
                          ),
                        ),
                    ],
                  ),
                  onTap: () => _toggle(t),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
