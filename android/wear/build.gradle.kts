plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.adhdplanner.adhd_planner.wear"
    compileSdk = 36

    defaultConfig {
        // Same applicationId + (debug) signing cert as the phone app: that pair
        // is what lets the Wearable Data Layer bridge the two as one companion.
        applicationId = "com.adhdplanner.adhd_planner"
        minSdk = 30 // Wear OS 3 (Galaxy Watch 4+)
        // 33 (not 34): keeps the alarm foreground service off Android 14's
        // FGS-type requirement -- this is an adb-sideloaded companion, not a
        // Play release, so the older target is fine.
        targetSdk = 33
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        compose = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Wear Compose Material 3 (M3 Expressive) drives the Compose version:
    // material3 1.6.2 requires Compose 1.9.0, so pin the base libs to match
    // rather than a BOM that lags behind.
    implementation("androidx.compose.ui:ui:1.9.0")
    implementation("androidx.compose.foundation:foundation:1.9.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.wear.compose:compose-material3:1.6.2")
    implementation("androidx.wear.compose:compose-foundation:1.6.2")
    implementation("com.google.android.gms:play-services-wearable:18.2.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.core:core-ktx:1.13.1")

    testImplementation("junit:junit:4.13.2")
    // Real org.json on the JVM (the android.jar one is a no-op stub under
    // plain unit tests), so ChecklistData.parse is testable without a device.
    testImplementation("org.json:json:20240303")
}
