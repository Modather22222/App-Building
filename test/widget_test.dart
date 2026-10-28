import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_building/core/theme/app_theme.dart';

void main() {
  test('App Building ships an M3 theme with light + dark semantics', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.useMaterial3, isTrue);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
  });
}
