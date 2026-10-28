import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Thin, best-effort Supabase-backed projects store.
///
/// Mirrors [ChatRepository]: every call degrades via [ProjectStoreOffline]
/// and providers keep working from memory (`never brick the app`).
/// The store call failed for a non-quota reason. Carries the server's own
/// error text when PostgREST supplied one — surfaced verbatim so failure
/// reasons are diagnosable from the screen the user is looking at.
class ProjectStoreOffline implements Exception {
  const ProjectStoreOffline([this.message]);
  final String? message;
}

/// The DB quota trigger (private.enforce_project_quota) refused the insert —
/// the message text travels through PostgREST and is shown verbatim in UI.
class ProjectLimitReached implements Exception {
  const ProjectLimitReached(this.message);

  final String message;
}

class ProjectRepository {
  const ProjectRepository();

  Future<void> insertProject({
    required String id,
    required String userId,
    required String name,
    required String prompt,
    required String summary,
    DateTime? createdAt,
  }) async {
    final at = (createdAt ?? DateTime.now()).toUtc().toIso8601String();
    try {
      await SupabaseConfig.client.from('projects').insert({
        'id': id,
        'user_id': userId,
        'name': name,
        'prompt': prompt,
        'summary': summary,
        'status': 'generating',
        'stage_times': {'generating': at},
        'created_at': at,
        'updated_at': at,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('Monthly limit reached')) {
        throw ProjectLimitReached(e.message);
      }
      throw ProjectStoreOffline(e.message);
    } catch (_) {
      throw ProjectStoreOffline();
    }
  }

  /// Projects newest-first, as the list screen renders them.
  Future<List<ProjectRow>> listProjects(String userId) async {
    try {
      final rows = await SupabaseConfig.client
          .from('projects')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return [
        for (final r in rows as List)
          ProjectRow(
            id: r['id'] as String,
            name: r['name'] as String,
            prompt: (r['prompt'] as String?) ?? '',
            summary: (r['summary'] as String?) ?? '',
            status: r['status'] as String,
            repo: r['repo'] as String?,
            apkUrl: r['apk_url'] as String?,
            error: r['error'] as String?,
            stageTimes:
                (r['stage_times'] as Map?)?.cast<String, dynamic>() ??
                const {},
            buildInfo:
                (r['build_info'] as Map?)?.cast<String, dynamic>(),
            createdAt: DateTime.parse(r['created_at'] as String),
            updatedAt: DateTime.parse(r['updated_at'] as String),
          ),
      ];
    } catch (_) {
      throw ProjectStoreOffline();
    }
  }

  /// Retry path: worker-owned columns fall back to a fresh generating state.
  Future<void> resetForRetry({required String id, DateTime? at}) async {
    final atUtc = (at ?? DateTime.now()).toUtc().toIso8601String();
    try {
      await SupabaseConfig.client.from('projects').update({
        'status': 'generating',
        'error': null,
        'stage_times': {'generating': atUtc},
        'updated_at': atUtc,
      }).eq('id', id);
    } catch (_) {
      throw ProjectStoreOffline();
    }
  }

  Future<void> delete(String id) async {
    try {
      await SupabaseConfig.client.from('projects').delete().eq('id', id);
    } catch (_) {
      throw ProjectStoreOffline();
    }
  }
}

class ProjectRow {
  const ProjectRow({
    required this.id,
    required this.name,
    required this.prompt,
    required this.summary,
    required this.status,
    required this.stageTimes,
    required this.createdAt,
    required this.updatedAt,
    this.repo,
    this.apkUrl,
    this.error,
    this.buildInfo,
  });

  final String id;
  final String name;
  final String prompt;
  final String summary;
  final String status;
  final String? repo;
  final String? apkUrl;
  final String? error;
  final Map<String, dynamic> stageTimes; // {stage: iso, stage_done: iso}
  final Map<String, dynamic>? buildInfo; // {run_id, run_number, size_bytes}
  final DateTime createdAt;
  final DateTime updatedAt;
}
