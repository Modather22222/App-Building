import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/providers.dart';

Future<void> main() async {
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

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const AppFactoryApp(),
    ),
  );
}
