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
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = _service.list()),
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
              return const Center(child: Text('No profiles yet', style: TextStyle(color: AppColors.textSoft)));
            }
            return ListView.separated(
              itemCount: profiles.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final p = profiles[i];
                final categories = p.categories.map((c) => c[0].toUpperCase() + c.substring(1)).join(', ');
                return ListTile(
                  tileColor: AppColors.panel,
                  leading: InitialAvatar(name: p.name),
                  title: Text(p.name),
                  subtitle: Text('$categories · ${DateFormat('MMM d, HH:mm').format(p.lastSeen)}'),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: p))),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
