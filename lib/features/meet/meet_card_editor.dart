import 'package:flutter/material.dart';

import '../../theme.dart';
import 'meet_api.dart';
import 'meet_card_view.dart';
import 'meet_models.dart';

/// Create or edit my card. Opens pre-filled (a draft from my profile the
/// first time); nothing is shared until I tap Save. Laid out in the same
/// three parts as the card itself: who you are, personality, stay in touch.
class MeetCardEditorScreen extends StatefulWidget {
  final MyMeetCard initial;

  const MeetCardEditorScreen({super.key, required this.initial});

  @override
  State<MeetCardEditorScreen> createState() => _MeetCardEditorScreenState();
}

class _MeetCardEditorScreenState extends State<MeetCardEditorScreen> {
  static const _maxTraits = 4;
  static const _linkHints = ['linkedin.com/in/…', 'instagram.com/…', 'Your website'];
  final _api = MeetApi();
  late final MeetCard _c = widget.initial.card;
  late final _headline = TextEditingController(text: _c.headline);
  late final _organization = TextEditingController(text: _c.organization);
  late final _city = TextEditingController(text: _c.city);
  late final _education = TextEditingController(text: _c.education);
  late final _style = TextEditingController(text: _c.style);
  late final _about = TextEditingController(text: _c.about);
  late final _interests = TextEditingController(text: _c.interests.join(', '));
  late final _likes = TextEditingController(text: _c.likes.join(', '));
  late final _links = List.generate(3, (i) => TextEditingController(text: i < _c.links.length ? _c.links[i] : ''));
  late final _customTrait = TextEditingController();
  late List<String> _traits = [..._c.traits];
  late bool _sharing = _c.sharing;
  bool _saving = false;
  bool _suggesting = false;

  List<TextEditingController> get _all =>
      [_headline, _organization, _city, _education, _style, _about, _interests, _likes, ..._links, _customTrait];

  @override
  void initState() {
    super.initState();
    for (final c in _all) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _split(String text) => text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  MeetCard get _card => MeetCard(
        headline: _headline.text.trim(),
        organization: _organization.text.trim(),
        city: _city.text.trim(),
        education: _education.text.trim(),
        style: _style.text.trim(),
        about: _about.text.trim(),
        traits: _traits,
        interests: _split(_interests.text),
        likes: _split(_likes.text),
        links: _links.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(),
        sharing: _sharing,
      );

  void _toggleTrait(String t) {
    setState(() {
      if (_traits.contains(t)) {
        _traits = [..._traits]..remove(t);
      } else if (_traits.length < _maxTraits) {
        _traits = [..._traits, t];
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick up to 4 -- remove one first.')));
      }
    });
  }

  void _addCustomTrait() {
    final t = _customTrait.text.trim();
    if (t.isEmpty) return;
    if (!_traits.any((x) => x.toLowerCase() == t.toLowerCase())) _toggleTrait(t);
    _customTrait.clear();
  }

  Future<void> _suggest() async {
    setState(() => _suggesting = true);
    try {
      final s = await _api.suggest();
      if (!mounted) return;
      setState(() {
        if (s.traits.isNotEmpty) _traits = s.traits.take(_maxTraits).toList();
        if (s.style.isNotEmpty) _style.text = s.style;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suggested from what Throughline knows about you. Change anything before saving.')),
      );
    } on MeetSuggestionError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't make a suggestion. Check your connection.")));
      }
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

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

  InputDecoration _field(String label, {String? hint, String? helper, IconData? icon}) => InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        filled: true,
        fillColor: AppColors.panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
      );

  Widget _section(String title, {String? subtitle}) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: appHeadlineFont(color: AppColors.text, fontSize: 17)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: AppColors.textSoft, fontSize: 13, height: 1.35)),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final options = {...widget.initial.traitOptions, ..._traits}.toList();
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        backgroundColor: AppColors.bgApp,
        title: Text(widget.initial.saved ? 'Edit your card' : 'Your Meet card'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            widget.initial.saved
                ? 'This is what people see when you both share. Everything is optional.'
                : "We've started your card from your profile. Change anything -- people only see it after you both tap Share.",
            style: TextStyle(color: AppColors.textSoft, height: 1.4),
          ),

          _section('Who you are'),
          TextField(controller: _headline, maxLength: 80, decoration: _field('Role or headline', hint: 'e.g. Product designer', icon: Icons.badge_outlined)),
          TextField(controller: _organization, maxLength: 80, decoration: _field('Company or organisation', icon: Icons.business_outlined)),
          TextField(controller: _city, maxLength: 80, decoration: _field('City', icon: Icons.place_outlined)),
          TextField(controller: _education, maxLength: 80, decoration: _field('Education', hint: 'e.g. MBA, IIM Indore', icon: Icons.school_outlined)),

          _section('Personality', subtitle: 'Pick up to 4 traits that sound like you.'),
          if (widget.initial.canSuggest)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _suggesting ? null : _suggest,
                icon: _suggesting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(_suggesting ? 'Thinking…' : 'Suggest from Throughline'),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in options)
                FilterChip(
                  label: Text(t),
                  selected: _traits.contains(t),
                  onSelected: (_) => _toggleTrait(t),
                  selectedColor: AppColors.accent.withValues(alpha: 0.25),
                  checkmarkColor: AppColors.text,
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _customTrait,
            maxLength: 24,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addCustomTrait(),
            decoration: _field('Add your own trait').copyWith(
              suffixIcon: IconButton(icon: const Icon(Icons.add), tooltip: 'Add trait', onPressed: _addCustomTrait),
            ),
          ),
          TextField(
            controller: _style,
            maxLength: 160,
            minLines: 1,
            maxLines: 3,
            decoration: _field('How you communicate', hint: 'e.g. I think out loud and like getting to the point.'),
          ),
          TextField(
            controller: _about,
            maxLength: 280,
            minLines: 2,
            maxLines: 5,
            decoration: _field('About you', hint: 'A line or two about what drives you'),
          ),

          _section("What you're into"),
          TextField(controller: _interests, decoration: _field('Interests', helper: 'Separate with commas, up to 8')),
          const SizedBox(height: 12),
          TextField(controller: _likes, decoration: _field('Things you like', helper: 'Separate with commas, up to 8')),

          _section('Stay in touch', subtitle: 'Optional. Only people you both share with can see these.'),
          for (var i = 0; i < _links.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _links[i],
                keyboardType: TextInputType.url,
                decoration: _field('Link ${i + 1}', hint: _linkHints[i], icon: Icons.link),
              ),
            ),

          const SizedBox(height: 8),
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
