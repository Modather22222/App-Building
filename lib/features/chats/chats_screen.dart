import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models.dart';
import 'chats_providers.dart';

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      floatingActionButton: chats.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openNewChat(context, ref),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('New chat'),
            ),
      body: chats.isEmpty
          ? _EmptyChats(onStart: () => _openNewChat(context, ref))
          : Builder(
              builder: (context) {
                final safeBottom = MediaQuery.paddingOf(context).bottom;
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.gutter,
                    8,
                    AppTokens.gutter,
                    110 + safeBottom,
                  ),
                  itemCount: chats.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _ChatRow(thread: chats[index]),
                );
              },
            ),
    );
  }

  void _openNewChat(BuildContext context, WidgetRef ref) {
    HapticFeedback.lightImpact();
    final thread = ref.read(chatsProvider.notifier).create();
    context.push('/chat/${thread.id}');
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.thread});

  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        onTap: () => context.push('/chat/${thread.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.build_circle_outlined, color: colors.primary),
              ),
              const SizedBox(width: AppTokens.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chat with the build agent',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.gapMd),
              Text(
                timeAgo(thread.updatedAt),
                style: text.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ghost preview — teaches the structure without fake data.
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GhostBar(
                height: 64,
                color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 96, bottom: 32),
              child: _GhostBar(
                height: 44,
                color: colors.primaryContainer.withValues(alpha: 0.5),
              ),
            ),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceContainerHighest,
                ),
                child: Icon(
                  Icons.smart_toy_outlined,
                  color: colors.primary,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.gapLg),
            Text(
              'Describe an app. Get an APK.',
              textAlign: TextAlign.center,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.gapSm),
            Text(
              'Tell the agent what to build. It scopes the flow with you, '
              'generates the project and ships an installable build back.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppTokens.sectionGap),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Start your first chat'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostBar extends StatelessWidget {
  const _GhostBar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      ),
    );
  }
}
