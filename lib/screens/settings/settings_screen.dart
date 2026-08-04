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
  Categories? _categories;
  String? _categoryError;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCategories();
  }

  Future<void> _load() async {
    final settings = await _service.get();
    if (!mounted) return;
    setState(() {
      _personalization = settings['personalization'];
      _friendCode = settings['friend_code'];
      _loading = false;
    });
  }

  Future<void> _loadCategories() async {
    final categories = await _categoryService.list();
    if (!mounted) return;
    setState(() => _categories = categories);
  }

  Future<void> _updatePersonalization(String mode) async {
    setState(() => _personalization = mode);
    await _service.update(mode);
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
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
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
