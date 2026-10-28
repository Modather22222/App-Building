import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/supabase_config.dart';
import 'projects_providers.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Apps')),
      floatingActionButton: projects.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                HapticFeedback.lightImpact();
                context.go('/chats');
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('New app'),
            ),
      body: projects.isEmpty
          ? const _EmptyProjects()
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
                  itemCount: projects.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _ProjectRow(project: projects[index]),
                );
              },
            ),
    );
  }
}

class _ProjectRow extends ConsumerWidget {
  const _ProjectRow({required this.project});

  final AppProject project;

  void _openActions(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    final projects = ref.read(projectsProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded),
              title: const Text('View build details'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/project/${project.id}');
              },
            ),
            // Simulation is available only in backend-less mode — with real
            // builds the failure path belongs to the factory, not the UI.
            if (project.isActive && !SupabaseConfig.enabled)
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Simulate build failure (dev)'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  projects.fail(project.id);
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(content: Text('Build failed (simulated)')),
                  );
                },
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                'Delete app',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                projects.remove(project.id);
                ScaffoldMessenger.of(sheetContext)
                    .showSnackBar(const SnackBar(content: Text('App deleted')));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        onTap: () => context.push('/project/${project.id}'),
        onLongPress: () => _openActions(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.smartphone_rounded,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: AppTokens.gapMd),
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                  ),
                  const SizedBox(width: AppTokens.gapMd),
                  _StatusChip(project: project),
                ],
              ),
              const SizedBox(height: AppTokens.gapMd),
              Text(
                project.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (project.isActive) ...[
                const SizedBox(height: AppTokens.gapMd),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: colors.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.project});

  final AppProject project;

  @override
  Widget build(BuildContext context) {
    final statusColor = project.failed
        ? AppTokens.failedColor(context)
        : AppTokens.stageColor(context, project.stage);
    final label = project.failed ? 'Failed' : project.stage.short;

    // Screen readers get one clean announcement instead of dot + text noise.
    return Semantics(
      label: 'Build status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ghost preview of a filled project card.
            Container(
              height: 96,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 96,
              width: double.infinity,
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.55,
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.sectionGap),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceContainerHighest,
                ),
                child: Icon(
                  Icons.smartphone_outlined,
                  color: colors.primary,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.gapLg),
            Text(
              'No apps built yet',
              textAlign: TextAlign.center,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.gapSm),
            Text(
              'Chat with the agent and hit "Build this app" to queue your '
              'first APK build.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppTokens.sectionGap),
            FilledButton.icon(
              onPressed: () => context.go('/chats'),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Open the agent'),
            ),
          ],
        ),
      ),
    );
  }
}
