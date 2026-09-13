import 'package:flutter/material.dart';

import '../../motion/motion_profile.dart';
import '../../services/home_signals_service.dart';
import '../../theme.dart';

/// Live debug view for the "adaptive home screen motion" feature (see
/// ADAPTIVE_HOME_ANIMATION_PLAN.md) -- reachable only from Settings,
/// entirely self-contained (no production screen is touched or shared), so
/// it's safe to poke at. Uses the REAL `motion_profile.dart` decision table
/// and a REAL `GET /me/home-signals` fetch -- this is not a mockup of the
/// feature, it's the feature's own logic pointed at a scratch layout, which
/// is also why this is a much more reliable way to see it than the real
/// home screen: ChatsScreen only fetches its signals once per app launch
/// and its rows only ever play their entrance animation once, so seeing a
/// changed chat_tone there requires a full app restart. This screen is a
/// fresh widget tree every time you open it from Settings, so every
/// combination replays on demand.
///
/// Chips below default to the real, currently-live time/mood/chat_tone but
/// can be overridden to test any combination without needing to actually
/// wait for the real time to change or finish a real chat first.
///
/// Also demonstrates the "theme engine" half of the design: a per-time-
/// period background gradient + greeting style, with mood modulating
/// ambient motion intensity on top -- same "LLM/server picks a name, a
/// local Dart table owns the actual values" discipline as MotionProfile.
/// Deliberately NOT applied to the real ChatsScreen: that screen already
/// has a shipped, hand-designed warm-gradient brand look
/// (AppColors.dmGradient) used consistently across every main-tab screen,
/// and swapping to a cycling per-time-period palette there is a real
/// visual-identity decision, not a side effect of a motion feature -- this
/// sandbox is where to look at the idea without committing to it.
class HomeThemeSpec {
  final List<Color> backgroundGradient;
  final double ambientMotionIntensity; // 0..1 base, before the mood multiplier below
  final String greetingStyle;
  final String greetingSubtitle;

  const HomeThemeSpec({
    required this.backgroundGradient,
    required this.ambientMotionIntensity,
    required this.greetingStyle,
    required this.greetingSubtitle,
  });
}

// Colors taken directly from the proposed time-period palettes; evening's
// original was a radial gradient (not supported by a plain LinearGradient
// crossfade here, see AnimatedContainer below) so it's applied linearly
// instead -- same colors, different geometry. TimeBucket only has 4
// values, so the original 6-period version's "early_morning" folds into
// "morning" and "deep_night" folds into "night" (this screen's `time` chip
// already only offers 4 choices, same as production).
const _themeByTime = {
  TimeBucket.morning: HomeThemeSpec(
    backgroundGradient: [Color(0xFF102B36), Color(0xFF164B55), Color(0xFF1B6B68)],
    ambientMotionIntensity: 0.9,
    greetingStyle: 'energetic',
    greetingSubtitle: 'Ready for the day?',
  ),
  TimeBucket.afternoon: HomeThemeSpec(
    backgroundGradient: [Color(0xFF101820), Color(0xFF152B31), Color(0xFF183C3D)],
    ambientMotionIntensity: 0.7,
    greetingStyle: 'neutral',
    greetingSubtitle: 'Busy day so far.',
  ),
  TimeBucket.evening: HomeThemeSpec(
    backgroundGradient: [Color(0xFF241D35), Color(0xFF17243A), Color(0xFF101820)],
    ambientMotionIntensity: 0.65,
    greetingStyle: 'warm',
    greetingSubtitle: 'How was your day?',
  ),
  TimeBucket.night: HomeThemeSpec(
    backgroundGradient: [Color(0xFF090D18), Color(0xFF0D1324), Color(0xFF101A2E)],
    ambientMotionIntensity: 0.25,
    greetingStyle: 'calm',
    greetingSubtitle: 'Take it easy.',
  ),
};

// Mood modifies the base ambient intensity above rather than each mood
// getting its own separate theme -- same base-plus-modifier idea as
// proposed, kept to the one dimension (motion intensity) actually wired
// into a visible effect here (the hero card's breathing amplitude).
// Stressed damps hardest and deliberately independent of time-of-day: a
// stressed morning must not still animate like a lively one.
const _ambientMoodMultiplier = {
  MoodBucket.positive: 1.15,
  MoodBucket.neutral: 1.0,
  MoodBucket.low: 0.45,
  MoodBucket.stressed: 0.2,
};

