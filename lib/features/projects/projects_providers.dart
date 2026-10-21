import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';

/// Simulated pipeline timer progress. Timers advance the stage; a run token
/// guards against stale timers after fail/retry/remove operations.
class ProjectsState extends Notifier<List<AppProject>> {
  final Map<String, int> _runs = <String, int>{};
  int _seq = 0;

  static const List<Duration> _stageDurations = [
    Duration(seconds: 6), // generating
    Duration(seconds: 4), // pushing
    Duration(seconds: 5), // queued
    Duration(seconds: 7), // building -> ready
  ];

  @override
  List<AppProject> build() => const [];

  String create({required String name, required String summary}) {
    final id =
        'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${(_seq++).toRadixString(36)}';
    final now = DateTime.now();
    final project = AppProject(
      id: id,
      name: name,
      summary: summary,
      createdAt: now,
    )..stageStarted[BuildStage.generating] = now;
    state = [project, ...state];
    _scheduleNext(id, 0);
    return id;
  }

  void fail(String id) {
    _runs[id] = (_runs[id] ?? 0) + 1; // cancel pending timers
    final current = _byId(id);
    if (current == null || !current.isActive) return;
    final updated = current.copyWith(failed: true)
      ..stageFinished[current.stage] = DateTime.now();
    state = [for (final p in state) p.id == id ? updated : p];
    HapticFeedback.mediumImpact();
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
    _scheduleNext(id, 0);
  }

  void remove(String id) {
    _runs[id] = (_runs[id] ?? 0) + 1; // cancel pending timers
    state = [...state]..removeWhere((p) => p.id == id);
  }

  AppProject? _byId(String id) {
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }

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
