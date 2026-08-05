import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_provider.dart';
import '../state/theme_provider.dart';
import '../theme.dart';
import '../widgets/category_menu.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isRegister = false;
  bool _submitting = false;
  String? _error;
  String _personalization = 'personal';

  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final error = _isRegister
        ? await auth.register(
            user: _username.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            personalization: _personalization,
          )
        : await auth.login(_username.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Throughline',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.accent)),
                    const SizedBox(height: 4),
                    Text('Listens once. Remembers everything.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSoft)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _username,
                      decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _personalization,
                        decoration: const InputDecoration(labelText: 'Mode', border: OutlineInputBorder()),
                        items: kCategories
                            .map((c) => DropdownMenuItem(
                                value: c, child: Text(c[0].toUpperCase() + c.substring(1))))
                            .toList(),
                        onChanged: (v) => setState(() => _personalization = v ?? 'personal'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _submitting
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_isRegister ? 'Register' : 'Log in'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _submitting ? null : () => setState(() => _isRegister = !_isRegister),
                      child: Text(_isRegister ? 'Already have an account? Log in' : "Don't have an account? Register"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
