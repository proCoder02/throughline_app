import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_provider.dart';
import '../state/theme_provider.dart';
import '../services/consent_service.dart';
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
  bool _agreed = false;

  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  Future<void> _submit() async {
    if (_isRegister && !_agreed) {
      setState(() => _error = 'Please agree to the Terms of Service and Privacy Policy.');
      return;
    }
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
            acceptedTerms: _agreed,
          )
        : await auth.login(_username.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  /// Matches the frosted-pill field treatment used by every composer bar
  /// elsewhere in the app -- see this session's own audit (Auth/Onboarding
  /// were the only screens still on the old flat AppColors.* palette while
  /// every other screen uses the warm-gradient dm* system).
  InputDecoration _fieldDecoration(String label) {
    final radius = BorderRadius.circular(14);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppColors.dmTextSoft),
      filled: true,
      fillColor: AppColors.dmPillFill,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.dmBubbleBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.dmAccent, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.dmGradient),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.dmBubbleIn,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.dmBubbleBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Throughline',
                        textAlign: TextAlign.center, style: appHeadlineFont(color: AppColors.dmText, fontSize: 24)),
                    const SizedBox(height: 4),
                    Text('Listens once. Remembers everything.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.dmTextSoft)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _username,
                      style: TextStyle(color: AppColors.dmText),
                      cursorColor: AppColors.dmAccent,
                      decoration: _fieldDecoration('Username'),
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(color: AppColors.dmText),
                        cursorColor: AppColors.dmAccent,
                        decoration: _fieldDecoration('Email'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      style: TextStyle(color: AppColors.dmText),
                      cursorColor: AppColors.dmAccent,
                      decoration: _fieldDecoration('Password'),
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _personalization,
                        style: TextStyle(color: AppColors.dmText),
                        dropdownColor: AppColors.dmBubbleIn,
                        decoration: _fieldDecoration('Mode'),
                        items: kCategories
                            .map((c) => DropdownMenuItem(
                                value: c, child: Text(c[0].toUpperCase() + c.substring(1))))
                            .toList(),
                        onChanged: (v) => setState(() => _personalization = v ?? 'personal'),
                      ),
                    ],
                    if (_isRegister) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _agreed,
                            activeColor: AppColors.dmAccent,
                            onChanged: _submitting ? null : (v) => setState(() => _agreed = v ?? false),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text('I agree to the ', style: TextStyle(color: AppColors.dmTextSoft)),
                                  _LegalLink(label: 'Terms', path: '/terms'),
                                  Text(' and ', style: TextStyle(color: AppColors.dmTextSoft)),
                                  _LegalLink(label: 'Privacy Policy', path: '/privacy'),
                                  Text(", and I'll tell people before I record them.",
                                      style: TextStyle(color: AppColors.dmTextSoft)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.dmAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_isRegister ? 'Register' : 'Log in'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _submitting ? null : () => setState(() => _isRegister = !_isRegister),
                      style: TextButton.styleFrom(foregroundColor: AppColors.dmAccent),
                      child: Text(_isRegister ? 'Already have an account? Log in' : "Don't have an account? Register"),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        _LegalLink(label: 'Privacy', path: '/privacy'),
                        SizedBox(width: 16),
                        _LegalLink(label: 'Terms', path: '/terms'),
                      ],
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

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.path});
  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openLegalPage(path),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(label,
            style: TextStyle(color: AppColors.dmAccent, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
      ),
    );
  }
}
