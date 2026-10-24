import 'supabase_config.dart';

/// Thin, best-effort Supabase-backed projects store.
///
/// Mirrors [ChatRepository]: every call degrades via [ProjectStoreOffline]
/// and providers keep working from memory (`never brick the app`).
class ProjectStoreOffline implements Exception {}

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
  final DateTime createdAt;
  final DateTime updatedAt;
}
