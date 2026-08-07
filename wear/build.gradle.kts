// Wear OS companion module. Builds independently of the Flutter phone
// APK; the two communicate via the Wearable Data Layer.

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.fitnessapp.wear"
    compileSdk = 34

    defaultConfig {
        // MUST equal the phone module's applicationId. The Wearable Data Layer
        // pairs the watch to the phone by matching applicationId + signing key
        // (see wear/settings.gradle.kts); renaming one side alone silently
        // unpairs them -- the watch keeps building, keeps installing, and
        // simply never hears from the phone again.
        applicationId = "com.fitnessapp.fitness_app.sptr"
        minSdk = 30
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.10" }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.06.00")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.1")

    // Wear-specific Compose surfaces.
    implementation("androidx.wear.compose:compose-material:1.4.0")
    implementation("androidx.wear.compose:compose-foundation:1.4.0")

    // Wearable Data Layer — shared messages between phone + watch.
    implementation("com.google.android.gms:play-services-wearable:18.2.0")
}
