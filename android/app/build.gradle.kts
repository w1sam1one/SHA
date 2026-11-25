import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (see docs/release.md). The upload key's location and
// passwords are read from android/key.properties, which is git-ignored and
// must never be committed. Without that file the release build is left
// UNSIGNED: it is never signed with the debug key. Debug and profile builds
// do not use any of this, and a broken key.properties only stops release
// builds.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val keystorePropertiesReadable = keystorePropertiesFile.isFile &&
    runCatching {
        keystorePropertiesFile.reader(Charsets.UTF_8).use { keystoreProperties.load(it) }
    }.isSuccess
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingReleaseSigningKeys =
    releaseSigningKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
val hasReleaseSigning = keystorePropertiesReadable && missingReleaseSigningKeys.isEmpty()
// Android Studio's "Generate Signed Bundle/APK" injects its own key.
val ideInjectsSigning = providers.gradleProperty("android.injected.signing.store.file").isPresent

// Checked against the tasks that will actually run (also `assemble`, `build`
// or abbreviations like `bR`), not only the names typed on the command line.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.project == project && it.name.endsWith("Release") }
    if (!buildsRelease || ideInjectsSigning) return@whenReady
    // Never print values from key.properties: only file and key names.
    if (keystorePropertiesFile.isFile && !keystorePropertiesReadable) {
        throw GradleException(
            "android/key.properties kunde inte läsas. Skriv \\ som \\\\ i värden " +
                "och använd / i sökvägar. Se android/key.properties.example.",
        )
    }
    if (keystorePropertiesFile.isFile && missingReleaseSigningKeys.isNotEmpty()) {
        throw GradleException(
            "android/key.properties saknar: ${missingReleaseSigningKeys.joinToString()}. " +
                "Se android/key.properties.example och docs/release.md.",
        )
    }
    if (!hasReleaseSigning) {
        // flutter build runs Gradle with -q, which hides warn(); quiet() is shown.
        logger.quiet(
            "VARNING: android/key.properties saknas. Release-bygget blir OSIGNERAT " +
                "och kan inte laddas upp till Google Play. Det signeras aldrig med " +
                "debugnyckeln. Se docs/release.md.",
        )
    }
}

android {
    namespace = "se.sha.sha"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The owner's decision 5 in docs/decisions/0014: an id from a domain
        // the owner controls (w1sam1one.github.io). The Kotlin package and
        // `namespace` above stay se.sha.sha; only this id is the app's
        // identity on the phone. A new id is a different app: the old one
        // and its data stay as they are.
        applicationId = "io.github.w1sam1one.sha"
        // Android 9 (API 28): the vault key needs an unlocked phone
        // (setUnlockedDeviceRequired), and a key rotation (APK Signature
        // Scheme v3) works on every phone that can install the app (0014).
        minSdk = maxOf(flutter.minSdkVersion, 28)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Upload key from key.properties, or unsigned. Never the debug key.
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null
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
