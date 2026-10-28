import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/ids.dart';
import '../../data/chat_repository.dart';
import '../../data/mock/mock_chat_service.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
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
  String? _bootstrappedFor;
  bool _disposed = false;

  @override
  List<ChatThread> build() {
    // Phase 7 — re-key on auth changes (AuthSession == by user id, so token
    // refreshes don't rebuild): sign-out clears the list, sign-in loads the
    // new account's threads. No cross-account leakage.
    final userId = ref.watch(authProvider)?.id;
    ref.onDispose(() => _disposed = true);
    if (_bootstrappedFor != userId) {
      _bootstrappedFor = userId;
      if (userId != null) unawaited(_loadFromStore(userId));
    }
    return const [];
  }

  Future<void> _loadFromStore(String userId) async {
    final repo = ref.read(chatRepositoryProvider);
    if (repo == null) return;
    try {
      final rows = await repo.listChats(userId).timeout(
        const Duration(seconds: 5),
      );
      if (_disposed) return; // Phase 7 — disposed mid-fetch
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

/// Phase 7 — a message row waiting in the persistence outbox.
typedef _PendingInsert = ({
  String id,
  String role,
  String content,
  String? planName,
  String? planSummary,
});

class MessagesState extends FamilyNotifier<List<ChatMessage>, String> {
  bool _bootstrapped = false;
  String? _bootstrappedForSession;
  Future<void>? _bootstrapInFlight;
  static const _welcomePrefix = 'welcome-';

  // Phase 7 — persistence outbox: failed message inserts retry on a short
  // timer instead of being lost forever. In-memory only (a restart loses the
  // outbox, same as before, but a transient outage no longer eats turns).
  final List<_PendingInsert> _outbox = <_PendingInsert>[];
  Timer? _outboxTimer;
  bool _flushing = false;
  bool _disposed = false;

  @override
  List<ChatMessage> build(String arg) {
    // Phase 7 — re-key on auth changes (AuthSession == by user id, so token
    // refreshes don't rebuild); a new account resets the outbox so the
    // previous account's queue is never flushed into its context.
    final sessionId = ref.watch(authProvider)?.id;
    if (_bootstrappedForSession != sessionId) {
      _bootstrappedForSession = sessionId;
      _bootstrapped = false;
      _outbox.clear();
      _outboxTimer?.cancel();
      _outboxTimer = null;
    }
    ref.onDispose(() => _disposed = true);
    if (!_bootstrapped) {
      _bootstrapped = true;
      // Defer past build(): bootstrap's synchronous path (mock mode seeds
      // the greeting with no await in between) touches state, which is
      // illegal while the provider is still building. Real-mode runs
      // suspend at the fetch await first, so only mock mode ever hit this.
      Future<void>.microtask(() => bootstrap());
    }
    return const [];
  }

  /// Pulls persisted messages for this thread. When the thread is brand new
  /// (or the store is offline) the agent greeting is seeded locally — it is
  /// intentionally never persisted.
  Future<void> bootstrap() {
    // Phase 7 — idempotent: the screen's initState AND the build hook both
    // call this on first open; one fetch, one merge (the old double fetch
    // let two merges interleave last-writer-wins).
    return _bootstrapInFlight ??= _doBootstrap();
  }

  Future<void> _doBootstrap() async {
    final repo = ref.read(chatRepositoryProvider);
    if (repo == null) {
      _seedGreeting();
      return;
    }
    try {
      final rows = await repo.listMessages(arg).timeout(
        const Duration(seconds: 5),
      );
      if (_disposed) return; // Phase 7 — disposed mid-fetch
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
      if (_disposed) return; // Phase 7 — disposed mid-merge
      final serverIds = {for (final m in server) m.id};
      final local = [
        for (final m in state)
          if (!serverIds.contains(m.id) && !m.id.startsWith(_welcomePrefix)) m,
      ];
      state = [...server, ...local];
    } catch (_) {
      // Phase 7 — a store outage must not look like data loss: keep whatever
      // is on screen (local turns, a previous greeting) instead of reseeding
      // the greeting over real history.
      if (!_disposed && state.isEmpty) _seedGreeting();
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

  void _enqueue(_PendingInsert row) {
    _outbox.add(row);
    _outboxTimer ??= Timer.periodic(const Duration(seconds: 6), (_) => _flushOutbox());
  }

  Future<void> _flushOutbox() async {
    if (_flushing || _outbox.isEmpty) return;
    final store = ref.read(chatRepositoryProvider);
    if (store == null || _disposed) return;
    _flushing = true;
    try {
      while (_outbox.isNotEmpty && !_disposed) {
        final row = _outbox.first;
        try {
          await store.insertMessage(
            id: row.id,
            chatId: arg,
            role: row.role,
            content: row.content,
            planName: row.planName,
            planSummary: row.planSummary,
          );
          _outbox.removeAt(0);
        } catch (_) {
          break; // still unreachable — retry on the next tick
        }
      }
    } finally {
      _flushing = false;
      if (_outbox.isEmpty) {
        _outboxTimer?.cancel();
        _outboxTimer = null;
      }
    }
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
            // Phase 7 — queue for retry instead of losing the turn.
            _enqueue((
              id: message.id,
              role: 'user',
              content: message.text,
              planName: null,
              planSummary: null,
            ));
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
        final row = (
          id: finalReply.id,
          role: 'assistant',
          content: finalReply.text,
          planName: finalReply.planName,
          planSummary: finalReply.planSummary,
        );
        try {
          await store.insertMessage(
            id: row.id,
            chatId: arg,
            role: row.role,
            content: row.content,
            planName: row.planName,
            planSummary: row.planSummary,
          );
        } catch (_) {
          // Phase 7 — the outbox retries instead of losing the reply.
          _enqueue(row);
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
