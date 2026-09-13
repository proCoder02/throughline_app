import 'package:fade_out_particle/fade_out_particle.dart';
import 'package:flutter/material.dart';

import 'typing_indicator.dart';

/// The "assistant is typing" row, but instead of being yanked out of the
/// message list the instant a real reply lands (its old behavior), it
/// dissolves into particles right as the reply appears above it -- this is
/// what fade_out_particle is actually for (a *disappearing* view), unlike
/// the reply itself, which should be arriving, not fading out.
///
/// Driven the package's intended way: the host screen keeps this same row
/// mounted at the same list position and just flips [disappear] from false
/// to true once the reply is ready, then removes the row (via
/// [onDissolved]) once the particle burst finishes.
class DissolvingTypingIndicator extends StatelessWidget {
  final bool disappear;
  final VoidCallback onDissolved;

  const DissolvingTypingIndicator({super.key, required this.disappear, required this.onDissolved});

  @override
  Widget build(BuildContext context) {
    return FadeOutParticle(
      disappear: disappear,
      duration: const Duration(milliseconds: 550),
      onAnimationEnd: onDissolved,
      child: const TypingIndicator(),
    );
  }
}
