import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/profile.dart';
import '../../services/profile_service.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/category_chip_bar.dart';
import '../../widgets/chat_list_skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/offline_banner.dart';
import 'profile_detail_screen.dart';

class ProfilesScreen extends StatefulWidget {
  /// Opens HomeShell's side drawer (the retired bottom nav's replacement).
  final VoidCallback? onOpenDrawer;

  const ProfilesScreen({super.key, this.onOpenDrawer});

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
  String? _category;

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
        title: const Text('Profiles'),
        // Category filter added -- this screen has the same Profile.categories
        // data Chats/Tasks filter by, but previously offered no filtering UI
        // at all for it (see this session's UX audit). Same persistent chip
        // bar as those two screens, not a third different pattern.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: TextField(
                      style: TextStyle(color: AppColors.dmText),
                      decoration: InputDecoration(
                        hintText: 'Search by name',
                        hintStyle: TextStyle(color: AppColors.dmTextSoft),
                        prefixIcon: Icon(Icons.search, color: AppColors.dmTextSoft),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.dmPillFill,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: AppColors.dmBubbleBorder)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: AppColors.dmBubbleBorder)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(color: AppColors.dmAccent, width: 2)),
                      ),
                      onChanged: (v) => setState(() => _search = v.toLowerCase()),
                    ),
                  ),
                ),
              ),
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
    if (_profiles == null) {
      // Same shimmer skeleton as Chats/Tasks' cold-start load (see this
      // session's UX audit) instead of a bare spinner.
      if (_loading) return const ChatListSkeleton();
      return Center(child: Text('Failed to load profiles: $_error'));
    }
    var profiles = _profiles!.values.toList();
    if (_search.isNotEmpty) {
      profiles = profiles.where((p) => p.name.toLowerCase().contains(_search)).toList();
    }
    // A profile can carry several categories (unlike Task's single one), so
    // this filters on "has this category" rather than an exact match.
    final category = _category;
    if (category != null) {
      profiles = profiles.where((p) => p.categories.contains(category)).toList();
    }
    if (profiles.isEmpty) {
      final filtered = _search.isNotEmpty || category != null;
      // Shared EmptyState component (icon + title) instead of a bare gray
      // sentence -- Chats/Tasks already use it for the same job.
      return EmptyState(
        icon: filtered ? Icons.search_off : Icons.people_outline,
        title: filtered ? 'No profiles match this filter' : 'No profiles yet',
        subtitle: filtered ? null : 'People you mention in a Listen conversation show up here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: profiles.length,
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.dmText),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.dmTextSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
