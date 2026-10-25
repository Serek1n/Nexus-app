# Ядро Xray (gomobile) и плагин — не трогать при оптимизации R8.
-keep class libv2ray.** { *; }
-keep class go.** { *; }
-keep class dev.amirzr.flutter_v2ray_client.** { *; }
-dontwarn libv2ray.**
-dontwarn go.**
# Flutter (отложенные компоненты Play Core не используются)
-dontwarn com.google.android.play.core.**
