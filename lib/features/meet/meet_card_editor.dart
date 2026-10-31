import 'package:flutter/material.dart';

import '../../theme.dart';
import 'meet_api.dart';
import 'meet_card_view.dart';
import 'meet_models.dart';

/// Create or edit my card. Opens pre-filled (a draft from my persona the
/// first time); nothing is shared until I tap Save.
class MeetCardEditorScreen extends StatefulWidget {
  final MyMeetCard initial;

  const MeetCardEditorScreen({super.key, required this.initial});

  @override
  State<MeetCardEditorScreen> createState() => _MeetCardEditorScreenState();
}

class _MeetCardEditorScreenState extends State<MeetCardEditorScreen> {
  final _api = MeetApi();
  late final _headline = TextEditingController(text: widget.initial.card.headline);
  late final _about = TextEditingController(text: widget.initial.card.about);
  late final _interests = TextEditingController(text: widget.initial.card.interests.join(', '));
  late final _likes = TextEditingController(text: widget.initial.card.likes.join(', '));
  late bool _sharing = widget.initial.card.sharing;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_headline, _about, _interests, _likes]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_headline, _about, _interests, _likes]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _split(String text) =>
      text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  MeetCard get _card => MeetCard(
        headline: _headline.text.trim(),
        about: _about.text.trim(),
        interests: _split(_interests.text),
        likes: _split(_likes.text),
        sharing: _sharing,
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await _api.saveCard(_card);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save your card. Check your connection and try again.")));
    }
  }

  InputDecoration _field(String label, {String? hint, String? helper}) => InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        filled: true,
        fillColor: AppColors.panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        backgroundColor: AppColors.bgApp,
        title: Text(widget.initial.saved ? 'Edit your card' : 'Your Meet card'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            widget.initial.saved
                ? 'This is what people see when you share your card.'
                : "We've started your card from your profile. Change anything you like -- people only see it after you both tap Share.",
            style: TextStyle(color: AppColors.textSoft, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(controller: _headline, maxLength: 80, decoration: _field('Headline', hint: 'e.g. Product designer, trekker')),
          const SizedBox(height: 8),
          TextField(
            controller: _about,
            maxLength: 280,
            minLines: 2,
            maxLines: 5,
            decoration: _field('About you', hint: 'A line or two about how you think, work or spend your time'),
          ),
          const SizedBox(height: 8),
          TextField(controller: _interests, decoration: _field('Interests', helper: 'Separate with commas, up to 8')),
          const SizedBox(height: 16),
          TextField(controller: _likes, decoration: _field('Things you like', helper: 'Separate with commas, up to 8')),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sharing,
            onChanged: (v) => setState(() => _sharing = v),
            title: const Text('Share my card with people I meet'),
            subtitle: Text(
              _sharing ? 'On' : 'Off -- nobody can see your card, including people you already met',
              style: TextStyle(color: AppColors.textSoft),
            ),
          ),
          const SizedBox(height: 16),
          Text('PREVIEW', style: TextStyle(color: AppColors.textSoft, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          MeetCardView(card: _card, person: widget.initial.me),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size.fromHeight(48)),
            child: Text(_saving ? 'Saving…' : 'Save card'),
          ),
        ],
      ),
    );
  }
}
