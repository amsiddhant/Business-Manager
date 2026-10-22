import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How much the interface animates.
///
/// - [full]: fades, slides, scales, chart build-ups.
/// - [reduced]: fades only — nothing moves on screen.
/// - [off]: no animation at all.
enum MotionLevel {
  full('Full'),
  reduced('Reduced'),
  off('Off');

  const MotionLevel(this.label);
  final String label;

  /// The stricter of two levels.
  MotionLevel atMost(MotionLevel other) =>
      MotionLevel.values[math.max(index, other.index)];

  static MotionLevel fromName(String? name) => MotionLevel.values
      .firstWhere((m) => m.name == name, orElse: () => MotionLevel.full);
}

/// Motion timings for the current [level]. Read with `context.motion`, which
/// also honours the operating system's "reduce motion" setting.
///
/// Rules: animate only when a value changes, never loop, and keep it short.
@immutable
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion([this.level = MotionLevel.full]);

  final MotionLevel level;

  static const Curve standard = Curves.easeInOutCubic;
  static const Curve emphasized = Curves.easeOutCubic;

  bool get enabled => level != MotionLevel.off;

  /// Slides, scales and chart build-ups are allowed.
  bool get allowsMovement => level == MotionLevel.full;

  Duration get fast => _fade(120);
  Duration get base => _fade(200);
  Duration get slow => _fade(320);

  /// Charts drawing in (movement — off unless [allowsMovement]).
  Duration get chart => allowsMovement ? const Duration(milliseconds: 650) : Duration.zero;

  /// Delay between items of a staggered entrance.
  Duration get stagger => allowsMovement ? const Duration(milliseconds: 40) : Duration.zero;

  Duration _fade(int ms) =>
      enabled ? Duration(milliseconds: ms) : Duration.zero;

  @override
  AppMotion copyWith({MotionLevel? level}) => AppMotion(level ?? this.level);

  @override
  AppMotion lerp(AppMotion? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
