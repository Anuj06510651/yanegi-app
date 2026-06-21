import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("com.google.firebase.crashlytics")
    //firebase crashlytics
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.yanegi.app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
    applicationId = "com.yanegi.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
    targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // Environment flavors: prod = live Play Store app (com.yanegi.app),
    // dev  = isolated yanegi-dev project (com.yanegi.app.dev, installs side-by-side).
    flavorDimensions += "env"
    productFlavors {
        create("prod") {
            dimension = "env"
            // applicationId stays com.yanegi.app — production untouched.
        }
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled =false
            isShrinkResources=false

        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

tasks.register<Copy>("copyReleaseAabWithVersionName") {
    dependsOn("bundleRelease")

    val appName = "yanegi"
    val buildName = flutter.versionName
    val buildNumber = flutter.versionCode

    from(layout.buildDirectory.file("outputs/bundle/release/app-release.aab"))
    into(layout.buildDirectory.dir("outputs/bundle/release/versioned"))
    rename("app-release.aab", "$appName-v$buildName+$buildNumber-release.aab")
}

tasks.matching { it.name == "bundleRelease" }.configureEach {
    finalizedBy("copyReleaseAabWithVersionName")
}
