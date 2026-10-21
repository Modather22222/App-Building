import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/ids.dart';
import '../../data/models.dart';

class ChatsState extends Notifier<List<ChatThread>> {
  @override
  List<ChatThread> build() => const [];

  ChatThread create() {
    final now = DateTime.now();
    final thread = ChatThread(
      id: newId('chat'),
      title: 'New chat',
      createdAt: now,
      updatedAt: now,
    );
    state = [thread, ...state];
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
  }

  void touch(String id) {
    state = [
      for (final t in state)
        if (t.id == id) t..updatedAt = DateTime.now() else t,
    ];
  }
}

final chatsProvider = NotifierProvider<ChatsState, List<ChatThread>>(
  ChatsState.new,
);

class MessagesState extends FamilyNotifier<List<ChatMessage>, String> {
  @override
  List<ChatMessage> build(String arg) => const [];

  void add(ChatMessage message) => state = [...state, message];

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

  void finishStreaming(String messageId) =>
      substitute(messageId, (m) => m..isStreaming = false);

  void markActionUsed(String messageId) =>
      substitute(messageId, (m) => m..actionUsed = true);

  void substitute(String messageId, ChatMessage Function(ChatMessage) change) {
    state = [
      for (final m in state)
        if (m.id == messageId) change(m) else m,
    ];
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
  return '${trimmed.substring(0, 42)}\u2026';
}
