import 'package:supabase_flutter/supabase_flutter.dart';

/// Compile-time backend config.
///
/// The publishable key (`sb_publishable_...`) is public by design — safe to
/// ship to clients — but is supplied via `--dart-define` so local widget tests
/// and CI builds without secrets stay green and backend-less.
class SupabaseConfig {
  const SupabaseConfig._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://loeaiuktjmhxeoxpyqjl.supabase.co',
  );

  static const anonKeyString = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Modern key name — same value, non-deprecated API surface.
  static String get publishableKey => anonKeyString;

  /// When false the app runs backend-less: auth sign-in reports a clear error
  /// and chats degrade to in-memory, exactly like the pre-Phase 2 build.
  static bool get enabled => publishableKey.isNotEmpty;

  static SupabaseClient? _client;

  /// Call [init] first from main() when [enabled] is true.
  static SupabaseClient get client {
    final existing = _client;
    if (existing != null) return existing;
    return _client = Supabase.instance.client;
  }

  static Future<void> init() async {
    if (!enabled) return;
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }
}
