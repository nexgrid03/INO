# ============================================================================
# INO — R8 / ProGuard keep rules
# ============================================================================
# Release builds run R8 in full mode (Flutter enables code shrinking for
# release). These rules keep the reflectively-loaded ML Kit classes and silence
# R8's missing-class check for optional components we deliberately don't bundle.

# ----------------------------------------------------------------------------
# Google ML Kit — Text Recognition (google_mlkit_text_recognition) and the
# Document Scanner (google_mlkit_document_scanner).
# ----------------------------------------------------------------------------
# The text-recognition plugin's Android code references FIVE script recognizers
# (Latin + Chinese + Japanese + Korean + Devanagari). The app only uses the
# default LATIN recognizer, so the other four models are NOT on the classpath.
# Under R8 full mode a reference to an absent class is a hard error, which is
# exactly the `minifyReleaseWithR8` failure:
#   Missing class com.google.mlkit.vision.text.{chinese,japanese,korean,devanagari}.*
# These scripts are never invoked at runtime, so it is safe to tell R8 not to
# warn/fail on them. (Adding the four language libraries would instead balloon
# the AAB by ~20 MB of models we never use.)
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# Keep the ML Kit surface — options/builders/detectors are instantiated
# reflectively by the SDK, so stripping/renaming them breaks text recognition
# and document scanning at runtime.
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }

# ML Kit resolves its bundled models through Google Play services internals;
# keep them and don't warn on the optional pieces pulled in transitively.
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-dontwarn com.google.android.gms.**

# ----------------------------------------------------------------------------
# Kotlin coroutines (used by the ML Kit plugins). Prevents R8 from stripping
# the internal service-loader classes.
# ----------------------------------------------------------------------------
-dontwarn kotlinx.coroutines.**
-keep class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }
