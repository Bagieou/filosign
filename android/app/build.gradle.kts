plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.filosign"
    compileSdk = flutter.compileSdkVersion
    // FiloSign recognizer: pinned to an installed NDK (Windows sdkmanager
    // cannot auto-fetch); >= the 28.2.x the camera plugins request.
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.filosign"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_pose_detection (live practice / quiz) requires minSdk 31.
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

configurations.all {
    // flutter_pose_detection pulls old org.tensorflow:tensorflow-lite* AARs that
    // clash with tflite_flutter's litert on the org.tensorflow.lite namespace.
    exclude(group = "org.tensorflow", module = "tensorflow-lite")
    exclude(group = "org.tensorflow", module = "tensorflow-lite-gpu")
    exclude(group = "org.tensorflow", module = "tensorflow-lite-api")
}
