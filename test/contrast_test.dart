// Accessibility gate — WCAG 2.1 contrast for the status-pill system.
//
// The pill renders its label in the status color over a 12% tint of that
// same color on the surface. The check therefore measures against the
// BLENDED background, not the bare surface — the tint shifts the ratio
// enough to flip pass/fail. Body-size text requires >= 4.5:1.
//
// Per-mode status colors (light needs darker inks, dark needs lighter ones)
// live in AppTokens.statusColorsFor(Brightness).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_building/core/theme/tokens.dart';
import 'package:app_building/data/models.dart';

double _linearChannel(double v) => v <= 0.03928
    ? v / 12.92
    : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) => 0.2126 * _linearChannel(c.r) +
    0.7152 * _linearChannel(c.g) +
    0.0722 * _linearChannel(c.b);

double _contrast(Color fg, Color bg) {
  final l1 = _luminance(fg);
  final l2 = _luminance(bg);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _tintedBg(Color status, Color surface) =>
    Color.alphaBlend(status.withValues(alpha: 0.12), surface);

void main() {
  const surfaces = {
    Brightness.light: Color(0xFFFAFAF8),
    Brightness.dark: Color(0xFF0B0C10),
  };

  for (final entry in surfaces.entries) {
    final mode = entry.key;
    final surface = entry.value;
    final colors = AppTokens.statusColorsFor(mode);

    for (final stage in BuildStage.values) {
      test('contrast ${mode.name}: ${stage.name} label on its pill >= 4.5', () {
        final status = colors[stage]!;
        final ratio = _contrast(status, _tintedBg(status, surface));
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$mode ${stage.name} ${status.toARGB32().toRadixString(16)} '
              'on its tinted pill = ${ratio.toStringAsFixed(2)}:1',
        );
      });
    }

    test('contrast ${mode.name}: failed label on its pill >= 4.5', () {
      final status = AppTokens.failureFor(mode);
      final ratio = _contrast(status, _tintedBg(status, surface));
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$mode failed ${status.toARGB32().toRadixString(16)} '
            'on its tinted pill = ${ratio.toStringAsFixed(2)}:1',
      );
    });
  }
}
