import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/ids.dart';
import '../../data/mock/mock_chat_service.dart';
import '../../data/models.dart';
import '../projects/projects_providers.dart';
import 'chats_providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.threadId});

  final String threadId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  StreamSubscription<ReplyChunk>? _sub;
  String? _streamingReplyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Messages load persisted turns; a brand-new (or offline) thread gets
      // the agent greeting seeded locally — never persisted.
      unawaited(
        ref
            .read(messagesProvider(widget.threadId).notifier)
            .bootstrap(),
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  MessagesState get _messages =>
      ref.read(messagesProvider(widget.threadId).notifier);

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {});

    ref
        .read(chatsProvider.notifier)
        .renameFromFirstMessage(widget.threadId, text);
    ref.read(chatsProvider.notifier).touch(widget.threadId);

    _messages.add(
      ChatMessage(
        id: newId('u'),
        role: ChatRole.user,
        text: text,
        at: DateTime.now(),
      ),
    );
    HapticFeedback.selectionClick();

    // Finish a previous in-flight reply so bubbles never keep blinking.
    if (_streamingReplyId != null) {
      _messages.finishStreaming(_streamingReplyId!);
      _sub?.cancel();
    }

    final replyId = newId('a');
    _streamingReplyId = replyId;
    _messages.add(
      ChatMessage(
        id: replyId,
        role: ChatRole.assistant,
        text: '',
        at: DateTime.now(),
        isStreaming: true,
      ),
    );

    _sub = MockChatService.reply(text).listen(
      (chunk) {
        switch (chunk) {
          case TextChunk(:final text):
            _messages.setText(replyId, text);
          case PlanChunk(:final appName, :final summary):
            _messages.attachPlan(replyId, appName: appName, summary: summary);
        }
      },
      onDone: () {
        _messages.finishStreaming(replyId);
        _streamingReplyId = null;
      },
      onError: (Object error) {
        _messages.setText(
          replyId,
          'Something went wrong on my side. Try again in a moment.',
        );
        _messages.finishStreaming(replyId);
        _streamingReplyId = null;
      },
    );
  }

  void _startBuild(ChatMessage message) {
    if (message.planName == null || message.actionUsed) return;
    HapticFeedback.mediumImpact();
    // The build prompt is the user request that produced this plan — find the
    // nearest preceding user turn so the factory generates what was asked.
    String prompt = '';
    for (final m in ref.read(messagesProvider(widget.threadId)).reversed) {
      if (m.role == ChatRole.user) {
        prompt = m.text;
        break;
      }
    }
    final projectId = ref
        .read(projectsProvider.notifier)
        .create(
          name: message.planName!,
          summary: message.planSummary ?? '',
          prompt: prompt,
        );
    _messages.markActionUsed(message.id);
    context.push('/project/$projectId');
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.threadId));
    ChatThread? thread;
    for (final t in ref.watch(chatsProvider)) {
      if (t.id == widget.threadId) {
        thread = t;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(thread?.title ?? 'New chat')),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _SuggestionPane(
                    onPick: (prompt) {
                      _controller.text = prompt;
                      _send();
                    },
                  )
                : _MessageList(messages: messages, onStartBuild: _startBuild),
          ),
          _Composer(
            controller: _controller,
            focusNode: _focusNode,
            onSend: () => _send(),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.messages, required this.onStartBuild});

  final List<ChatMessage> messages;
  final void Function(ChatMessage) onStartBuild;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.gutter,
        vertical: 16,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
        return _MessageBubble(
          message: message,
          onStartBuild: () => onStartBuild(message),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onStartBuild});

  final ChatMessage message;
  final VoidCallback onStartBuild;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;

    final isUser = message.role == ChatRole.user;
    final bubbleRadius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          );

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        color: isUser ? colors.primary : colors.surfaceContainerHighest,
        borderRadius: bubbleRadius,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.text.isEmpty && message.isStreaming)
            const _TypingDots()
          else
            SelectableText(
              message.text,
              style: text.bodyMedium?.copyWith(
                color: isUser ? colors.onPrimary : colors.onSurface,
              ),
            ),
          if (!isUser && message.planName != null && !message.actionUsed) ...[
            const SizedBox(height: AppTokens.gapMd),
            FilledButton.icon(
              onPressed: onStartBuild,
              icon: const Icon(Icons.build_circle_rounded, size: 20),
              label: const Text('Build this app'),
            ),
          ],
        ],
      ),
    );

    final row = isUser
        ? Align(alignment: Alignment.centerRight, child: bubble)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primaryContainer.withValues(alpha: 0.55),
                ),
                child: Icon(
                  Icons.smart_toy_outlined,
                  size: 16,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: AppTokens.gapSm),
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: bubble),
              ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: message.text));
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
        },
        child: row,
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  const _SendButton({required this.enabled, required this.onSend});

  final bool enabled;
  final VoidCallback onSend;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        setState(() => _pressed = true);
        if (widget.enabled) HapticFeedback.selectionClick();
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed && widget.enabled ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 48,
          height: 48,
          child: IconButton.filled(
            onPressed: widget.enabled ? widget.onSend : null,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacityFor(int i, double phase) {
    final t = (phase - i * 0.22) % 1.0;
    return 0.35 + 0.65 * (0.5 + 0.5 * _sin(t * 2 * _pi2));
  }

  static const double _pi2 = 3.1415926535897932 * 2;
  static double _sin(double x) => math.sin(x);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Opacity(
                opacity: _opacityFor(i, phase),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _SuggestionPane extends StatelessWidget {
  const _SuggestionPane({required this.onPick});

  final void Function(String) onPick;

  static const _prompts = [
    'Habit tracker MVP',
    'Expense tracker app',
    'Workout log app',
    'Local notes app',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primaryContainer.withValues(alpha: 0.55),
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 30,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: AppTokens.gapLg),
            Text('Start with a prompt', style: text.titleMedium),
            const SizedBox(height: AppTokens.gapSm),
            Text(
              'Or write your own — a rough idea is enough.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppTokens.gapLg),
            Wrap(
              spacing: AppTokens.gapSm,
              runSpacing: AppTokens.gapSm,
              alignment: WrapAlignment.center,
              children: [
                for (final prompt in _prompts)
                  ActionChip(
                    label: Text(prompt),
                    onPressed: () => onPick(prompt),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canSend = widget.controller.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.gapMd,
            10,
            AppTokens.gapMd,
            10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: const InputDecoration(
                    hintText: 'Describe the app to build\u2026',
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.gapSm),
              _SendButton(enabled: canSend, onSend: widget.onSend),
            ],
          ),
        ),
      ),
    );
  }
}
