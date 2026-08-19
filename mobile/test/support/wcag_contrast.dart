import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.1 relative luminance, from the spec's own formula.
double channel(int v) {
  final c = v / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) as double;
}

double luminance(Color c) =>
    0.2126 * channel((c.r * 255).round()) +
    0.7152 * channel((c.g * 255).round()) +
    0.0722 * channel((c.b * 255).round());

/// WCAG 2.1 contrast ratio, `(L1+0.05)/(L2+0.05)` with the lighter colour
/// first — order doesn't matter here, the larger luminance always wins the
/// numerator.
double contrast(Color a, Color b) {
  final la = luminance(a), lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [fg] at its own alpha composited onto opaque [bg].
Color flatten(Color fg, Color bg) => Color.alphaBlend(fg, bg);
