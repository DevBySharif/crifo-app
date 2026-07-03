# Flutter wraps its own engine classes; keep them intact.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# Firebase / Google Play services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.**

# video_player / ExoPlayer (media3) — reflection-heavy
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Keep annotations and generic signatures used at runtime.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
