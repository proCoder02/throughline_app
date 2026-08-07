import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/profile.dart';
import '../../services/profile_service.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/offline_banner.dart';
import 'profile_detail_screen.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final _service = ProfileService();
  Map<String, Profile>? _profiles;
  bool _loading = true;
  Object? _error;
  bool _offline = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    // Show the on-device copy instantly if there is one, then always refresh
    // from the network in the background -- same cache-first pattern as
    // ChatsScreen, so this tab still shows its last-known data offline.
    final cached = _service.listCached();
    if (cached != null) {
      _profiles = cached;
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.list();
      if (!mounted) return;
      setState(() {
        _profiles = items;
        _loading = false;
        _error = null;
        _offline = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
        if (_profiles == null) _error = e;
      });
    }
  }

  Future<void> _reload() => _load();

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
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
    if (_profiles == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(child: Text('Failed to load profiles: $_error'));
    }
    var profiles = _profiles!.values.toList();
    if (_search.isNotEmpty) {
      profiles = profiles.where((p) => p.name.toLowerCase().contains(_search)).toList();
    }
    if (profiles.isEmpty) {
      return Center(
        child: Text(
          _search.isNotEmpty ? 'No profiles match your search' : 'No profiles yet',
          style: TextStyle(color: AppColors.textSoft),
        ),
      );
    }
    return ListView.separated(
      itemCount: profiles.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border, indent: 78),
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13.5, color: AppColors.textSoft),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSoft),
            ],
          ),
        ),
      ),
    );
  }
}
