import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (README → „Podpis wydania"). key.properties is gitignored; the keystore itself lives
// outside every project tree (release_keystore_dir in grobing-agents/.claude/rules/project-config.md).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    // Package name (ADR-002, decided 2026-10-05) — never change it: Android would treat the app as a
    // different one and the new install would not see the phone's database.
    namespace = "com.grobing.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.grobing.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Never the debug key: a phone holding real data must only ever get release-signed builds,
            // or the next update needs an uninstall — and an uninstall deletes the database.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// Fail loudly instead of producing an unsigned or debug-signed release build.
gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any { it.project == project && it.name.contains("Release") }
    if (releaseRequested && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "Missing android/key.properties — release builds of Grobing must be signed with the " +
                "release key (README → „Podpis wydania\"). Debug signing is never used for release."
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    // The background backup (ISSUE-010, D1): Jetpack WorkManager directly, no Flutter plugin — the
    // worker starts its own headless engine with the documents channel. 2.11.x: minSdk 23 (ours is
    // flutter.minSdkVersion = 24). Adds WAKE_LOCK, ACCESS_NETWORK_STATE, RECEIVE_BOOT_COMPLETED and
    // FOREGROUND_SERVICE to the merged manifest (SPIKE-003, M3) — never INTERNET (NFR-005).
    implementation("androidx.work:work-runtime:2.11.2")
}
