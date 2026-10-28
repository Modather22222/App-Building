import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../features/auth/auth_screen.dart';
import '../features/chats/chat_screen.dart';
import '../features/chats/chats_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/projects/project_detail_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/shell/home_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Phase 7 — ONE GoRouter for the app's lifetime. The old provider watched
  // auth/onboarding directly and rebuilt the whole router on every auth
  // event (including token refreshes), resetting the navigation stack
  // mid-flow. State changes now drive `refreshListenable`, and `redirect`
  // reads the mirrored notifiers.
  final onboarded = ValueNotifier<bool>(ref.read(onboardingProvider));
  final session = ValueNotifier<AuthSession?>(ref.read(authProvider));
  ref
    ..listen(onboardingProvider, (_, bool v) => onboarded.value = v)
    ..listen(authProvider, (_, AuthSession? v) => session.value = v);

  final router = GoRouter(
    initialLocation: '/chats',
    refreshListenable: Listenable.merge([onboarded, session]),
    redirect: (context, state) {
      final path = state.uri.path;
      if (!onboarded.value) {
        return path == '/onboarding' ? null : '/onboarding';
      }
      if (path == '/onboarding') return '/chats';
      if (session.value == null) return path == '/auth' ? null : '/auth';
      if (path == '/auth') return '/chats';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/chats', builder: (_, _) => const ChatsScreen()),
              GoRoute(
                path: '/chat/:id',
                builder: (_, state) =>
                    ChatScreen(threadId: state.pathParameters['id']!),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/apps', builder: (_, _) => const ProjectsScreen()),
              GoRoute(
                path: '/project/:id',
                builder: (_, state) =>
                    ProjectDetailScreen(projectId: state.pathParameters['id']!),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    onboarded.dispose();
    session.dispose();
  });
  return router;
});
