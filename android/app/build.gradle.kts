plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nodexdata.speechtotext"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by several plugins' use of java.time/newer java.util.* APIs
        // on API levels below where they're natively available.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.nodexdata.speechtotext"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 26 (not flutter.minSdkVersion's default of 24) -- self-managed
        // android.telecom.ConnectionService (the native incoming-call UI,
        // see CallConnectionService.kt) requires API 26+. Negligible impact
        // in practice (Android 8.0, released 2017).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // NativeAuthStore.kt's own encrypted token store (native decline calls
    // for the ConnectionService integration) -- deliberately NOT reading
    // flutter_secure_storage's own on-disk format (a plugin-internal,
    // versioned custom cipher, not a stable API to depend on from here).
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    // MyFirebaseMessagingReceiver.kt needs com.google.firebase.messaging.RemoteMessage
    // directly -- the firebase_messaging Flutter plugin only depends on this
    // via `implementation` in its own Gradle module, so it's on the final
    // APK's runtime classpath but NOT visible to this module at compile
    // time. Version pinned to the same FirebaseSDKVersion firebase_core's
    // own android/gradle.properties uses, so this resolves to the identical
    // artifact already being pulled in transitively (no duplicate-version
    // conflict).
    implementation(platform("com.google.firebase:firebase-bom:33.16.0"))
    implementation("com.google.firebase:firebase-messaging")
}
