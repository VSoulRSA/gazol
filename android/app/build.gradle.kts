import java.util.Properties
import java.io.FileInputStream
import com.android.build.api.dsl.ApplicationExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties (if present)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

extensions.configure<ApplicationExtension> {
    // Use the Flutter-provided ndkVersion (do not duplicate)
    namespace = "com.gazol.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        // Application ID for Play Store
        applicationId = "com.gazol.app"
        // You can update the following values to match your application needs.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Signing config using key.properties (if provided)
    signingConfigs {
        create("release") {
            // keys may be null if key.properties doesn't exist; that's okay for debug builds
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            keystoreProperties["storeFile"]?.let {
                storeFile = file(it as String)
            }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // Use the release signing config we created above
            signingConfig = signingConfigs.getByName("release")
            // Keep minify/shrink off for initial release; enable later if desired
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            // debug config (unchanged)
        }
    }
}

    kotlin {
        compilerOptions {
            jvmTarget = JvmTarget.JVM_11
        }
    }

flutter {
    source = "../.."
}
