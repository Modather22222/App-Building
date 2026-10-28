import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/ids.dart';
import '../../data/chat_repository.dart';
import '../../data/mock/mock_chat_service.dart';
import '../../data/models.dart';
import '../../data/supabase_config.dart';

final chatRepositoryProvider = Provider<ChatRepository?>((ref) {
  if (!SupabaseConfig.enabled) return null;
  return const ChatRepository();
});

String? _currentUserId() {
  if (!SupabaseConfig.enabled) return null;
  return SupabaseConfig.client.auth.currentUser?.id;
}

class ChatsState extends Notifier<List<ChatThread>> {
  bool _bootstrapped = false;

  @override
  List<ChatThread> build() {
    if (!_bootstrapped) {
      _bootstrapped = true;
      unawaited(_loadFromStore());
    }
    return const [];
  }

  Future<void> _loadFromStore() async {
    final repo = ref.read(chatRepositoryProvider);
    final userId = _currentUserId();
    if (repo == null || userId == null) return;
    try {
      final rows = await repo.listChats(userId).timeout(
        const Duration(seconds: 5),
      );
      state = [
        for (final row in rows)
          ChatThread(
            id: row.id,
            title: row.title,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
          ),
      ];
    } catch (_) {
      // Offline or store unavailable — in-memory list continues to work.
    }
  }

  ChatThread create() {
    final now = DateTime.now();
    final thread = ChatThread(
      id: newId('chat'),
      title: 'New chat',
      createdAt: now,
      updatedAt: now,
    );
    state = [thread, ...state];

    final repo = ref.read(chatRepositoryProvider);
    final userId = _currentUserId();
    if (repo != null && userId != null) {
      unawaited(
        _safe(
          () => repo.insertChat(
            id: thread.id,
            userId: userId,
            title: thread.title,
          ),
        ),
      );
    }
    return thread;
  }

