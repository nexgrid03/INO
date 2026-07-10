plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.inoapp"
    // Pinned to 36 explicitly: transitive plugins (flutter_plugin_android_lifecycle,
    // file_picker) declare minCompileSdk=36 in their AAR metadata, so the app must
    // compile against SDK 36 or `checkDebugAarMetadata` fails. Flutter 3.44's
    // `flutter.compileSdkVersion` already defaults to 36; pinning it here guarantees
    // the build stays correct regardless of Flutter version.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.inoapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Keep R8 code-shrinking ENABLED for release (smaller AAB). We attach
            // our own ProGuard rules so R8's full-mode missing-class check doesn't
            // fail on ML Kit's optional non-Latin text recognizers, and so the
            // reflectively-loaded ML Kit classes are kept. See proguard-rules.pro.
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
