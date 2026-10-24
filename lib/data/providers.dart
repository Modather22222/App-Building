import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'supabase_config.dart';

/// Overridden in main() with the real [SharedPreferences] instance.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override sharedPrefsProvider in main()');
});

class OnboardingState extends Notifier<bool> {
  @override
  bool build() => ref.read(sharedPrefsProvider).getBool('onboarded') ?? false;

  void complete() {
    unawaited(ref.read(sharedPrefsProvider).setBool('onboarded', true));
    state = true;
  }
}

final onboardingProvider = NotifierProvider<OnboardingState, bool>(
  OnboardingState.new,
);

class AuthState extends Notifier<AuthSession?> {
  StreamSubscription? _authEvents;

  @override
  AuthSession? build() {
    if (!SupabaseConfig.enabled) return null;
    final auth = SupabaseConfig.client.auth;
    _authEvents = auth.onAuthStateChange.listen(
      (event) => state = _fromSession(event.session),
    );
    ref.onDispose(() => _authEvents?.cancel());
    return _fromSession(auth.currentSession);
  }

  AuthSession? _fromSession(Session? session) {
    if (session == null) return null;
    final user = session.user;
    final email = user.email ?? '';
    final metaName = switch (user.userMetadata?['name']) {
      final String s when s.trim().isNotEmpty => s.trim(),
      _ => null,
    };
    final fallbackName = email.isEmpty ? 'Member' : email.split('@').first;
    return AuthSession(name: metaName ?? fallbackName, email: email);
  }

  Future<void> signIn({required String email, required String password}) async {
    await SupabaseConfig.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    // Router redirect follows the onAuthStateChange listener above.
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final response = await SupabaseConfig.client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );
    // Returns false when the project requires email confirmation — the UI
    // then asks the user to verify and switch to sign-in.
    return response.session != null;
  }

  Future<void> signOut() async {
    if (!SupabaseConfig.enabled) return;
    await SupabaseConfig.client.auth.signOut();
  }
}

final authProvider = NotifierProvider<AuthState, AuthSession?>(AuthState.new);

class ThemeModeState extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    switch (ref.read(sharedPrefsProvider).getString('theme.mode')) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void set(ThemeMode mode) {
    final prefs = ref.read(sharedPrefsProvider);
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    unawaited(prefs.setString('theme.mode', value));
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeState, ThemeMode>(
  ThemeModeState.new,
);
