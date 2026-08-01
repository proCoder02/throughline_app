import 'package:flutter/material.dart';

import '../services/persona_service.dart';
import 'home_shell.dart';
import 'persona_onboarding_screen.dart';

/// Blocks the main app shell behind a one-time persona form. Fails open on
/// network error (matches the web client) so a transient hiccup never
/// permanently locks a user out of the app.
class PersonaGate extends StatefulWidget {
  const PersonaGate({super.key});

  @override
  State<PersonaGate> createState() => _PersonaGateState();
}

class _PersonaGateState extends State<PersonaGate> {
  final _service = PersonaService();
  bool? _completed;
  Map<String, dynamic> _options = const {};

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final data = await _service.get();
      if (!mounted) return;
      setState(() {
        _completed = data['completed'] == true;
        _options = (data['options'] as Map?)?.cast<String, dynamic>() ?? const {};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _completed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_completed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_completed!) {
      return PersonaOnboardingScreen(
        options: _options,
        onComplete: () => setState(() => _completed = true),
      );
    }
    return const HomeShell();
  }
}
