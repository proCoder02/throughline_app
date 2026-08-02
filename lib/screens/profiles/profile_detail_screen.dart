import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/profile.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';
import '../chats/chat_thread_screen.dart';

class ProfileDetailScreen extends StatefulWidget {
  final Profile profile;

  const ProfileDetailScreen({super.key, required this.profile});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  final _service = ProfileService();
  late Profile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _profile.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename profile'),
        content: TextField(controller: controller, autofocus: true, onSubmitted: (v) => Navigator.of(context).pop(v)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty || newName.trim() == _profile.name) return;
    try {
      await _service.rename(_profile.profileId, newName.trim());
      if (!mounted) return;
      setState(() {
        _profile = Profile(
          profileId: _profile.profileId,
          name: newName.trim(),
          categories: _profile.categories,
          lastSeen: _profile.lastSeen,
          notes: _profile.notes,
        );
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not rename -- that name may already be taken')));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete profile'),
        content: Text(
          "Delete ${_profile.name}'s profile permanently? This removes every observation about them. "
          "This cannot be undone.",
        ),
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
    await _service.delete(_profile.profileId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_profile.name),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Rename', onPressed: _rename),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _delete),
        ],
      ),
      body: _profile.notes.isEmpty
          ? const Center(child: Text('No observations yet', style: TextStyle(color: AppColors.textSoft)))
          : ListView.separated(
              itemCount: _profile.notes.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final n = _profile.notes[i];
                final category = n.category.isEmpty ? '' : n.category[0].toUpperCase() + n.category.substring(1);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 14.5, color: AppColors.text, height: 1.4),
                            children: [
                              TextSpan(
                                text: '$category  ·  ${DateFormat('MMM d, HH:mm').format(n.createdAt)}\n',
                                style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5),
                              ),
                              TextSpan(text: n.observation),
                            ],
                          ),
                        ),
                      ),
                      if (n.conversationId != null)
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.textSoft),
                          tooltip: 'View source conversation',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: n.conversationId!)),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
