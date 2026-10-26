import 'package:supabase_flutter/supabase_flutter.dart';

import '../mock/mock_chat_service.dart';
import '../supabase_config.dart';

/// One prior turn of the conversation, oldest → newest, INCLUDING the message
/// that was just sent.
class AgentTurn {
  const AgentTurn(this.role, this.content);

  final String role; // 'user' | 'assistant'
  final String content;
}

class AgentChatException implements Exception {
  const AgentChatException(this.message);

  final String message;
}

/// Real planning agent. Calls the `agent-chat` edge function with the visible
/// history and replays the result through the same [ReplyChunk] contract the
/// chat UI already consumes — TextChunk for the reply, PlanChunk when the
/// agent proposes a build plan.
///
/// Throws [AgentChatException] on failure so the screen can show the exact
/// server message (missing key, rate limit, model error...).
class AgentChatService {
  const AgentChatService._();

  static Stream<ReplyChunk> reply({required List<AgentTurn> history}) async* {
    final FunctionResponse res;
    try {
      res = await SupabaseConfig.client.functions
          .invoke(
            'agent-chat',
            body: {
              'history': [
                for (final t in history)
                  {'role': t.role, 'content': t.content},
              ],
            },
          )
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw const AgentChatException(
        'Could not reach the agent. Check the connection and try again.',
      );
    }

    if (res.status != 200) {
      final data = res.data;
      final message = data is Map && data['error'] is String
          ? data['error'] as String
          : 'Agent service error (${res.status}).';
      throw AgentChatException(message);
    }

    final data = res.data;
    if (data is! Map) {
      throw const AgentChatException('Agent returned an unexpected payload.');
    }
    yield TextChunk((data['reply'] as String?) ?? '');
    final plan = data['plan'];
    if (plan is Map) {
      yield PlanChunk(
        appName: ((plan['app_name'] as String?) ?? 'App').trim(),
        summary: ((plan['summary'] as String?) ?? '').trim(),
      );
    }
  }
}
