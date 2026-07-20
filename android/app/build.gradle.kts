import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing credentials from android/key.properties (git-ignored,
// never committed). It's absent on a fresh clone / CI, in which case the
// release build falls back to debug signing so it still succeeds.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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

    signingConfigs {
        // The real release key, loaded from android/key.properties (git-ignored).
        // Created ONLY when that file exists, so a fresh clone / CI without the
        // keystore still configures and builds cleanly.
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sign with the real release key when android/key.properties is
            // present; otherwise fall back to debug signing so the build still
            // succeeds (fresh clone, CI, or `flutter run --release` without the
            // keystore). No passwords are hardcoded — they come from the
            // git-ignored key.properties. See RELEASE_SIGNING.md.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // No key.properties → debug-signed. Fine for `flutter run`, but
                // this build must NEVER be distributed (Google Sign-In and Play
                // require the registered release key). Warn loudly so a
                // debug-signed release can't be shipped by accident.
                logger.warn(
                    "INO: android/key.properties not found — the RELEASE build " +
                    "is DEBUG-signed. Do NOT distribute it. See RELEASE_SIGNING.md.",
                )
                signingConfigs.getByName("debug")
            }

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
