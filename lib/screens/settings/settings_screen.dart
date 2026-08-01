import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  String? _personalization;
  String? _friendCode;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _updatePersonalization(String mode) async {
    setState(() => _personalization = mode);
    await _service.update(mode);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
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
                ...kCategories.map(
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
