# Keep attributes for annotations and reflection
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Keep Tauri plugin classes and InvokeArg classes
-keep @app.tauri.annotation.TauriPlugin class * { *; }
-keep @app.tauri.annotation.InvokeArg class * { *; }
-keepclassmembers class * {
    @app.tauri.annotation.Command <methods>;
    @app.tauri.annotation.ActivityCallback <methods>;
    @app.tauri.annotation.InvokeArg <fields>;
}

# Keep the plugin package classes, fields, and methods
-keep class com.plugin.vpnservice.** { *; }
-keepclassmembers class com.plugin.vpnservice.** { *; }
