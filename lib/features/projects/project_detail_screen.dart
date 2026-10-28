import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models.dart';
import '../../data/supabase_config.dart';
import 'projects_providers.dart';

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = _projectOf(ref);
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Build details')),
        body: const Center(child: Text('This app no longer exists.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      bottomNavigationBar: _StickyBar(project: project),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppTokens.gutter,
          AppTokens.gapMd,
          AppTokens.gutter,
          AppTokens.sectionGap,
        ),
        children: [
          _Header(project: project),
          const SizedBox(height: AppTokens.gapLg),
          _BuildTimeline(project: project),
          const SizedBox(height: AppTokens.gapLg),
          _BuildInfo(project: project),
          if (project.failed && project.error != null) ...[
            const SizedBox(height: AppTokens.gapMd),
            _FailureCard(message: project.error!),
          ],
        ],
      ),
    );
  }

  AppProject? _projectOf(WidgetRef ref) {
    for (final p in ref.watch(projectsProvider)) {
      if (p.id == projectId) return p;
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.project});

  final AppProject project;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.smartphone_rounded, color: colors.primary),
        ),
        const SizedBox(width: AppTokens.gapMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project.name, style: text.titleLarge),
              const SizedBox(height: 2),
              Text(
                project.summary,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BuildTimeline extends StatelessWidget {
  const _BuildTimeline({required this.project});

  final AppProject project;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final stages = BuildStage.values;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BUILD PIPELINE',
              style: text.labelSmall?.copyWith(
                letterSpacing: 1.2,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.gapMd),
            for (var i = 0; i < stages.length; i++)
              _StageRow(
                stage: stages[i],
                isFirst: i == 0,
                isLast: i == stages.length - 1,
                project: project,
              ),
            const SizedBox(height: AppTokens.gapMd),
            Text(
              project.repo != null
                  ? 'Build runs on GitHub Actions in the shared '
                      'App Building build repo.'
                  : 'The build starts on GitHub Actions once the build '
                      'service dispatches it.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.isFirst,
    required this.isLast,
    required this.project,
  });

  final BuildStage stage;
  final bool isFirst;
  final bool isLast;
  final AppProject project;

  _StageState get state {
    if (project.failed && stage == project.stage) return _StageState.failed;
    final index = stage.index;
    if (index < project.stageIndex) return _StageState.done;
    if (index == project.stageIndex) return _StageState.active;
    return _StageState.pending;
  }

  String _caption(AppProject project) {
    switch (state) {
      case _StageState.done:
        final started = project.stageStarted[stage];
        final finished = project.stageFinished[stage];
        if (started == null || finished == null) return 'Done';
        return 'Done \u00b7 ${fmtDuration(finished.difference(started))}';
      case _StageState.active:
        if (project.failed) return 'Failed here \u2014 retry below.';
        if (stage == BuildStage.queued) {
          return "You're in the queue \u2014 typical wait is 10\u201315 min.";
        }
        if (stage == BuildStage.generating) {
          return 'Writing screens, models and state\u2026';
        }
        return 'Est. ${stage.eta}';
      case _StageState.pending:
        return 'Est. ${stage.eta}';
      case _StageState.failed:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = AppTokens.stageColor(context, stage);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              _StageDot(state: state, accent: accent),
              if (!isLast)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 2,
                      color: colors.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppTokens.gapMd),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.label,
                    style: text.titleSmall?.copyWith(
                      color: state == _StageState.pending
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
                  ),
                  if (_caption(project).isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _caption(project),
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StageState { pending, active, done, failed }

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded, color: AppTokens.failedColor(context)),
                const SizedBox(width: 10),
                Text(
                  'Build report',
                  style: text.titleSmall?.copyWith(
                    color: AppTokens.failedColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.gapSm),
            SelectableText(
              message,
              style: text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageDot extends StatelessWidget {
  const _StageDot({required this.state, required this.accent});

  final _StageState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return switch (state) {
      _StageState.done => Icon(
        Icons.check_circle_rounded,
        color: AppTokens.stageColor(context, BuildStage.ready),
        size: 24,
        semanticLabel: 'Completed',
      ),
      _StageState.failed => Icon(
        Icons.cancel_rounded,
        color: AppTokens.failedColor(context),
        size: 24,
        semanticLabel: 'Failed',
      ),
      _StageState.active => SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.6, color: accent),
      ),
      _StageState.pending => Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.outlineVariant, width: 2),
        ),
      ),
    };
  }
}

class _BuildInfo extends StatelessWidget {
  const _BuildInfo({required this.project});

  final AppProject project;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final info = project.buildInfo;
    final runNo = info?['run_number'];
    final sizeB = info?['size_bytes'];
    final buildText = (runNo != null && sizeB != null)
        ? '#$runNo \u00b7 ${((sizeB as num) / 1048576).toStringAsFixed(1)} MB'
        : null;

    final rows = <String, String>{
      'Repository': project.repo ?? 'assigned on build start',
      'Requested':
          '${shortDate(project.createdAt)} \u00b7 ${clockTime(project.createdAt)}',
      'Status': project.failed ? 'Failed' : project.stage.label,
      'Build': buildText ?? 'assigned on build completion',
      'Artifact': project.apkUrl != null ? 'app-release.apk' : 'pending',
    };

    return Card(
      child: Column(
        children: [
          for (final entry in rows.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.gapLg,
                vertical: 13,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (entry.key != rows.keys.last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _StickyBar extends ConsumerWidget {
  const _StickyBar({required this.project});

  final AppProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    final (label, onPressed) = switch (project) {
      _ when project.failed => (
        'Retry build',
        () => ref.read(projectsProvider.notifier).retry(project.id),
      ),
      _ when project.stage == BuildStage.ready => (
        'Download APK',
        () => _downloadApk(context, project),
      ),
      _ => ('${project.stage.short}\u2026', null as void Function()?),
    };

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppTokens.gutter,
          AppTokens.gapMd,
          AppTokens.gutter,
          AppTokens.gapMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (project.isActive) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: colors.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.gapMd),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton(onPressed: onPressed, child: Text(label)),
                ),
                if (project.stage == BuildStage.ready && !project.failed) ...[
                  const SizedBox(width: AppTokens.gapSm),
                  OutlinedButton(
                    onPressed: project.repo == null
                        ? null
                        : () => _openRepo(context, project),
                    child: const Text('Repo'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRepo(BuildContext context, AppProject project) async {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = Uri.https('github.com', '/${project.repo}');
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the repo link.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the repo link.')),
      );
    }
  }

  Future<void> _downloadApk(BuildContext context, AppProject project) async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    final apkUrl = project.apkUrl;
    if (apkUrl == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('The APK link is still syncing — retry in a moment.'),
        ),
      );
      return;
    }
    try {
      final launched = await launchUrl(
        Uri.parse(apkUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the download link.')),
        );
      } else {
        // Phase 5 — telemetry: the download tap is the funnel's last stage
        // (earlier stages are server-derived from existing rows). Silent
        // degrade: analytics must never disturb the action itself.
        if (SupabaseConfig.enabled) {
          try {
            await SupabaseConfig.client
                .from('funnel_events')
                .insert({'kind': 'download', 'project_id': project.id});
          } catch (_) {
            // Degrade: the event is lost, not the download.
          }
        }
      }
    } catch (error) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open the download link. Try again shortly.'),
        ),
      );
    }
  }
}
