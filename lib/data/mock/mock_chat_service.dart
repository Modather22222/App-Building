/// Chunks emitted by the agent while composing a reply.
///
/// [TextChunk] carries the cumulative message text so the UI can simply
/// replace the bubble content; [PlanChunk] attaches the build action the
/// user can confirm to spawn a project.
sealed class ReplyChunk {
  const ReplyChunk();
}

class TextChunk extends ReplyChunk {
  const TextChunk(this.text);
  final String text;
}

class PlanChunk extends ReplyChunk {
  const PlanChunk({required this.appName, required this.summary});
  final String appName;
  final String summary;
}

/// Mock agent stream. Replaced by the real OpenCode pipeline in Phase 3 —
/// the UI only depends on [ReplyChunk], not on this implementation.
class MockChatService {
  MockChatService._();

  static const String greeting =
      "Hey! I'm your app factory agent. Describe a Flutter app and I'll scope "
      'it with you, generate the full project, push it to GitHub and build an '
      'APK you can install. What should we build today?';

  static Stream<ReplyChunk> reply(String userText) async* {
    if (_looksLikeAppIdea(userText)) {
      yield* _appPlan(userText);
    } else {
      yield* _guidance(userText);
    }
  }

  static bool _looksLikeAppIdea(String text) {
    final t = text.toLowerCase();
    return (t.contains('app') ||
            t.contains('build') ||
            t.contains('mvp') ||
            t.contains('flutter') ||
            t.contains('tracker') ||
            t.contains('clone')) &&
        text.trim().split(RegExp(r'\s+')).length >= 2;
  }

  static Stream<ReplyChunk> _appPlan(String idea) async* {
    yield* _streamText(
      'Love it — that works as an MVP. Here is the flow I would lock in:\n\n'
      '\u2022 3 core screens, one primary job per screen\n'
      '\u2022 Local-first data, cloud hooks ready for later\n'
      '\u2022 Clean state management, zero clutter in the first cut\n\n'
      'Confirm and I will generate the complete Flutter project, push it to '
      'GitHub and queue an APK build for you.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final summary = idea.trim().replaceAll(RegExp(r'\s+'), ' ');
    yield PlanChunk(
      appName: _deriveName(summary),
      summary: summary.length > 140 ? summary.substring(0, 140) : summary,
    );
  }

  static Stream<ReplyChunk> _guidance(String userText) async* {
    final t = userText.toLowerCase();
    if (t.contains('hi') || t.contains('hello') || t.contains('hey')) {
      yield* _streamText(
        'Hey! Tell me what the app is for and I will take it from idea to an '
        'installable APK.',
      );
      return;
    }
    yield* _streamText(
      'Before we lock a plan, I need three things:\n\n'
      '1. Who it is for — and the one job it must nail\n'
      '2. The 3\u20135 must-have screens, in flow order\n'
      '3. Whether you need accounts from day one\n\n'
      'Rough is fine. Once I know the flow, I will draft the build plan and '
      'start the factory.',
    );
  }

  static Stream<ReplyChunk> _streamText(String full) async* {
    final parts = full.split(' ');
    final buffer = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      buffer
        ..write(parts[i])
        ..write(' ');
      yield TextChunk(buffer.toString());
      await Future<void>.delayed(Duration(milliseconds: i % 9 == 8 ? 90 : 34));
    }
  }

  static String _deriveName(String idea) {
    const stop = {
      'a',
      'an',
      'the',
      'for',
      'my',
      'me',
      'app',
      'flutter',
      'build',
      'that',
      'with',
      'and',
      'to',
      'of',
      'want',
      'make',
      'this',
    };
    final words = idea
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 2 && !stop.contains(w))
        .take(2)
        .toList();
    if (words.isEmpty) return 'New Flutter App';
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }
}
