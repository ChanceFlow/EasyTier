import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing
//
// Android only installs an update over an existing app when both APKs carry the
// SAME signing certificate. The default `signingConfigs.getByName("debug")`
// uses `~/.android/debug.keystore`, which Gradle *creates on demand*: every
// build container without that file got a brand-new key, so each published APK
// refused to install over the previous one ("签名不一致").
//
// Two options, checked in this order:
//   1. `android/key.properties` (NOT committed) — a real release key. Same file
//      layout Flutter's own docs describe:
//         storeFile=/abs/path/to/release.jks
//         storePassword=...
//         keyAlias=...
//         keyPassword=...
//   2. `android/app/easytier-internal.jks` (committed) — the internal test key.
//      It is checked in ON PURPOSE so every machine and CI runner signs the
//      same way; its password is public and it MUST NOT be used for a Play
//      Store release. See android/README.md → "Signing".
// ---------------------------------------------------------------------------
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKey) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val internalKeystore = file("easytier-internal.jks")

android {
    namespace = "com.kkrainbow.easytier_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kkrainbow.easytier_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        } else if (internalKeystore.exists()) {
            create("internal") {
                // Public test key: stable signatures, never for production.
                storeFile = internalKeystore
                storePassword = "easytier-internal"
                keyAlias = "easytier"
                keyPassword = "easytier-internal"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                internalKeystore.exists() -> signingConfigs.getByName("internal")
                // Last resort so `flutter run --release` still works locally; a
                // random debug key cannot be updated in place, so warn loudly.
                else -> {
                    logger.warn(
                        "EasyTier: no release key found (android/key.properties " +
                            "or android/app/easytier-internal.jks). Falling back to " +
                            "the debug keystore; this APK cannot update an installed build."
                    )
                    signingConfigs.getByName("debug")
                }
            }
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
