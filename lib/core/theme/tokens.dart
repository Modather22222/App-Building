import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Design tokens — forked from the "Field" (Crafted Utility) palette with a
/// Midnight Pro-style semantic dark override (dribbble-world-class-mobile-design
/// skill). Primary hue tuned from violet to indigo: calmer and more trustworthy
/// for a developer-facing tool.
abstract final class AppTokens {
  // Brand
  static const Color brandLight = Color(0xFF6366F1); // indigo-500
  static const Color brandDark = Color(0xFF818CF8); // indigo-400

  // Semantic build-status colors — PER MODE. Status text sits on a 12% tint
  // of itself over the surface, and WCAG 2.1 (>= 4.5:1 for body text) is
  // measured against that blended pill background. One constant per mode
  // cannot pass both themes (light needs darker inks, dark needs lighter
  // ones) — the accessibility gate in test/contrast_test.dart enforces it.
  static const statusLight = <BuildStage, Color>{
    BuildStage.generating: Color(0xFF5457D6), // indigo, deep
    BuildStage.pushing: Color(0xFF4F46E5), // indigo-600
    BuildStage.queued: Color(0xFF92400E), // amber-800
    BuildStage.building: Color(0xFF0369A1), // sky-700
    BuildStage.ready: Color(0xFF166534), // green-800
  };
  static const statusDark = <BuildStage, Color>{
    BuildStage.generating: Color(0xFFA5B4FC), // indigo-300
    BuildStage.pushing: Color(0xFFA5B4FC), // indigo-300
    BuildStage.queued: Color(0xFFFCD34D), // amber-300
    BuildStage.building: Color(0xFF7DD3FC), // sky-300
    BuildStage.ready: Color(0xFF86EFAC), // green-300
  };
  static const failureLight = Color(0xFFB91C1C); // red-700
  static const failureDark = Color(0xFFFCA5A5); // red-300

  /// Status colors for [stage] on [brightness] — contrast-safe pill inks.
  static Map<BuildStage, Color> statusColorsFor(Brightness brightness) =>
      brightness == Brightness.light ? statusLight : statusDark;

  static Color? statusFor(Brightness brightness, BuildStage stage) =>
      statusColorsFor(brightness)[stage];

  /// Contrast-safe failure ink for [brightness].
  static Color failureFor(Brightness brightness) =>
      brightness == Brightness.light ? failureLight : failureDark;

  // Shape
  static const double radiusCard = 16;
  static const double radiusField = 14;
  static const double radiusButton = 12;
  static const double radiusSheet = 20;
  static const double radiusPill = 999;

  // Spacing (4/8pt grid)
  static const double gutter = 16;
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double gapLg = 16;
  static const double sectionGap = 32;

  static Color stageColor(BuildContext context, BuildStage stage) {
    final colors = statusColorsFor(Theme.of(context).brightness);
    return colors[stage] ?? failureFor(Theme.of(context).brightness);
  }

  /// Contrast-safe failure ink for the current theme.
  static Color failedColor(BuildContext context) =>
      failureFor(Theme.of(context).brightness);
}
