# --- Flutter Plugin API Rules ---
# Keep the plugin's main classes
-keep class io.github.iot_gamer.hand_landmarker.MyHandLandmarker { *; }
-keep class io.github.iot_gamer.hand_landmarker.HandLandmarkerPlugin implements io.flutter.embedding.engine.plugins.FlutterPlugin {
    public <init>();
}

# --- MediaPipe Core, Framework, Tasks & Protobuf Rules ---
# Keeps the main mediapipe classes and framework, which are often called via JNI.
-keep public class com.google.mediapipe.** { *; }
-keep class com.google.mediapipe.framework.** { *; } 
-keep public class com.google.mediapipe.framework.Graph { *; } 
-keep class com.google.mediapipe.tasks.** { *; } 
-keep interface com.google.mediapipe.tasks.** { *; } 
-keep class com.google.mediapipe.solutioncore.** { *; }

# Keeps all protobuf-generated classes, which MediaPipe uses for configuration.
-keep class com.google.mediapipe.proto.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keep class * extends com.google.protobuf.GeneratedMessageLite$Builder { *; } 

# --- Other Common Dependencies ---
# Keeps Google's Flogger (logging) and Guava (common utilities)
-keep class com.google.common.flogger.** { *; }
-keep public class com.google.common.** { *; }
-keep public interface com.google.common.* { *; }

# --- Warning Suppression ---
# Suppress warnings from compile-time-only dependencies (e.g., auto-value)
-dontwarn javax.annotation.**
-dontwarn javax.lang.model.**
-dontwarn com.google.auto.value.**

# Suppress warnings from specific MediaPipe proto classes
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate