# CriFO ProGuard / R8 Rules
# ─────────────────────────────────────────────────────────────────────────────
# Applied when isMinifyEnabled = true in build.gradle.kts (release build).
# R8 in full-mode aggressively shrinks and obfuscates — these rules prevent
# classes that are accessed via reflection or JNI from being stripped.

# ── Flutter engine ────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# ── Firebase / Google Play services ──────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.**

# ── video_player / ExoPlayer / Media3 (reflection-heavy) ─────────────────────
-keep class androidx.media3.** { *; }
-keepclassmembers class androidx.media3.** { *; }
-dontwarn androidx.media3.**
# Legacy ExoPlayer (some Flutter video_player versions still use it)
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# ── Dio HTTP client (uses reflection for JSON serialization) ──────────────────
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# ── Kotlin stdlib & coroutines ────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ── Keep annotations and generic signatures (needed for Dio JSON parsing) ─────
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# ── Prevent stripping of serialized JSON model classes ───────────────────────
# (CriFO uses Map<String,dynamic> throughout — no generated models to strip)
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ── Shared preferences ────────────────────────────────────────────────────────
-keep class androidx.datastore.** { *; }

# ── url_launcher ──────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.urllauncher.** { *; }

# ── cached_network_image / Glide-style loaders ───────────────────────────────
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.AppGlideModule { <init>(...); }
-dontwarn com.bumptech.glide.**

# ── Suppress common library warnings that don't affect runtime ────────────────
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
