import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/empty_state.dart';
import 'meet_api.dart';
import 'meet_card_view.dart';
import 'meet_models.dart';

/// Everyone I've met with Meet -- also "who has my card", with a way to
/// stop sharing with any of them.
class MeetHistoryScreen extends StatefulWidget {
  const MeetHistoryScreen({super.key});

  @override
  State<MeetHistoryScreen> createState() => _MeetHistoryScreenState();
}

class _MeetHistoryScreenState extends State<MeetHistoryScreen> {
  final _api = MeetApi();
  List<MeetEncounter>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _api.history();
      if (mounted) setState(() => _items = items.where((e) => e.status != 'expired').toList());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _statusText(MeetEncounter e) => switch (e.status) {
        'shared' => e.cardHidden ? 'Stopped sharing their card' : 'Cards shared',
        'declined' => 'Not shared',
        'removed' => 'Sharing stopped',
        _ => 'Waiting',
      };

  Future<void> _stopSharing(MeetEncounter e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop sharing with ${e.other.name}?'),
        content: const Text("You'll both lose access to each other's cards."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop sharing')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.remove(e.id);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't stop sharing. Try again.")));
      }
    }
  }

  void _open(MeetEncounter e) {
    if (!e.isShared || e.card == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.bgApp,
        appBar: AppBar(backgroundColor: AppColors.bgApp, title: Text(e.other.name)),
        body: ListView(padding: const EdgeInsets.all(16), children: [MeetCardView(card: e.card!, person: e.other)]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(backgroundColor: AppColors.bgApp, title: const Text("People you've met")),
      body: _failed
          ? const EmptyState(icon: Icons.cloud_off_outlined, title: "Couldn't load your meetings", subtitle: 'Check your connection and try again.')
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? const EmptyState(
                      icon: Icons.contactless_outlined,
                      title: 'No one yet',
                      subtitle: 'People you swap cards with will show up here.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) {
                          final e = items[i];
                          final when = e.createdAt == null ? '' : DateFormat('d MMM, h:mm a').format(e.createdAt!.toLocal());
                          return ListTile(
                            leading: InitialAvatar(name: e.other.name, imageUrl: e.other.photo),
                            title: Text(e.other.name, style: TextStyle(color: AppColors.text)),
                            subtitle: Text('${_statusText(e)} · $when', style: TextStyle(color: AppColors.textSoft)),
                            onTap: () => _open(e),
                            trailing: e.isShared
                                ? IconButton(
                                    icon: const Icon(Icons.link_off),
                                    tooltip: 'Stop sharing',
                                    onPressed: () => _stopSharing(e),
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
    );
  }
}
