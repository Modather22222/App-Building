import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/profile_repository.dart';
import '../../data/providers.dart';
import '../projects/projects_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider);
    final projects = ref.watch(projectsProvider);
    final colors = Theme.of(context).colorScheme;

    final name = session?.name ?? 'Guest dev';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.gutter,
          8,
          AppTokens.gutter,
          48,
        ),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: colors.primaryContainer.withValues(alpha: 0.6),
                child: Text(
                  _initials(name),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      session?.email ?? 'guest@local.device',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.sectionGap),
          _PlanCard(projectsThisMonth: _usedThisCycle(projects)),
          const SizedBox(height: AppTokens.sectionGap),
          _sectionLabel('SETTINGS', context),
          const SizedBox(height: AppTokens.gapSm),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Appearance'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _modeLabel(ref.watch(themeModeProvider)),
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                  onTap: () => _openThemeSheet(context, ref),
                ),
                const Divider(height: 1, indent: AppTokens.gutter),
                const _NotificationsTile(),
                const Divider(height: 1, indent: AppTokens.gutter),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('About'),
                  trailing: Text(
                    'v1.0.0',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('App Building \u00b7 MVP build 1.0.0'),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: AppTokens.gutter),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy & terms'),
                  subtitle: const Text('What we store, in plain language'),
                  subtitleTextStyle: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(
                      'https://raw.githubusercontent.com/Modather22222/'
                      'App-Building/main/PRIVACY.md',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.gapLg),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colors.errorContainer,
              foregroundColor: colors.onErrorContainer,
            ),
            onPressed: () => _confirmSignOut(context, ref),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  int _usedThisCycle(List<AppProject> projects) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    var used = 0;
    for (final p in projects) {
      if (p.refused) continue; // a refusal is a recorded failure, not budget
      if (p.createdAt.isAfter(monthStart)) used++;
    }
    return used;
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'AF';
    if (parts.length == 1) {
      final single = parts.first;
      return single.substring(0, single.length > 1 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _modeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  void _openThemeSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Consumer(
          builder: (context, sheetRef, _) {
            final mode = sheetRef.watch(themeModeProvider);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppTokens.gapSm),
                Padding(
                  padding: const EdgeInsets.all(AppTokens.gapLg),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                for (final candidate in ThemeMode.values)
                  ListTile(
                    leading: Icon(switch (candidate) {
                      ThemeMode.system => Icons.settings_suggest_outlined,
                      ThemeMode.light => Icons.light_mode_outlined,
                      ThemeMode.dark => Icons.dark_mode_outlined,
                    }),
                    title: Text(switch (candidate) {
                      ThemeMode.system => 'System',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    }),
                    trailing: mode == candidate
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () {
                      sheetRef.read(themeModeProvider.notifier).set(candidate);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                const SizedBox(height: AppTokens.gapMd),
              ],
            );
          },
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(authProvider.notifier).signOut();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _NotificationsTile extends StatefulWidget {
  const _NotificationsTile();

  @override
  State<_NotificationsTile> createState() => _NotificationsTileState();
}

class _NotificationsTileState extends State<_NotificationsTile> {
  bool _enabled = false;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_outlined),
      title: const Text('Build notifications'),
      subtitle: const Text('When builds finish or fail'),
      value: _enabled,
      onChanged: (value) => setState(() => _enabled = value),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.projectsThisMonth});

  final int projectsThisMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final session = ref.watch(authProvider);
    final backendProfile = ref.watch(profileProvider);

    final planName = session == null
        ? 'Free'
        : (backendProfile?.plan ?? 'free') == 'free'
            ? 'Free'
            : (backendProfile!.plan[0].toUpperCase() + backendProfile.plan.substring(1));
    final limit = PlanLimits.of(session == null ? 'free' : backendProfile?.plan ?? 'free');
    final isUnlimited = session != null && backendProfile?.plan == 'unlimited';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOUR PLAN',
              style: text.labelSmall?.copyWith(
                letterSpacing: 1.2,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.gapSm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(planName, style: text.titleLarge),
                const Spacer(),
                Text(
                  session == null
                      ? 'local device'
                      : 'built on GitHub Actions',
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.gapLg),
            _Meter(
              label: 'Projects / month',
              used: projectsThisMonth,
              total: isUnlimited ? 0 : limit,
            ),
            const SizedBox(height: AppTokens.gapMd),
            FilledButton.tonal(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Upgrade flow lands with billing.'),
                ),
              ),
              child: const Text('Upgrade plan'),
            ),
            const SizedBox(height: AppTokens.gapSm),
            Text(
              'Live usage — server-derived, resets each calendar month. '
              'The build service enforces this limit server-side.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.used, required this.total});

  final String label;
  final int used;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: text.titleSmall),
            Text(
              total <= 0 ? '$used · unlimited' : '$used / $total',
              style: text.labelLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            child: LinearProgressIndicator(
              value: used / total,
              minHeight: 4,
              backgroundColor: colors.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

Widget _sectionLabel(String text, BuildContext context) => Text(
  text,
  style: Theme.of(context).textTheme.labelSmall?.copyWith(
    letterSpacing: 1.2,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ),
);
