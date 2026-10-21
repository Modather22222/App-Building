import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  // Redirects re-evaluate whenever onboarding/session state changes.
  final onboarded = ref.watch(onboardingProvider);
  final session = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/chats',
    redirect: (context, state) {
      final path = state.uri.path;
      if (!onboarded) {
        return path == '/onboarding' ? null : '/onboarding';
      }
      if (path == '/onboarding') return '/chats';
      if (session == null) return path == '/auth' ? null : '/auth';
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
});
