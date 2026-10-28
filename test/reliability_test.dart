// Phase 7 reliability gates — the fixes the audit called out, locked by tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:app_building/core/utils/links.dart';
import 'package:app_building/data/models.dart';

void main() {
  group('AppProject.copyWith preserves worker-owned fields', () {
    final project = AppProject(
      id: 'proj-x',
      name: 'X',
      summary: 's',
      createdAt: DateTime(2026),
      stage: BuildStage.ready,
      refused: true,
      buildInfo: const {'run_id': 1, 'run_number': 2, 'size_bytes': 3},
    );

    test('refused survives an unrelated copy', () {
      final copied = project.copyWith(stage: BuildStage.generating);
      expect(copied.refused, isTrue,
          reason: 'copyWith used to reset refused to false, making the meter '
              'count a refused attempt as spent budget until the next poll');
    });

    test('buildInfo survives an unrelated copy', () {
      final copied = project.copyWith(failed: false);
      expect(copied.buildInfo, isNotNull);
      expect(copied.buildInfo!['run_number'], 2);
    });

    test('explicit values still override', () {
      final copied = project.copyWith(refused: false);
      expect(copied.refused, isFalse);
    });
  });

  group('isTrustedDownloadUrl', () {
    test('accepts GitHub release hosts', () {
      expect(
        isTrustedDownloadUrl(
          'https://github.com/o/app-building-outputs/releases/download/af-x/app-release.apk',
        ),
        isTrue,
      );
      expect(
        isTrustedDownloadUrl(
          'https://objects.githubusercontent.com/x/app-release.apk',
        ),
        isTrue,
      );
    });

    test('rejects other schemes and hosts', () {
      expect(isTrustedDownloadUrl('http://github.com/x/app-release.apk'), isFalse);
      expect(isTrustedDownloadUrl('https://evil.example.com/x.apk'), isFalse);
      expect(isTrustedDownloadUrl('intents://x'), isFalse);
      expect(isTrustedDownloadUrl('not a url'), isFalse);
      expect(isTrustedDownloadUrl('https://github.com.evil.com/x.apk'), isFalse,
          reason: 'suffix spoofing must not pass — host must BE github.com '
              'or end with .github.com as a real label');
    });
  });
}
