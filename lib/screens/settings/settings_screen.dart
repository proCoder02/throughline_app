import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../services/category_service.dart';
import '../../services/settings_service.dart';
import '../../state/auth_provider.dart';
import '../../theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final categoryNames = _categories?.all ?? kCategories;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(title: Text('Signed in as ${auth.username ?? ""}')),
                const Divider(color: AppColors.border),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Personalization mode', style: TextStyle(color: AppColors.textSoft)),
                ),
                ...categoryNames.map(
                  (c) => RadioListTile<String>(
                    value: c,
                    groupValue: _personalization,
                    title: Text(c[0].toUpperCase() + c.substring(1)),
                    onChanged: (v) {
                      if (v != null) _updatePersonalization(v);
                    },
                  ),
                ),
                const Divider(color: AppColors.border),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Your categories', style: TextStyle(color: AppColors.textSoft)),
                ),
                ...(_categories?.custom ?? const []).map(
                  (c) => ListTile(
                    title: Text(c),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () => _removeCategory(c),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newCategory,
                          decoration: const InputDecoration(hintText: 'New category', isDense: true),
                          onSubmitted: (_) => _addCategory(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(onPressed: _addCategory, child: const Text('Add')),
                    ],
                  ),
                ),
                if (_categoryError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(_categoryError!, style: const TextStyle(color: AppColors.danger)),
                  ),
                const Divider(color: AppColors.border),
                ListTile(
                  title: const Text('Friend code'),
                  subtitle: SelectableText(
                    _friendCode ?? '',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                  ),
                ),
                const Divider(color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                    onPressed: () => context.read<AuthProvider>().logout(),
                    child: const Text('Log out'),
                  ),
                ),
              ],
            ),
    );
  }
}
