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

  // Semantic build-status colors
  static const Color statusGenerating = Color(0xFF5457D6);
  static const Color statusPushing = Color(0xFF818CF8);
  static const Color statusQueued = Color(0xFFB45309); // amber-700
  static const Color statusBuilding = Color(0xFF0284C7); // sky-600
  static const Color statusReady = Color(0xFF16A34A); // green-600
  static const Color statusFailed = Color(0xFFDC2626); // red-600

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
    switch (stage) {
      case BuildStage.generating:
        return statusGenerating;
      case BuildStage.pushing:
        return statusPushing;
      case BuildStage.queued:
        return statusQueued;
      case BuildStage.building:
        return statusBuilding;
      case BuildStage.ready:
        return statusReady;
    }
  }
}
