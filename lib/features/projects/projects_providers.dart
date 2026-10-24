import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/project_repository.dart';
import '../../data/supabase_config.dart';

final projectRepositoryProvider = Provider<ProjectRepository?>((ref) {
  if (!SupabaseConfig.enabled) return null;
  return const ProjectRepository();
});

String? _currentUserId() {
  if (!SupabaseConfig.enabled) return null;
  return SupabaseConfig.client.auth.currentUser?.id;
}

/// Real pipeline when the backend is configured: project rows live in
/// Supabase, the factory worker drives their status, and a 12 s poll merges
/// the server state in. Retries re-dispatch the worker via the request-build
/// edge function.
///
/// Backend-less mode keeps the Phase-1 timer simulation so the unlock flow
/// still demos end-to-end without any server.
class ProjectsState extends Notifier<List<AppProject>> {
  final Map<String, int> _runs = <String, int>{};
  int _seq = 0;
  bool _bootstrapped = false;
  Timer? _poll;

  static const List<Duration> _stageDurations = [
    Duration(seconds: 6), // generating
    Duration(seconds: 4), // pushing
    Duration(seconds: 5), // queued
    Duration(seconds: 7), // building -> ready
  ];

  @override
  List<AppProject> build() {
    ref.onDispose(() => _poll?.cancel());
    if (!_bootstrapped) {
      _bootstrapped = true;
      unawaited(_loadFromStore());
      _startPolling();
    }
    return const [];
  }

  // --- real pipeline -----------------------------------------------------

  bool get _isReal => ref.read(projectRepositoryProvider) != null;

