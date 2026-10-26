import 'supabase_config.dart';

/// Profile row + authoritative usage accounting.
///
/// Meters are DERIVED, never mutated: monthly counts come straight from the
/// projects table (calendar month), so they are always truthful and the
/// server is the authority — the client mirrors the same limit map only to
/// render the meter.
class PlanLimits {
  static const map = <String, int>{
    'free': 3,
    'starter': 10,
    'pro': 30,
    'scale': 100,
  };

  static int of(String plan) => map[plan] ?? 3;
}

class ProfileRepository {
  const ProfileRepository();

  /// Own profile row (RLS guarantees it is strictly the bearer's).
  Future<ProfileRow?> fetch() async {
    try {
      final rows = await SupabaseConfig.client
          .from('profiles')
          .select('plan, display_name')
          .limit(1);
      if (rows.isEmpty) return null;
      final r = rows.first as Map;
      return ProfileRow(
        plan: (r['plan'] as String?) ?? 'free',
        displayName: (r['display_name'] as String?) ?? '',
      );
    } catch (_) {
      return null; // degrade: meter renders without plan info
    }
  }
}

class ProfileRow {
  const ProfileRow({required this.plan, required this.displayName});

  final String plan;
  final String displayName;
}
