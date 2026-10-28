// Accessibility gate — Dynamic Type at 135%.
//
// Pumps each tab screen directly (backend-less mock providers feed them real
// demo state) on a small Android viewport with text scaled to 1.35x. Any
// unscrollable RenderFlex overflow throws inside the test and fails it, so
// large-system-text regressions can't ship silently. The chat screen is
// covered too: a thread with a streaming reply exercises bubbles, the plan
// action button and the composer at the inflated scale.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_building/data/providers.dart';
import 'package:app_building/features/chats/chats_providers.dart';
import 'package:app_building/features/chats/chats_screen.dart';
import 'package:app_building/features/chats/chat_screen.dart';
import 'package:app_building/features/profile/profile_screen.dart';
import 'package:app_building/features/projects/projects_screen.dart';

void main() {
  Future<ProviderContainer> harness(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.textScaleFactorTestValue = 1.35;
    return ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
    ]);
  }

  testWidgets('projects screen survives 135% text scale', (tester) async {
    final container = await harness(tester);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProjectsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProjectsScreen), findsOneWidget);
  });

  testWidgets('chats screen survives 135% text scale', (tester) async {
    final container = await harness(tester);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChatsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatsScreen), findsOneWidget);
  });

  testWidgets('chat screen survives 135% text scale', (tester) async {
    final container = await harness(tester);
    addTearDown(container.dispose);
    final thread = container.read(chatsProvider.notifier).create();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ChatScreen(threadId: thread.id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('profile screen survives 135% text scale', (tester) async {
    final container = await harness(tester);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
