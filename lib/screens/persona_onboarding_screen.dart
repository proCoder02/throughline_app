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
    // Collects every problem at once instead of the old early-return chain,
    // which only ever showed the first failing field -- fixing it, hitting
    // submit again, and finding the *next* one (see this session's UX
    // audit; violates "help users recognize, diagnose, and recover from
    // errors" more with every extra required field).
    final age = int.tryParse(_age.text.trim());
    final problems = [
      if (age == null || age < 13 || age > 120) 'Enter a valid age (13-120)',
      if (_gender == null) 'Select a gender',
      if (_language == null) 'Select a language preference',
      if (_hobbies.isEmpty) 'Pick at least one hobby',
      if (_interests.isEmpty) 'Pick at least one interest',
      if (_occupation.text.trim().isEmpty) 'Occupation is required',
    ];
    if (problems.isNotEmpty) {
      setState(() => _error = problems.join('\n'));
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
        Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dmText)),
        const SizedBox(height: 4),
        Text('Pick at least one', style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final isSelected = selected.contains(o);
            return FilterChip(
              // Capped -- these option strings are server-driven
              // (widget.options), so nothing previously stopped an
              // unexpectedly long one from stretching the chip full-width
              // (see this session's UX audit).
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(o, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              selected: isSelected,
              onSelected: (v) => setState(() => v ? selected.add(o) : selected.remove(o)),
              selectedColor: AppColors.dmAccent.withValues(alpha: 0.18),
              checkmarkColor: AppColors.dmAccentDark,
              labelStyle: TextStyle(color: isSelected ? AppColors.dmAccentDark : AppColors.dmText),
              side: BorderSide(color: isSelected ? AppColors.dmAccent : AppColors.dmBubbleBorder),
              backgroundColor: AppColors.dmPillFill,
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Same frosted-pill field treatment as auth_screen.dart -- see this
  /// session's audit (Auth/Onboarding were the only screens still on the
  /// old flat AppColors.* palette while every other screen uses the
  /// warm-gradient dm* system).
  InputDecoration _fieldDecoration(String label, {String? hint}) {
    final radius = BorderRadius.circular(14);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: AppColors.dmTextSoft),
      hintStyle: TextStyle(color: AppColors.dmTextSoft.withValues(alpha: 0.7)),
      filled: true,
      fillColor: AppColors.dmPillFill,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.dmBubbleBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.dmAccent, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.dmGradient),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.dmBubbleIn,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.dmBubbleBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tell us about you', style: appHeadlineFont(color: AppColors.dmText, fontSize: 21)),
                      const SizedBox(height: 4),
                      Text(
                        'We use this information to make your experience more personalized and better tailored to you.',
                        style: TextStyle(color: AppColors.dmTextSoft),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _age,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppColors.dmText),
                        cursorColor: AppColors.dmAccent,
                        decoration: _fieldDecoration('Age'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _gender,
                        // isExpanded + ellipsis -- these option strings are
                        // server-driven, so nothing previously stopped an
                        // unexpectedly long one from overflowing (see this
                        // session's UX audit).
                        isExpanded: true,
                        style: TextStyle(color: AppColors.dmText),
                        dropdownColor: AppColors.dmBubbleIn,
                        decoration: _fieldDecoration('Gender'),
                        items: _opts('gender')
                            .map((g) => DropdownMenuItem(
                                value: g, child: Text(g, maxLines: 1, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _language,
                        isExpanded: true,
                        style: TextStyle(color: AppColors.dmText),
                        dropdownColor: AppColors.dmBubbleIn,
                        decoration: _fieldDecoration('Language preference'),
                        items: _opts('language_preference')
                            .map((l) =>
                                DropdownMenuItem(value: l, child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis)))
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
                        style: TextStyle(color: AppColors.dmText),
                        cursorColor: AppColors.dmAccent,
                        decoration: _fieldDecoration('Occupation', hint: 'e.g. Software Engineer'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _primaryGoal,
                        style: TextStyle(color: AppColors.dmText),
                        cursorColor: AppColors.dmAccent,
                        decoration: _fieldDecoration('Primary goal (optional)',
                            hint: 'e.g. stay organized, understand people better'),
                      ),
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