  void _startPolling() {
    if (!_isReal) return;
    _poll = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_loadFromStore(keepLocalExtras: true));
    });
  }

  Future<void> _loadFromStore({bool keepLocalExtras = false}) async {
    final repo = ref.read(projectRepositoryProvider);
    final uid = _currentUserId();
    if (repo == null || uid == null) return;
    try {
      final rows = await repo.listProjects(uid).timeout(
        const Duration(seconds: 6),
      );
      final fresh = [for (final row in rows) _fromRow(row)];
      if (!keepLocalExtras) {
        state = fresh;
      } else {
        final serverIds = {for (final p in fresh) p.id};
        final extras = [
          for (final p in state)
            if (!serverIds.contains(p.id)) p,
        ];
        state = [...extras, ...fresh];
      }
    } catch (_) {
      // Offline or store unavailable — keep the current in-memory list.
    }
  }

  AppProject _fromRow(ProjectRow row) {
    final started = <BuildStage, DateTime>{};
    final finished = <BuildStage, DateTime>{};
    var lastStarted = 0;
    for (final s in BuildStage.values) {
      final startTs = row.stageTimes[s.name];
      if (startTs is String) {
        started[s] = DateTime.parse(startTs);
        lastStarted = s.index;
      }
      final doneTs = row.stageTimes['${s.name}_done'];
      if (doneTs is String) {
        finished[s] = DateTime.parse(doneTs);
        started[s] ??= finished[s]!;
      }
    }

    final stage = switch (row.status) {
      'ready' => BuildStage.ready,
      'failed' => BuildStage.values[lastStarted],
      'queued' => BuildStage.queued,
      'building' => BuildStage.building,
      'pushing' => BuildStage.pushing,
      _ => BuildStage.generating,
    };

    return AppProject(
      id: row.id,
      name: row.name,
      summary: row.summary,
      prompt: row.prompt,
      repo: row.repo,
      apkUrl: row.apkUrl,
      error: row.error,
      createdAt: row.createdAt,
      stage: stage,
      failed: row.status == 'failed',
      stageStarted: started,
      stageFinished: finished,
    );
  }

  /// Asks the request-build edge function to dispatch the factory worker.
  /// Failures surface as the project's error text; the user can retry.
  Future<void> _requestBuild(String id) async {
    if (!SupabaseConfig.enabled) return;
    if (ref.read(projectRepositoryProvider) == null) return;
    try {
      final res = await SupabaseConfig.client.functions.invoke(
        'request-build',
        body: {'project_id': id},
      );
      final status = res.status;
      if (status >= 400) {
        final data = res.data;
        final message =
            (data is Map && data['error'] is String)
                ? data['error'] as String
                : 'Build factory returned status $status.';
        _applyError(id, message);
      }
    } catch (_) {
      _applyError(id, 'Could not reach the build factory — retry shortly.');
    }
  }

  void _applyError(String id, String message) {
    if (!_isReal) return;
    state = [
      for (final p in state) p.id == id ? p.copyWith(error: message) : p,
    ];
  }

  // --- shared entry points -------------------------------------------------

  String create({
    required String name,
    required String summary,
    String prompt = '',
  }) {
    final id = 'proj-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '-${(_seq++).toRadixString(36)}';
    final now = DateTime.now();
    final project = AppProject(
      id: id,
      name: name,
      summary: summary,
      prompt: prompt,
      createdAt: now,
    )..stageStarted[BuildStage.generating] = now;
    state = [project, ...state];

    final repo = ref.read(projectRepositoryProvider);
    final uid = _currentUserId();
    if (repo != null && uid != null) {
      unawaited(() async {
        try {
          await repo.insertProject(
            id: id,
            userId: uid,
            name: name,
            prompt: prompt,
            summary: summary,
            createdAt: now,
          );
        } catch (_) {
          // Degrade: project only exists in memory this session.
        }
      }());
      unawaited(_requestBuild(id));
    } else {
      _scheduleNext(id, 0);
    }
    return id;
  }

  void retry(String id) {
    final current = _byId(id);
    if (current == null || !current.failed) return;
    final now = DateTime.now();
    state = [
      for (final p in state)
        p.id == id
            ? p.copyWith(
                stage: BuildStage.generating,
                failed: false,
                stageStarted: {BuildStage.generating: now},
                stageFinished: {},
              )
            : p,
    ];
    final repo = ref.read(projectRepositoryProvider);
    if (repo != null) {
      unawaited(() async {
        try {
          await repo.resetForRetry(id: id, at: now);
        } catch (_) {
          // Degrade: row stays as-is server-side.
        }
      }());
      unawaited(_requestBuild(id));
    } else {
      _scheduleNext(id, 0);
    }
  }

  void fail(String id) {
    _runs[id] = (_runs[id] ?? 0) + 1; // cancel pending timers
    final current = _byId(id);
    if (current == null || !current.isActive) return;
    final updated =
        current.copyWith(failed: true)
          ..stageFinished[current.stage] = DateTime.now();
    state = [for (final p in state) p.id == id ? updated : p];
    HapticFeedback.mediumImpact();
  }

  void remove(String id) {
    _runs[id] = (_runs[id] ?? 0) + 1; // cancel pending timers
    state = [...state]..removeWhere((p) => p.id == id);
    final repo = ref.read(projectRepositoryProvider);
    if (repo != null) {
      unawaited(
        (() async {
          try {
            await repo.delete(id);
          } catch (_) {
            // Degrade: deleted locally only.
          }
        })(),
      );
    }
  }

  AppProject? _byId(String id) {
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }

  // --- backend-less simulation (Phase 1 behavior) -------------------------

  void _scheduleNext(String id, int index) {
    final token = (_runs[id] ?? 0) + 1;
    _runs[id] = token;

    unawaited(
      Future<void>.delayed(_stageDurations[index], () {
        if (_runs[id] != token) return;
        final current = _byId(id);
        if (current == null || !current.isActive) return;

        final nextStage = BuildStage.values[current.stageIndex + 1];
        final now = DateTime.now();
        current
          ..stageFinished[current.stage] = now
          ..stage = nextStage;
        if (nextStage != BuildStage.ready) {
          current.stageStarted[nextStage] = now;
        }
        state = [for (final p in state) p.id == id ? current : p];

        if (nextStage != BuildStage.ready) {
          _scheduleNext(id, index + 1);
        } else {
          HapticFeedback.mediumImpact();
        }
      }),
    );
  }
}

final projectsProvider = NotifierProvider<ProjectsState, List<AppProject>>(
  ProjectsState.new,
);