  void renameFromFirstMessage(String id, String message) {
    final title = _titleFrom(message);
    state = [
      for (final t in state)
        if (t.id == id)
          t
            ..title = title
            ..updatedAt = DateTime.now()
        else
          t,
    ];
    _push(
      id,
      update: ChatUpdate(
        title: title,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void touch(String id) {
    final now = DateTime.now();
    state = [
      for (final t in state)
        if (t.id == id) t..updatedAt = now else t,
    ];
    _push(id, update: ChatUpdate(updatedAt: now));
  }

  void _push(String id, {ChatUpdate? update}) {
    if (update == null) return;
    final repo = ref.read(chatRepositoryProvider);
    if (repo == null) return;
    unawaited(
      _safe(
        () => repo.renameChat(
          id: id,
          title: update.title,
          updatedAt: update.updatedAt,
        ),
      ),
    );
  }

  Future<void> _safe(Future Function() op) async {
    try {
      await op();
    } catch (_) {
      // Belongs to the graceful-degrade contract; the UI keeps working locally.
    }
  }
}

class ChatUpdate {
  const ChatUpdate({this.title, this.updatedAt});
  final String? title;
  final DateTime? updatedAt;
}

final chatsProvider = NotifierProvider<ChatsState, List<ChatThread>>(
  ChatsState.new,
);

class MessagesState extends FamilyNotifier<List<ChatMessage>, String> {
  bool _bootstrapped = false;

  static const _welcomePrefix = 'welcome-';

  @override
  List<ChatMessage> build(String arg) {
    if (!_bootstrapped) {
      _bootstrapped = true;
      // Defer past build(): bootstrap's synchronous path (mock mode seeds
      // the greeting with no await in between) touches state, which is
      // illegal while the provider is still building. Real-mode runs
      // suspend at the fetch await first, so only mock mode ever hit this.
      Future<void>.microtask(bootstrap);
    }
    return const [];
  }

  /// Pulls persisted messages for this thread. When the thread is brand new
  /// (or the store is offline) the agent greeting is seeded locally — it is
  /// intentionally never persisted.
  Future<void> bootstrap() async {
    final repo = ref.read(chatRepositoryProvider);
    if (repo == null) {
      _seedGreeting();
      return;
    }
    try {
      final rows = await repo.listMessages(arg).timeout(
        const Duration(seconds: 5),
      );
      if (rows.isEmpty) {
        _seedGreeting();
        return;
      }
      final server = [
        for (final row in rows)
          ChatMessage(
            id: row.id,
            role: row.role == 'user' ? ChatRole.user : ChatRole.assistant,
            text: row.content,
            planName: row.planName,
            planSummary: row.planSummary,
            at: row.createdAt,
          ),
      ];
      // Merge, don't clobber: turns sent while this fetch was in flight (and
      // the reply streaming onto them) stay in place. The old overwrite wiped
      // them, they vanished from the thread, then "reordered" back into view
      // once their own insert landed and a later bootstrap restored them.
      final serverIds = {for (final m in server) m.id};
      final local = [
        for (final m in state)
          if (!serverIds.contains(m.id) && !m.id.startsWith(_welcomePrefix)) m,
      ];
      state = [...server, ...local];
    } catch (_) {
      _seedGreeting();
    }
  }

  void _seedGreeting() {
    if (state.isNotEmpty) return;
    add(
      ChatMessage(
        id: '$_welcomePrefix$arg',
        role: ChatRole.assistant,
        text: MockChatService.greeting,
        at: DateTime.now(),
      ),
    );
  }

  void add(ChatMessage message) {
    state = [...state, message];
    // Persist user turns immediately; assistant turns are persisted once at
    // completion (finishStreaming), so streaming churn never hits the DB.
    // The greeting is a fixed intro never worth storing.
    final isUser = message.role == ChatRole.user;
    final isGreeting = message.id.startsWith(_welcomePrefix);
    final store = ref.read(chatRepositoryProvider);
    if (isUser && !isGreeting && store != null) {
      unawaited(
        (() async {
          try {
            await store.insertMessage(
              id: message.id,
              chatId: arg,
              role: 'user',
              content: message.text,
            );
          } catch (_) {
            // Degrade: in-memory only.
          }
        })(),
      );
    }
  }

  void setText(String messageId, String text) =>
      substitute(messageId, (m) => m..text = text);

  void attachPlan(
    String messageId, {
    required String appName,
    required String summary,
  }) => substitute(
    messageId,
    (m) => m
      ..planName = appName
      ..planSummary = summary,
  );

  void finishStreaming(String messageId) {
    final persisted = substitute(
      messageId,
      (m) => m..isStreaming = false,
    );
    ChatMessage? done;
    for (final m in persisted) {
      if (m.id == messageId) {
        done = m;
        break;
      }
    }
    final store = ref.read(chatRepositoryProvider);
    if (done == null || store == null) return;
    final finalReply = done; // final local -> promoted to non-null for closure
    if (finalReply.id.startsWith(_welcomePrefix)) return;
    if (finalReply.text.isEmpty) return;
    unawaited(
      (() async {
        try {
          await store.insertMessage(
            id: finalReply.id,
            chatId: arg,
            role: 'assistant',
            content: finalReply.text,
            planName: finalReply.planName,
            planSummary: finalReply.planSummary,
          );
        } catch (_) {
          // Degrade — but one quiet retry first: a flaky moment shouldn't
          // cost the whole reply on the next app start.
          await Future<void>.delayed(const Duration(seconds: 4));
          try {
            await store.insertMessage(
              id: finalReply.id,
              chatId: arg,
              role: 'assistant',
              content: finalReply.text,
              planName: finalReply.planName,
              planSummary: finalReply.planSummary,
            );
          } catch (_) {
            // Still unreachable: reply stays in memory only.
          }
        }
      })(),
    );
  }

  void markActionUsed(String messageId) =>
      substitute(messageId, (m) => m..actionUsed = true);

  List<ChatMessage> substitute(
    String messageId,
    ChatMessage Function(ChatMessage) change,
  ) {
    final result = [
      for (final m in state)
        if (m.id == messageId) change(m) else m,
    ];
    state = result;
    return result;
  }
}

final messagesProvider =
    NotifierProvider.family<MessagesState, List<ChatMessage>, String>(
      MessagesState.new,
    );

String _titleFrom(String message) {
  final trimmed = message.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return 'New chat';
  if (trimmed.length <= 42) return trimmed;
  return '${trimmed.substring(0, 42)}…';
}
