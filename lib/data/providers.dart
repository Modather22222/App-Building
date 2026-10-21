import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

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
  @override
  AuthSession? build() {
    final prefs = ref.read(sharedPrefsProvider);
    final email = prefs.getString('auth.email');
    if (email == null) return null;
    return AuthSession(
      name: prefs.getString('auth.name') ?? email.split('@').first,
      email: email,
      guest: prefs.getBool('auth.guest') ?? false,
    );
  }

  Future<void> signIn({required String email, String? name}) {
    final displayName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : email.split('@').first;
    return _persist(AuthSession(name: displayName, email: email));
  }

  Future<void> signInAsGuest() => _persist(
    const AuthSession(
      name: 'Guest dev',
      email: 'guest@local.device',
      guest: true,
    ),
  );

  Future<void> _persist(AuthSession session) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString('auth.email', session.email);
    await prefs.setString('auth.name', session.name);
    await prefs.setBool('auth.guest', session.guest);
    state = session;
  }

  Future<void> signOut() async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.remove('auth.email');
    await prefs.remove('auth.name');
    await prefs.remove('auth.guest');
    state = null;
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