// `_themeByTime`'s gradients are dark for every time period (matching the
// proposed palette, which assumes a dark backdrop throughout, unlike
// AppColors.dmGradient which flips light/dark with the app's own theme
// setting) -- text/icons sitting directly on that gradient (not inside a
// dmBubbleIn card, which has its own correctly-paired dmText) need a fixed
// light color regardless of the app's light/dark mode, or light-mode text
// would render dark-on-dark and disappear.
const _onGradientText = Color(0xFFF3F5F8);
const _onGradientTextSoft = Color(0xFFAEB8C4);

class HomePreviewScreen extends StatefulWidget {
  const HomePreviewScreen({super.key});

  @override
  State<HomePreviewScreen> createState() => _HomePreviewScreenState();
}

class _HomePreviewScreenState extends State<HomePreviewScreen> {
  final _signalsService = HomeSignalsService();

  var _time = currentTimeBucket();
  MoodBucket? _mood;
  ChatTone? _chatTone;

  // What the server actually returned, kept separate from the (possibly
  // overridden) chip selections above so this screen can show "here's what
  // is really live right now" even while you're testing something else.
  bool _loadingLive = true;
  Object? _liveError;

  @override
  void initState() {
    super.initState();
    _syncWithLiveSignals();
  }

  Future<void> _syncWithLiveSignals() async {
    setState(() {
      _loadingLive = true;
      _liveError = null;
    });
    try {
      final signals = await _signalsService.fetch();
      if (!mounted) return;
      setState(() {
        _time = currentTimeBucket();
        _mood = signals.mood;
        _chatTone = signals.chatTone;
        _loadingLive = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingLive = false;
        _liveError = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = profileFor(time: _time, mood: _mood, chatTone: _chatTone);
    final spec = motionSpecs[profile]!;
    final baseBreathe = _breatheByProfile[profile]!;
    final theme = _themeByTime[_time]!;
    final moodMultiplier = _ambientMoodMultiplier[_mood] ?? 1.0;
    // Applies the mood modifier to the breathing amplitude specifically
    // (the one dimension of "ambient motion intensity" this screen
    // actually renders) -- scaled around 1.0 so a multiplier < 1 pulls the
    // swell back toward motionless rather than shrinking below it.
    final breathe = _BreatheSpec(
      scale: 1.0 + (baseBreathe.scale - 1.0) * theme.ambientMotionIntensity * moodMultiplier,
      duration: baseBreathe.duration,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight, colors: theme.backgroundGradient,
      )),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: _onGradientText),
          titleTextStyle: appHeadlineFont(color: _onGradientText, fontSize: 19),
          title: const Text('Home Concept'),
          actions: [
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync with live signals',
              onPressed: _loadingLive ? null : _syncWithLiveSignals,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text(
              'Uses the real motion_profile.dart decision table and a real '
              'GET /me/home-signals fetch. Chips below start at whatever is '
              'live right now -- override any of them to test a combination '
              'on demand. Reopen this screen (or tap sync) any time to '
              'replay the entrance animations.',
              style: TextStyle(fontSize: 13, color: _onGradientTextSoft, height: 1.4),
            ),
            const SizedBox(height: 10),
            _LiveSignalLine(loading: _loadingLive, error: _liveError, mood: _mood, chatTone: _chatTone),
            const SizedBox(height: 18),

            _ChipRow<TimeBucket>(
              label: 'Time of day',
              values: TimeBucket.values,
              selected: _time,
              labelOf: (v) => _timeLabel[v]!,
              onSelected: (v) => setState(() => _time = v),
            ),
            const SizedBox(height: 12),
            _ChipRow<MoodBucket?>(
              label: 'Mood',
              values: const [null, ...MoodBucket.values],
              selected: _mood,
              labelOf: (v) => v == null ? 'None' : _moodLabel[v]!,
              onSelected: (v) => setState(() => _mood = v),
            ),
            const SizedBox(height: 12),
            _ChipRow<ChatTone?>(
              label: 'Chat tone (from a just-finished chat)',
              values: const [null, ...ChatTone.values],
              selected: _chatTone,
              labelOf: (v) => v == null ? 'None' : _chatToneLabel[v]!,
              onSelected: (v) => setState(() => _chatTone = v),
            ),
            const SizedBox(height: 22),

            // Re-keying on the resolved profile (not on every input) means
            // picking a different combo that happens to resolve to the
            // *same* profile doesn't needlessly replay the entrance --
            // only an actual change in motion behavior does.
            _HeroCard(
              key: ValueKey(profile), profile: profile, breathe: breathe,
              time: _time, mood: _mood, chatTone: _chatTone, greetingSubtitle: theme.greetingSubtitle,
            ),
            const SizedBox(height: 18),

            Text('Quick glance', style: appHeadlineFont(color: _onGradientText, fontSize: 15)),
            const SizedBox(height: 10),
            for (final (i, item) in const [
              (Icons.chat_bubble_outline, 'Messages', '3 unread from 2 friends'),
              (Icons.task_alt, 'Tasks', '2 due today'),
              (Icons.insights_outlined, 'Weekly insight', 'Your mood trended up this week'),
            ].indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _EntranceCard(
                  key: ValueKey('${profile.name}-$i'),
                  delay: Duration(milliseconds: spec.staggerMs * i),
                  duration: spec.entranceDuration,
                  curve: spec.entranceCurve,
                  slideDistance: spec.slideDistance,
                  child: _QuickGlanceRow(icon: item.$1, title: item.$2, subtitle: item.$3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveSignalLine extends StatelessWidget {
  final bool loading;
  final Object? error;
  final MoodBucket? mood;
  final ChatTone? chatTone;

  const _LiveSignalLine({required this.loading, required this.error, required this.mood, required this.chatTone});

  @override
  Widget build(BuildContext context) {
    String text;
    if (loading) {
      text = 'Loading live signals...';
    } else if (error != null) {
      text = 'Could not fetch live signals ($error) -- chips below default to time-only.';
    } else {
      text = 'Live right now: mood_bucket=${mood?.name ?? 'null'}, chat_tone=${chatTone?.name ?? 'null'}';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(loading ? Icons.hourglass_empty : (error != null ? Icons.error_outline : Icons.check_circle_outline),
            size: 14, color: AppColors.dmAccent),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: _onGradientTextSoft))),
      ],
    );
  }
}

class _BreatheSpec {
  final double scale;
  final Duration duration;
  const _BreatheSpec({required this.scale, required this.duration});
}

/// Sandbox-only supplement to the real `motionSpecs` -- the hero card's
/// ambient breathing loop isn't part of production `FadeSlideIn`, so it has
/// no equivalent in motion_profile.dart to reuse; kept local and small
/// rather than adding a hero-card-specific concept to the shared file.
const _breatheByProfile = {
  MotionProfile.lively: _BreatheSpec(scale: 1.035, duration: Duration(milliseconds: 1600)),
  MotionProfile.balanced: _BreatheSpec(scale: 1.02, duration: Duration(milliseconds: 2400)),
  MotionProfile.gentle: _BreatheSpec(scale: 1.012, duration: Duration(milliseconds: 3200)),
  MotionProfile.minimal: _BreatheSpec(scale: 1.0, duration: Duration(milliseconds: 4000)),
};

const _timeLabel = {
  TimeBucket.morning: 'Morning',
  TimeBucket.afternoon: 'Afternoon',
  TimeBucket.evening: 'Evening',
  TimeBucket.night: 'Night',
};
const _moodLabel = {
  MoodBucket.positive: 'Positive',
  MoodBucket.neutral: 'Neutral',
  MoodBucket.low: 'Low',
  MoodBucket.stressed: 'Stressed',
};

const _chatToneLabel = {
  ChatTone.resolved: 'Resolved',
  ChatTone.celebratory: 'Celebratory',
  ChatTone.heavy: 'Heavy',
  ChatTone.routine: 'Routine',
};

/// Mood-companion face (see assets/mood_faces/NOTICE for image credit) --
/// chat_tone takes priority over mood, same rule as `profileFor` itself,
/// since a just-finished conversation is more specific/recent than the
/// ambient 2-hour mood window. Falls back to the neutral face rather than
/// nothing when there's no signal at all -- an empty circle would read as
/// broken, a neutral face reads as "nothing to report."
String _faceAssetFor({required TimeBucket time, MoodBucket? mood, ChatTone? chatTone}) {
  if (chatTone == ChatTone.celebratory) return 'assets/mood_faces/celebratory.png';
  if (chatTone == ChatTone.heavy) return 'assets/mood_faces/low.png';
  if (chatTone == ChatTone.resolved) return 'assets/mood_faces/resolved.png';
  if (mood == MoodBucket.positive) return 'assets/mood_faces/positive.png';
  if (mood == MoodBucket.low) return 'assets/mood_faces/low.png';
  if (mood == MoodBucket.stressed) return 'assets/mood_faces/stressed.png';
  if (mood == null && time == TimeBucket.night) return 'assets/mood_faces/night.png';
  return 'assets/mood_faces/neutral.png';
}

const _profileLabel = {
  MotionProfile.lively: 'Lively',
  MotionProfile.balanced: 'Balanced',
  MotionProfile.gentle: 'Gentle',
  MotionProfile.minimal: 'Minimal',
};

class _ChipRow<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  const _ChipRow({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _onGradientTextSoft)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(labelOf(v)),
                selected: v == selected,
                onSelected: (_) => onSelected(v),
                selectedColor: AppColors.dmAccent,
                labelStyle: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: v == selected ? Colors.white : AppColors.dmText,
                ),
                backgroundColor: AppColors.dmBubbleIn,
                side: BorderSide(color: AppColors.dmBubbleBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
          ],
        ),
      ],
    );
  }
}

