pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    // START: FlutterFire Configuration
    // 4.4.1+ is a hard requirement of the Crashlytics Gradle plugin 3 below --
    // with 4.3.15 the build dies at configuration time on
    // uploadCrashlyticsMappingFileRelease ("requires Google-Services 4.4.1 and
    // above"), for debug builds too.
    id("com.google.gms.google-services") version("4.4.2") apply false
    id("com.google.firebase.crashlytics") version("3.0.3") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.20" apply false
}

include(":app")
include(":wear")
