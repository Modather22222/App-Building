enum ChatRole { user, assistant }

class AuthSession {
  const AuthSession({
    required this.id,
    required this.name,
    required this.email,
    this.guest = false,
  });

  final String id;
  final String name;
  final String email;
  final bool guest;

  // Phase 7 — value equality on the user id: token refreshes produce fresh
  // session objects with the SAME user, and without this equality every
  // refresh looked like an auth change (router rebuilds, provider resets).
  @override
  bool operator ==(Object other) => other is AuthSession && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class ChatThread {
  ChatThread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.isStreaming = false,
    this.planName,
    this.planSummary,
    this.actionUsed = false,
  });

  final String id;
  final ChatRole role;
  String text;
  final DateTime at;
  bool isStreaming;
  String? planName;
  String? planSummary;
  bool actionUsed;
}

/// Pipeline of a generated app. Order matters — the UI derives progress
/// from the enum index.
enum BuildStage {
  generating('Generating code', 'Generating', '~1 min'),
  pushing('Pushing to GitHub', 'Pushing', '~30 s'),
  queued('Waiting for build runner', 'Queued', '~10–15 min'),
  building('Building APK', 'Building', '~3 min'),
  ready('Ready to download', 'Ready', '');

  const BuildStage(this.label, this.short, this.eta);

  final String label;
  final String short;
  final String eta;
}

class AppProject {
  AppProject({
    required this.id,
    required this.name,
    required this.summary,
    required this.createdAt,
    this.prompt = '',
    this.stage = BuildStage.generating,
    this.failed = false,
    this.repo,
    this.apkUrl,
    this.error,
    this.refused = false,
    Map<BuildStage, DateTime>? stageStarted,
    Map<BuildStage, DateTime>? stageFinished,
    this.buildInfo,
  }) : stageStarted = stageStarted ?? {},
       stageFinished = stageFinished ?? {};

  final String id;
  final String name;
  final String summary;
  final String prompt;
  final DateTime createdAt;
  final String? repo; // owner/name of the generated repo (from the factory)
  final String? apkUrl; // release asset URL once the build lands
  final String? error; // failure detail from the factory
  bool refused; // quota refusal recorded by the trigger (not spent budget)
  final Map<String, dynamic>? buildInfo; // {run_id, run_number, size_bytes}
  BuildStage stage;
  bool failed;
  final Map<BuildStage, DateTime> stageStarted;
  final Map<BuildStage, DateTime> stageFinished;

  int get stageIndex => BuildStage.values.indexOf(stage);

  bool get isActive => !failed && stage != BuildStage.ready;

  String get slug {
    final cleaned = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final trimmed = cleaned.replaceAll(RegExp(r'^-+|-+$'), '');
    if (trimmed.isEmpty) return 'flutter-app';
    return trimmed;
  }

  AppProject copyWith({
    BuildStage? stage,
    bool? failed,
    String? error,
    bool? refused,
    Map<String, dynamic>? buildInfo,
    Map<BuildStage, DateTime>? stageStarted,
    Map<BuildStage, DateTime>? stageFinished,
  }) {
    return AppProject(
      id: id,
      name: name,
      summary: summary,
      prompt: prompt,
      createdAt: createdAt,
      repo: repo,
      apkUrl: apkUrl,
      stage: stage ?? this.stage,
      failed: failed ?? this.failed,
      error: error ?? this.error,
      refused: refused ?? this.refused,
      buildInfo: buildInfo ?? this.buildInfo,
      stageStarted: stageStarted ?? Map.of(this.stageStarted),
      stageFinished: stageFinished ?? Map.of(this.stageFinished),
    );
  }
}
