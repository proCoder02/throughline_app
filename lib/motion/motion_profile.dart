// Adaptive home-screen motion (see ADAPTIVE_HOME_ANIMATION_PLAN.md in the
// backend repo). The server only ever hands over plain signals
// (mood_bucket, chat_tone) -- this file owns the entire decision of what
// those signals mean for motion. Nothing here is ever parsed from JSON;
// it's a small, reviewed Dart table, same discipline as the rest of the
// app's UI code.
import 'package:flutter/material.dart';

enum TimeBucket { morning, afternoon, evening, night }

enum MoodBucket { positive, neutral, low, stressed }

enum ChatTone { resolved, celebratory, heavy, routine }

enum MotionProfile { lively, balanced, gentle, minimal }

/// Local device clock only -- never worth a network round trip, and
/// timezone-correct by construction since it reads the device's own time.
TimeBucket currentTimeBucket([DateTime? at]) {
  final hour = (at ?? DateTime.now()).hour;
  if (hour >= 5 && hour < 8) return TimeBucket.morning;
  if (hour >= 8 && hour < 17) return TimeBucket.afternoon;
  if (hour >= 17 && hour < 21) return TimeBucket.evening;
  return TimeBucket.night;
}

MoodBucket? moodBucketFromString(String? value) {
  switch (value) {
    case 'positive': return MoodBucket.positive;
    case 'neutral': return MoodBucket.neutral;
    case 'low': return MoodBucket.low;
    case 'stressed': return MoodBucket.stressed;
    default: return null;
  }
}

ChatTone? chatToneFromString(String? value) {
  switch (value) {
    case 'resolved': return ChatTone.resolved;
    case 'celebratory': return ChatTone.celebratory;
    case 'heavy': return ChatTone.heavy;
    case 'routine': return ChatTone.routine;
    default: return null;
  }
}

/// The single decision table for whole-screen entrance motion. `chatTone`
/// (a just-finished conversation) takes priority over the ambient
/// time+mood combination when it says something specific -- `routine` (or
/// no chat_tone at all) falls through to the ambient rule below it exactly
/// like v1 always has.
MotionProfile profileFor({required TimeBucket time, MoodBucket? mood, ChatTone? chatTone}) {
  if (chatTone == ChatTone.celebratory) return MotionProfile.lively;
  if (chatTone == ChatTone.heavy) return MotionProfile.gentle;
  if (chatTone == ChatTone.resolved) return MotionProfile.balanced;

  if (mood == MoodBucket.stressed) return MotionProfile.minimal; // calm down, not up
  if (time == TimeBucket.night) return MotionProfile.minimal;
  if (mood == MoodBucket.low) return MotionProfile.gentle;
  if (time == TimeBucket.morning && mood == MoodBucket.positive) return MotionProfile.lively;
  return MotionProfile.balanced; // the safe, always-available default
}

class MotionSpec {
  final Duration entranceDuration;
  final Curve entranceCurve;
  final int staggerMs;
  final double slideDistance; // px the entrance travels upward

  const MotionSpec({
    required this.entranceDuration,
    required this.entranceCurve,
    required this.staggerMs,
    required this.slideDistance,
  });
}

/// `balanced` is deliberately identical to FadeSlideIn's original hardcoded
/// constants (260ms/easeOut/18ms-stagger/0.06 offset ~= 6px at typical row
/// height) -- passing no profile at all must look exactly like it always
/// has, not a subtly different "new default."
const motionSpecs = {
  MotionProfile.lively: MotionSpec(
    entranceDuration: Duration(milliseconds: 340), entranceCurve: Curves.easeOutBack,
    staggerMs: 26, slideDistance: 10,
  ),
  MotionProfile.balanced: MotionSpec(
    entranceDuration: Duration(milliseconds: 260), entranceCurve: Curves.easeOut,
    staggerMs: 18, slideDistance: 6,
  ),
  MotionProfile.gentle: MotionSpec(
    entranceDuration: Duration(milliseconds: 300), entranceCurve: Curves.easeOut,
    staggerMs: 12, slideDistance: 4,
  ),
  MotionProfile.minimal: MotionSpec(
    entranceDuration: Duration(milliseconds: 180), entranceCurve: Curves.easeOut,
    staggerMs: 0, slideDistance: 2,
  ),
};
