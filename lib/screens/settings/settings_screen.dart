import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show themeProvider;
import '../../models/category.dart';
import '../../services/category_service.dart';
import '../../services/settings_service.dart';
import '../../state/auth_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/category_menu.dart';
import '../../widgets/island_nav_bar.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/toggle_group.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SettingsService();
  final _categoryService = CategoryService();
  final _newCategory = TextEditingController();

  String? _personalization;
  String? _friendCode;
  bool _loading = true;
  Object? _loadError;
  bool _offline = false;
  Categories? _categories;
  String? _categoryError;

  // Default to true (matches the backend's own default-on behavior for a
  // user who has never touched nudges.user_settings -- see
  // nudge_engine.get_user_settings) so this card doesn't need its own
  // separate loading spinner; cache/network just override these once they
  // resolve.
  bool _nudgesEnabled = true;
  bool _cognitiveIntelligenceEnabled = true;
  bool _taskReminderNotificationsEnabled = true;
  bool _tagsQuestionsEnabled = true;

  /// Its own independently stored value (nudges.user_settings.smart_features_enabled),
  /// NOT derived from the four fields above. Toggling this master switch
  /// cascades DOWN and sets all four together -- but turning an individual
  /// feature off afterward does NOT cascade back up and flip this one off;
  /// it keeps reading as on until explicitly toggled again. See app.py's
  /// update_nudge_settings for the matching server-side logic.
  bool _smartFeaturesEnabled = true;

  @override
  void initState() {
    super.initState();
    // Show the on-device copy instantly if there is one, then always refresh
    // from the network in the background -- same cache-first pattern as
    // ChatsScreen, so this tab still shows last-known settings offline
    // instead of spinning forever if the request fails (the previous bug).
    final cachedSettings = _service.getCached();
    if (cachedSettings != null) {
      _personalization = cachedSettings['personalization'];
      _friendCode = cachedSettings['friend_code'];
      _loading = false;
    }
    final cachedCategories = _categoryService.listCached();
    if (cachedCategories != null) _categories = cachedCategories;
    final cachedNudgeSettings = _service.getCachedNudgeSettings();
    if (cachedNudgeSettings != null) {
      _nudgesEnabled = cachedNudgeSettings['nudges_enabled'] ?? true;
      _cognitiveIntelligenceEnabled = cachedNudgeSettings['cognitive_intelligence_enabled'] ?? true;
      _taskReminderNotificationsEnabled = cachedNudgeSettings['task_reminder_notifications_enabled'] ?? true;
      _tagsQuestionsEnabled = cachedNudgeSettings['tags_questions_enabled'] ?? true;
      _smartFeaturesEnabled = cachedNudgeSettings['smart_features_enabled'] ?? true;
    }
    _load();
    _loadCategories();
    _loadNudgeSettings();
  }

  Future<void> _load() async {
    try {
      final settings = await _service.get();
      if (!mounted) return;
      setState(() {
        _personalization = settings['personalization'];
        _friendCode = settings['friend_code'];
        _loading = false;
        _loadError = null;
        _offline = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
        if (_friendCode == null) _loadError = e;
      });
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryService.list();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // Offline/unreachable -- keep showing whatever was cached above (or
      // the kCategories fallback used in build() if there was none).
    }
  }

  Future<void> _updatePersonalization(String mode) async {
    setState(() => _personalization = mode);
    await _service.update(mode);
  }

  Future<void> _loadNudgeSettings() async {
    try {
      final settings = await _service.getNudgeSettings();
      if (!mounted) return;
      setState(() {
        _nudgesEnabled = settings['nudges_enabled'] ?? true;
        _cognitiveIntelligenceEnabled = settings['cognitive_intelligence_enabled'] ?? true;
        _taskReminderNotificationsEnabled = settings['task_reminder_notifications_enabled'] ?? true;
        _tagsQuestionsEnabled = settings['tags_questions_enabled'] ?? true;
        _smartFeaturesEnabled = settings['smart_features_enabled'] ?? true;
      });
    } catch (_) {
      // Offline/unreachable -- keep showing the cached or default value above.
    }
  }

  Future<void> _updateSmartFeatures(bool value) async {
    setState(() {
      _smartFeaturesEnabled = value;
      _nudgesEnabled = value;
      _cognitiveIntelligenceEnabled = value;
      _taskReminderNotificationsEnabled = value;
      _tagsQuestionsEnabled = value;
    });
    await _service.updateSmartFeatures(value);
  }

  Future<void> _updateNudgesEnabled(bool value) async {
    setState(() => _nudgesEnabled = value);
    await _service.updateNudgeSettings(nudgesEnabled: value);
  }

  Future<void> _updateCognitiveIntelligenceEnabled(bool value) async {
    setState(() => _cognitiveIntelligenceEnabled = value);
    await _service.updateNudgeSettings(cognitiveIntelligenceEnabled: value);
  }

  Future<void> _updateTaskReminderNotificationsEnabled(bool value) async {
    setState(() => _taskReminderNotificationsEnabled = value);
    await _service.updateNudgeSettings(taskReminderNotificationsEnabled: value);
  }

  Future<void> _updateTagsQuestionsEnabled(bool value) async {
    setState(() => _tagsQuestionsEnabled = value);
    await _service.updateNudgeSettings(tagsQuestionsEnabled: value);
  }

  Future<void> _addCategory() async {
    final name = _newCategory.text.trim();
    if (name.isEmpty) return;
    setState(() => _categoryError = null);
    try {
      await _categoryService.add(name);
      _newCategory.clear();
      await _loadCategories();
    } catch (e) {
      setState(() => _categoryError = CategoryService.errorMessage(e));
    }
  }

  Future<void> _removeCategory(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category'),
        content: Text('Delete your "$name" category? Conversations already tagged with it keep the label.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _categoryService.remove(name);
    await _loadCategories();
  }

  void _copyFriendCode() {
    if (_friendCode == null) return;
    Clipboard.setData(ClipboardData(text: _friendCode!));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend code copied')));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    context.watch<ThemeProvider>();
    final categoryNames = _categories?.all ?? kCategories;
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Text('Failed to load settings: $_loadError'))
              : ListView(
              // HomeShell's Scaffold extends its body under the translucent
              // IslandNavBar (needed for the bar's blur to have real content
              // behind it) -- without accounting for that here, the last
              // item (Log out) ends up hidden behind the floating nav bar,
              // same class of bug already fixed for ChatsScreen's FAB.
              padding: const EdgeInsets.fromLTRB(
                  12, 12, 12, 12 + IslandNavBar.barHeight + IslandNavBar.bottomMargin),
              children: [
                if (_offline) const Padding(padding: EdgeInsets.only(bottom: 12), child: OfflineBanner()),
                _SettingsCard(
                  children: [
                    Row(
                      children: [
                        InitialAvatar(name: auth.username ?? '?', size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(auth.username ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              Text('Signed in', style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                _SettingsCard(
                  title: 'Appearance',
                  children: [
                    Consumer<ThemeProvider>(
                      builder: (context, themeState, __) => SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                          ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                        ],
                        selected: {themeProvider.mode},
                        onSelectionChanged: (selection) => themeProvider.setMode(selection.first),
                      ),
                    ),
                  ],
                ),
                _SettingsCard(
                  title: 'Personalization mode',
                  children: categoryNames
                      .map(
                        (c) => RadioListTile<String>(
                          value: c,
                          groupValue: _personalization,
                          contentPadding: EdgeInsets.zero,
                          title: Text(c[0].toUpperCase() + c.substring(1)),
                          onChanged: (v) {
                            if (v != null) _updatePersonalization(v);
                          },
                        ),
                      )
                      .toList(),
                ),
                _SettingsCard(
                  // No title/subtitle here -- the parent switch below IS the
                  // header. Giving the card its own "Smart features" text on
                  // top of the switch's own title was the duplicate.
                  children: [
                    ToggleParentTile(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Smart features',
                      subtitle: _smartFeaturesEnabled
                          ? 'Turns everything below on or off together.'
                          : 'Turn on to customize the individual features below.',
                      value: _smartFeaturesEnabled,
                      onChanged: _updateSmartFeatures,
                    ),
                    ToggleGroup(
                      children: [
                        ToggleChildTile(
                          title: 'Nudges',
                          subtitle: 'Overdue tasks, mood shifts, and friends you haven\'t talked to in a while.',
                          value: _nudgesEnabled,
                          enabled: _smartFeaturesEnabled,
                          onChanged: _updateNudgesEnabled,
                        ),
                        ToggleChildTile(
                          title: 'Cognitive intelligence',
                          subtitle: 'Learns from your conversations to give more personalized replies.',
                          value: _cognitiveIntelligenceEnabled,
                          enabled: _smartFeaturesEnabled,
                          onChanged: _updateCognitiveIntelligenceEnabled,
                        ),
                        ToggleChildTile(
                          title: 'Task reminder notifications',
                          subtitle: 'Email and push reminders when a task\'s reminder time arrives.',
                          value: _taskReminderNotificationsEnabled,
                          enabled: _smartFeaturesEnabled,
                          onChanged: _updateTaskReminderNotificationsEnabled,
                        ),
                        ToggleChildTile(
                          title: 'Tags & questions',
                          subtitle: 'Suggested topic tags and follow-up questions during live conversations.',
                          value: _tagsQuestionsEnabled,
                          enabled: _smartFeaturesEnabled,
                          onChanged: _updateTagsQuestionsEnabled,
                          isLast: true,
                        ),
                      ],
                    ),
                  ],
                ),
                _SettingsCard(
                  title: 'Your categories',
                  subtitle: 'personal/office/study always exist -- add your own on top.',
                  children: [
                    ...(_categories?.custom ?? const []).map(
                      (c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(c, style: const TextStyle(fontSize: 15))),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                              onPressed: () => _removeCategory(c),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newCategory,
                            decoration: const InputDecoration(hintText: 'New category name', isDense: true),
                            onSubmitted: (_) => _addCategory(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(onPressed: _addCategory, child: const Text('Add')),
                      ],
                    ),
                    if (_categoryError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_categoryError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                      ),
                  ],
                ),
                _SettingsCard(
                  title: 'Your friend code',
                  subtitle: 'Share this so a friend can add you from the Friends tab.',
                  children: [
                    InkWell(
                      onTap: _copyFriendCode,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _friendCode ?? '',
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Icon(Icons.copy_outlined, size: 20, color: AppColors.textSoft),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => context.read<AuthProvider>().logout(),
                    child: const Text('Log out'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final List<Widget> children;

  const _SettingsCard({this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(title!, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
                ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(subtitle!, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

