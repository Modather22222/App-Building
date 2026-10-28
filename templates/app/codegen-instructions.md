# App Building — codegen instructions template.
# Placeholders (substituted with jq by scripts/worker.sh, never by shell):
#   {{NAME}}    app display name from the plan chunk
#   {{DART}}    valid dart package identifier for pubspec
#   {{REQUEST}} the user's build request, verbatim
#   {{SUMMARY}} the agent's plan summary

You are generating a NEW Flutter application. Work inside the CURRENT directory (it is empty).

App name: {{NAME}}
Dart package identifier (use this as pubspec.yaml `name`): {{DART}}

Build request (verbatim from the user):
{{REQUEST}}

Plan summary (from the factory agent):
{{SUMMARY}}

Hard requirements:
1. Only these files may exist: pubspec.yaml, lib/**, test/widget_test.dart, README.md.
   NOTHING else — no android/, ios/, web/, windows/, .git/, gradle files, none.
2. pubspec.yaml: environment `sdk: ">=3.5.0 <4.0.0"`. dependencies: flutter on the
   flutter sdk plus only pub.dev packages you actually use. dev_dependencies:
   flutter_test on the flutter sdk. No assets, no fonts — use Material icons/emoji
   for imagery.
3. Implement the requested app as a compact but COMPLETE working MVP:
   Material 3, meaningful in-memory state (ChangeNotifier or setState), no platform
   channels, no network APIs unless the user explicitly asked. If networking was
   explicitly requested, include loading/empty/error states and use https only.
4. main() calls runApp directly; ThemeData(useMaterial3: true) with
   themeMode: ThemeMode.system so light and dark both work.
5. test/widget_test.dart: one smoke test that pumps the app and expects a core widget.
6. Code must compile as a release build on Flutter stable 3.47 — analyzer errors are
   not allowed (warnings are tolerable).
7. README.md: 4-8 lines describing what the app does and how to run it.

When finished, reply with a one-paragraph summary of what you built. If something in the
request is ambiguous, choose the most reasonable interpretation and note it in your
summary — do not ask questions.
