import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../supabase_config.dart';
import '../mock/mock_chat_service.dart';

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
/// Uses a raw HttpClient instead of functions.invoke because the official
/// client THROWS on non-200 responses, which flattens every server message
/// (quota limits, configuration errors) into a generic network failure.
/// Here every status/body is parsed and surfaced verbatim.
class AgentChatService {
  const AgentChatService._();

  static Future<Map<String, dynamic>> _invoke(
    Map<String, dynamic> body,
  ) async {
    final session = SupabaseConfig.client.auth.currentSession;
    final token = session?.accessToken ?? '';
    if (token.isEmpty) {
      throw const AgentChatException('Your session expired — sign in again.');
    }

    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('${SupabaseConfig.url}/functions/v1/agent-chat'))
          .timeout(const Duration(seconds: 15));
      request.headers.set('apikey', SupabaseConfig.publishableKey);
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.set('content-type', 'application/json');
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode(text);
        payload =
            decoded is Map<String, dynamic>
                ? decoded
                : <String, dynamic>{};
      } catch (_) {
        payload = <String, dynamic>{};
      }

      if (response.statusCode != 200) {
        final message =
            payload['error'] is String
                ? payload['error'] as String
                : 'Agent service error (${response.statusCode}).';
        throw AgentChatException(message);
      }
      return payload;
    } on TimeoutException {
      throw const AgentChatException(
        'The agent took too long to reply — try again in a moment.',
      );
    } on SocketException {
      throw const AgentChatException(
        'Could not reach the agent. Check the connection and try again.',
      );
    } finally {
      client.close();
    }
  }

  static Stream<ReplyChunk> reply({required List<AgentTurn> history}) async* {
    final data = await _invoke({
      'history': [
        for (final t in history) {'role': t.role, 'content': t.content},
      ],
    });

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
