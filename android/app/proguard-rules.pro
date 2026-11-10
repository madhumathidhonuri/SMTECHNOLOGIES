# Flutter / plugin keep rules for release builds.
-keep class io.flutter.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# flutter_local_notifications uses Gson reflection for scheduled payloads.
-keep class com.dexterous.** { *; }
-keepattributes *Annotation*
-keepattributes Signature

# OkHttp / socket transport
-dontwarn okhttp3.**
-dontwarn okio.**

# Fix Play Core missing classes in release build
-dontwarn com.google.android.play.core.**
