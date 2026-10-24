import 'supabase_config.dart';

/// Thin, best-effort Supabase-backed chat store.
///
/// Every call degrades on failure: [ChatStoreOffline] is thrown and providers
/// fall back to in-memory behavior instead of breaking the UI. This keeps the
/// white-screen failure philosophy from Phase 1 ("never brick the app").
class ChatStoreOffline implements Exception {}

class ChatRepository {
  const ChatRepository();

  Future<void> insertChat({
    required String id,
    required String userId,
    required String title,
  }) async {
    try {
      await SupabaseConfig.client.from('chats').insert({
        'id': id,
        'user_id': userId,
        'title': title,
      });
    } catch (_) {
      throw ChatStoreOffline();
    }
  }

  Future<void> renameChat({
    required String id,
    String? title,
    DateTime? updatedAt,
  }) => _touch(id, title: title, updatedAt: updatedAt);

  Future<void> touchChat({required String id, DateTime? updatedAt}) =>
      _touch(id, updatedAt: updatedAt);

  Future<void> _touch(String id, {String? title, DateTime? updatedAt}) async {
    try {
      final patch = <String, Object?>{
        'title': ?title,
        'updated_at': ?updatedAt?.toIso8601String(),
      };
      if (patch.isEmpty) return;
      await SupabaseConfig.client.from('chats').update(patch).eq('id', id);
    } catch (_) {
      throw ChatStoreOffline();
    }
  }

  Future<void> insertMessage({
    required String id,
    required String chatId,
    required String role,
    required String content,
  }) async {
    try {
      await SupabaseConfig.client.from('messages').insert({
        'id': id,
        'chat_id': chatId,
        'role': role,
        'content': content,
      });
    } catch (_) {
      throw ChatStoreOffline();
    }
  }

  /// Chats newest-first, as the list screen renders them.
  Future<List<ChatRow>> listChats(String userId) async {
    try {
      final rows = await SupabaseConfig.client
          .from('chats')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return [
        for (final r in rows as List)
          ChatRow(
            id: r['id'] as String,
            title: r['title'] as String,
            createdAt: DateTime.parse(r['created_at'] as String),
            updatedAt: DateTime.parse(r['updated_at'] as String),
          ),
      ];
    } catch (_) {
      throw ChatStoreOffline();
    }
  }

  /// Messages oldest-first, as the conversation renders them.
  Future<List<MessageRow>> listMessages(String chatId) async {
    try {
      final rows = await SupabaseConfig.client
          .from('messages')
          .select()
          .eq('chat_id', chatId)
          .order('created_at', ascending: true);
      return [
        for (final r in rows as List)
          MessageRow(
            id: r['id'] as String,
            role: r['role'] as String,
            content: r['content'] as String,
            createdAt: DateTime.parse(r['created_at'] as String),
          ),
      ];
    } catch (_) {
      throw ChatStoreOffline();
    }
  }
}

class ChatRow {
  const ChatRow({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MessageRow {
  const MessageRow({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
}
