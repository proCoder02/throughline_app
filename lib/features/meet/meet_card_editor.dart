import 'package:flutter/material.dart';

import '../../theme.dart';
import 'meet_api.dart';
import 'meet_card_view.dart';
import 'meet_models.dart';
import 'meet_style.dart';

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
  late final _hook = TextEditingController(text: _c.hook);
  late final _askMe = TextEditingController(text: _c.askMe);
  late final _about = TextEditingController(text: _c.about);
  late final _interests = TextEditingController(text: _c.interests.join(', '));
  late final _likes = TextEditingController(text: _c.likes.join(', '));
  late final _links = List.generate(3, (i) => TextEditingController(text: i < _c.links.length ? _c.links[i] : ''));
  late final _customTrait = TextEditingController();
  late List<String> _traits = [..._c.traits];
  late bool _sharing = _c.sharing;
  late String _color = _c.color;
  bool _saving = false;
  bool _suggesting = false;

  List<TextEditingController> get _all =>
      [_headline, _organization, _city, _education, _style, _hook, _askMe, _about, _interests, _likes, ..._links, _customTrait];

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
        hook: _hook.text.trim(),
        askMe: _askMe.text.trim(),
        color: _color,
        about: _about.text.trim(),
        traits: _traits,
        interests: _split(_interests.text),
        likes: _split(_likes.text),
        links: _links.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(),
        sharing: _sharing,
      );

  /// The pieces of a strong first impression, most important first --
  /// drives the meter and the one tip shown under it.
  List<(bool, String)> get _checklist {
    final c = _card;
    return [
      (widget.initial.me.photo != null && widget.initial.me.photo!.isNotEmpty,
          'Add a profile photo in Settings -- faces are what people remember'),
      (c.headline.isNotEmpty, 'Add your role, e.g. "Product designer"'),
      (c.hook.isNotEmpty, "Write a one-line hook -- it's the first thing people read"),
      (c.traits.isNotEmpty, 'Pick a few traits that sound like you'),
      (c.askMe.isNotEmpty, 'Add "Ask me about" so people know how to start talking'),
      (c.organization.isNotEmpty || c.city.isNotEmpty, 'Add where you work or your city'),
      (c.interests.isNotEmpty, "Add a few things you're into"),
      (c.links.isNotEmpty, 'Add a link (LinkedIn, Instagram...) so people can stay in touch'),
    ];
  }

  Widget _meter() {
    final items = _checklist;
    final done = items.where((i) => i.$1).length;
    final pct = done / items.length;
    final tip = items.where((i) => !i.$1).map((i) => i.$2).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(pct >= 1 ? 'Your card makes a great first impression' : 'Your card is ${(pct * 100).round()}% done',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
            ),
            Text('$done/${items.length}', style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: AppColors.border,
              color: meetColorFor(_color, widget.initial.me.name),
            ),
          ),
          if (tip != null) ...[
            const SizedBox(height: 8),
            Text('Next: $tip', style: TextStyle(color: AppColors.textSoft, fontSize: 13, height: 1.35)),
          ],
        ],
      ),
    );
  }

  Widget _colorPicker() {
    final names = widget.initial.colors.isNotEmpty ? widget.initial.colors : meetColors.keys.toList();
    final effective = meetColorFor(_color, widget.initial.me.name);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final name in names)
          Semantics(
            button: true,
            selected: meetColors[name] == effective,
            label: '$name card colour',
            child: GestureDetector(
              onTap: () => setState(() => _color = name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: meetColors[name],
                  shape: BoxShape.circle,
                  border: Border.all(color: meetColors[name] == effective ? AppColors.text : Colors.transparent, width: 3),
                ),
                child: meetColors[name] == effective ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            ),
          ),
      ],
    );
  }

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
          const SizedBox(height: 14),
          _meter(),

          _section('Who you are'),
          TextField(controller: _headline, maxLength: 80, decoration: _field('Role or headline', hint: 'e.g. Product designer', icon: Icons.badge_outlined)),
          TextField(controller: _organization, maxLength: 80, decoration: _field('Company or organisation', icon: Icons.business_outlined)),
          TextField(controller: _city, maxLength: 80, decoration: _field('City', icon: Icons.place_outlined)),
          TextField(controller: _education, maxLength: 80, decoration: _field('Education', hint: 'e.g. MBA, IIM Indore', icon: Icons.school_outlined)),

          _section('Your hook', subtitle: "One line people read first -- what's memorable about you, not your job title."),
          TextField(
            controller: _hook,
            maxLength: 90,
            minLines: 1,
            maxLines: 2,
            decoration: _field('Hook', hint: 'e.g. Builds AI products; happiest on a mountain trail.'),
          ),
          TextField(
            controller: _askMe,
            maxLength: 80,
            decoration: _field('Ask me about', hint: 'e.g. trekking in Ladakh', icon: Icons.chat_bubble_outline),
          ),

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

          _section('Card colour'),
          _colorPicker(),

          const SizedBox(height: 16),
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
          MeetCardView(card: _card, person: widget.initial.me, initiallyExpanded: true),
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
