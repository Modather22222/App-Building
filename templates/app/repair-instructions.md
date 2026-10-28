# App Building — self-repair instructions template.
# Placeholder: {{FAILURES}} = captured flutter test output (truncated).

A Flutter project is in the CURRENT directory (lib/, pubspec.yaml, test/).
Its smoke test FAILED with this output:

{{FAILURES}}

Fix the code so `flutter test` passes and the project compiles as a release
build. You may ONLY edit files under pubspec.yaml, lib/** and test/**.
Keep the app's described behavior intact — prefer the minimal change that
resolves the failure (often a syntax slip: missing bracket, comma or
semicolon). Reply with DONE when fixed.
