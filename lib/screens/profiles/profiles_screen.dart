import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/profile.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import 'profile_detail_screen.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final _service = ProfileService();
  late Future<Map<String, Profile>> _future;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = _service.list();
  }

  void _reload() {
    final future = _service.list();
    setState(() {
      _future = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<Map<String, Profile>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Failed to load profiles: ${snap.error}'));
            }
            var profiles = (snap.data ?? {}).values.toList();
            if (_search.isNotEmpty) {
              profiles = profiles.where((p) => p.name.toLowerCase().contains(_search)).toList();
            }
            if (profiles.isEmpty) {
              return Center(
                child: Text(
                  _search.isNotEmpty ? 'No profiles match your search' : 'No profiles yet',
                  style: const TextStyle(color: AppColors.textSoft),
                ),
              );
            }
            return ListView.separated(
              itemCount: profiles.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border, indent: 78),
              itemBuilder: (context, i) {
                final p = profiles[i];
                return _ProfileRow(
                  profile: p,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: p)));
                    if (mounted) _reload();
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final Profile profile;
  final VoidCallback onTap;

  const _ProfileRow({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final categories = profile.categories.map((c) => c[0].toUpperCase() + c.substring(1)).join(', ');
    final subtitle = [
      if (categories.isNotEmpty) categories,
      DateFormat('MMM d, HH:mm').format(profile.lastSeen),
    ].join('  ·  ');

    return Material(
      color: AppColors.panel,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              InitialAvatar(name: profile.name),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13.5, color: AppColors.textSoft),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSoft),
            ],
          ),
        ),
      ),
    );
  }
}
