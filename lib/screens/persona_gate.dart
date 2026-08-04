import 'package:flutter/material.dart';

import '../services/local_cache.dart';
import '../services/persona_service.dart';
import '../theme.dart';
import 'home_shell.dart';
import 'persona_onboarding_screen.dart';

/// Blocks the main app shell behind a one-time persona form. Fails open on
/// network error (matches the web client) so a transient hiccup never
/// permanently locks a user out of the app.
///
/// Whether onboarding is done rarely changes once true, so it's cached
/// on-device (LocalCache.instance) -- a returning user renders HomeShell
/// immediately instead of waiting on this screen's own network round-trip
/// on every single app open. The network check still always runs in the
/// background to catch the rare cases (server-side reset, new account) the
/// cache wouldn't reflect.
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
    _completed = LocalCache.instance.getPersonaCompleted();
    _check();
  }

  Future<void> _check() async {
    try {
      final data = await _service.get();
      if (!mounted) return;
      final completed = data['completed'] == true;
      await LocalCache.instance.setPersonaCompleted(completed);
      setState(() {
        _completed = completed;
        _options = (data['options'] as Map?)?.cast<String, dynamic>() ?? const {};
      });
    } catch (_) {
      // Offline/unreachable -- keep showing whatever the cache already said
      // (or fail open if there was nothing cached yet, same as before).
      if (mounted && _completed == null) setState(() => _completed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_completed == null) {
      // Same reasoning as main.dart's auth gate -- a blank splash-colored
      // screen instead of a spinner, since this only shows for a genuinely
      // first-ever login where nothing is cached yet.
      return Scaffold(backgroundColor: AppColors.bgApp, body: const SizedBox.shrink());
    }
    if (!_completed!) {
      return PersonaOnboardingScreen(
        options: _options,
        onComplete: () {
          LocalCache.instance.setPersonaCompleted(true);
          setState(() => _completed = true);
        },
      );
    }
    return const HomeShell();
  }
}
