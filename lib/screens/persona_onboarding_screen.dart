import 'package:flutter/material.dart';

import '../services/persona_service.dart';
import '../theme.dart';

class PersonaOnboardingScreen extends StatefulWidget {
  final Map<String, dynamic> options;
  final VoidCallback onComplete;

  const PersonaOnboardingScreen({super.key, required this.options, required this.onComplete});

  @override
  State<PersonaOnboardingScreen> createState() => _PersonaOnboardingScreenState();
}

class _PersonaOnboardingScreenState extends State<PersonaOnboardingScreen> {
  final _service = PersonaService();
  final _age = TextEditingController();
  final _occupation = TextEditingController();
  final _primaryGoal = TextEditingController();

  String? _gender;
  String? _language;
  final Set<String> _hobbies = {};
  final Set<String> _interests = {};

  bool _submitting = false;
  String? _error;

  List<String> _opts(String key) => (widget.options[key] as List?)?.cast<String>() ?? const [];

  Future<void> _submit() async {
    final age = int.tryParse(_age.text.trim());
    if (age == null || age < 13 || age > 120) {
      setState(() => _error = 'Enter a valid age (13-120)');
      return;
    }
    if (_gender == null) {
      setState(() => _error = 'Select a gender');
      return;
    }
    if (_language == null) {
      setState(() => _error = 'Select a language preference');
      return;
    }
    if (_hobbies.isEmpty) {
      setState(() => _error = 'Pick at least one hobby');
      return;
    }
    if (_interests.isEmpty) {
      setState(() => _error = 'Pick at least one interest');
      return;
    }
    if (_occupation.text.trim().isEmpty) {
      setState(() => _error = 'Occupation is required');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _service.submit({
        'age': age,
        'gender': _gender,
        'language_preference': _language,
        'hobbies': _hobbies.toList(),
        'interests': _interests.toList(),
        'occupation': _occupation.text.trim(),
        'primary_goal': _primaryGoal.text.trim(),
      });
      widget.onComplete();
    } catch (e) {
      setState(() => _error = 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _chipGroup(String title, List<String> options, Set<String> selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 4),
        Text('Pick at least one', style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final isSelected = selected.contains(o);
            return FilterChip(
              label: Text(o),
              selected: isSelected,
              onSelected: (v) => setState(() => v ? selected.add(o) : selected.remove(o)),
              selectedColor: AppColors.bubbleOut,
              checkmarkColor: AppColors.accentDark,
              labelStyle: TextStyle(color: isSelected ? AppColors.accentDark : AppColors.text),
              side: BorderSide(color: isSelected ? AppColors.accent : AppColors.border),
              backgroundColor: AppColors.panel,
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tell us about you',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.text)),
                      const SizedBox(height: 4),
                      Text(
                        'We use this information to make your experience more personalized and better tailored to you.',
                        style: TextStyle(color: AppColors.textSoft),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _age,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _gender,
                        decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
                        items: _opts('gender').map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _language,
                        decoration:
                            const InputDecoration(labelText: 'Language preference', border: OutlineInputBorder()),
                        items: _opts('language_preference')
                            .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                            .toList(),
                        onChanged: (v) => setState(() => _language = v),
                      ),
                      const SizedBox(height: 16),
                      _chipGroup('Hobbies', _opts('hobbies'), _hobbies),
                      const SizedBox(height: 16),
                      _chipGroup('Interests', _opts('interests'), _interests),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _occupation,
                        decoration: const InputDecoration(
                          labelText: 'Occupation',
                          hintText: 'e.g. Software Engineer',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _primaryGoal,
                        decoration: const InputDecoration(
                          labelText: 'Primary goal (optional)',
                          hintText: 'e.g. stay organized, understand people better',
                          border: OutlineInputBorder(),
                        ),
                      ),
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
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Continue'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
