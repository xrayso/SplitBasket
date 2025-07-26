import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Builds a stable, non‑black/non‑white colour from an arbitrary string.
/// • Hue comes from a hash of the string → different names → different hues
/// • Saturation & lightness are kept in a pleasant mid‑range so the colour
///   never collapses to black or white.
Color colorForName(String name) {
  final int hash = name.hashCode;
  final double hue = (hash % 360).toDouble();             // 0‑359°
  const double sat = 0.65;                                // 65 % vividness
  const double light = 0.55;                              // 55 % pastel
  return HSLColor.fromAHSL(1.0, hue, sat, light).toColor();
}

/// Returns a shade of [base] that has *opposite* brightness from the
/// surrounding theme, but never black/white.
Color onColor(Color base, Brightness theme) {
  final hsl = HSLColor.fromColor(base);
  // Push lightness up or down 20 % without hitting the extremes.
  final double delta = theme == Brightness.dark ? 0.20 : -0.20;
  final double l = (hsl.lightness + delta).clamp(0.15, 0.85);
  return hsl.withLightness(l).toColor();
}