/// The "ambient, almost invisible" part of the design -- a slow, continuous
/// breathe (scale up/down) whose amplitude and speed come entirely from the
/// current MotionProfile. At `minimal` this is effectively motionless
/// (scale stays at 1.0), which is the point: calmer states get less motion,
/// not a different color of the same amount of motion.
class _HeroCard extends StatefulWidget {
  final MotionProfile profile;
  final _BreatheSpec breathe;
  final TimeBucket time;
  final MoodBucket? mood;
  final ChatTone? chatTone;
  final String greetingSubtitle;

  const _HeroCard({
    super.key,
    required this.profile,
    required this.breathe,
    required this.time,
    required this.mood,
    required this.chatTone,
    required this.greetingSubtitle,
  });

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.breathe.duration)..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: widget.breathe.scale)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.chatTone != null && widget.chatTone != ChatTone.routine
        ? 'A ${_chatToneLabel[widget.chatTone]!.toLowerCase()} chat just now -- motion set to '
            '${_profileLabel[widget.profile]!.toLowerCase()}'
        : 'Feeling ${widget.mood == null ? 'unknown' : _moodLabel[widget.mood]!.toLowerCase()} -- motion set to '
            '${_profileLabel[widget.profile]!.toLowerCase()}';
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.dmBubbleIn,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.dmBubbleBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: AppColors.dmAccent.withValues(alpha: 0.18), shape: BoxShape.circle),
              padding: const EdgeInsets.all(7),
              child: Image.asset(
                _faceAssetFor(time: widget.time, mood: widget.mood, chatTone: widget.chatTone),
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good ${_timeLabel[widget.time]!.toLowerCase()}',
                    style: appHeadlineFont(color: AppColors.dmText, fontSize: 17),
                  ),
                  Text(widget.greetingSubtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.dmAccent, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Parameterized one-shot fade+slide entrance -- same idea as the
/// production `FadeSlideIn` widget, but its duration/curve/delay/distance
/// come directly from `motionSpecs` (motion_profile.dart) instead of a
/// second, sandbox-only copy of those constants.
class _EntranceCard extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final double slideDistance;

  const _EntranceCard({
    super.key,
    required this.child,
    required this.delay,
    required this.duration,
    required this.curve,
    required this.slideDistance,
  });

  @override
  State<_EntranceCard> createState() => _EntranceCardState();
}

class _EntranceCardState extends State<_EntranceCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: widget.curve);
    _slide = Tween<Offset>(begin: Offset(0, widget.slideDistance / 100), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: widget.curve));
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _QuickGlanceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _QuickGlanceRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.dmAccent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.dmText)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
