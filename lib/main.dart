import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'data/providers.dart';
import 'data/supabase_config.dart';

/// Phase 7 — crash reporting via Sentry, gated on a compile-time DSN
/// (`--dart-define=SENTRY_DSN=…`). Empty DSN = fully disabled, so backend-less
/// builds and tests run exactly as before.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  if (_sentryDsn.isEmpty) {
    await _boot();
  } else {
    await SentryFlutter.init(
      (options) {
        options
          ..dsn = _sentryDsn
          ..environment = 'production'
          ..tracesSampleRate = 0.2
          ..sendDefaultPii = false;
      },
      appRunner: _boot,
    );
  }
}

Future<void> _boot() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    // Degrade gracefully: a broken platform plugin must never brick the app to a
    // white screen. The mock store keeps everything working in-memory for this
    // session (settings simply don't persist across restarts).
    debugPrint(
      'SharedPreferences unavailable ($e) — falling back to in-memory session prefs',
    );
    // Test-only API used deliberately as a production fallback: the mock store
    // routes all reads/writes to process memory.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }

  try {
    await SupabaseConfig.init();
  } catch (e) {
    // Without backend wiring the app still opens; sign-in will explain why.
    debugPrint('Supabase init failed ($e) — running backend-less');
    if (_sentryDsn.isNotEmpty) unawaited(Sentry.captureException(e));
  }

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const AppBuildingApp(),
    ),
  );
}
