# R8 keep rules for App Building (factory app).
#
# The white-screen incident (TODO.md Phase 1): R8 renamed the pigeon-generated
# methods of shared_preferences_android, whose dispatcher resolves them
# reflectively -> NoSuchMethodError on the first SharedPreferences.getInstance()
# -> permanent white screen on launch. The plugin layer must stay intact.
#
# Preserving io.flutter.** costs ~0.5 MB of dex and kills that entire failure
# family; the app's own code and third-party libraries still shrink.

# Flutter plugin layer is resolved reflectively (pigeon dispatch, plugin
# registry) — preserve it whole.
-keep class io.flutter.** { *; }

# The engine references Play Core split-install classes (deferred-components
# delivery) that are not on the classpath for direct-APK builds. Those code
# paths never execute here — Flutter's own generated missing_rules.txt says
# the same. Without this, R8 fails the build.
-dontwarn com.google.android.play.core.**

# Honor androidx @Keep annotations (several plugins rely on them).
-keep class * { @androidx.annotation.Keep <fields>; }
-keep class * { @androidx.annotation.Keep <methods>; }
-keep @androidx.annotation.Keep class * { *; }
