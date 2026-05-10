// Standalone Android Gradle root. Open this folder in Android Studio
// as its own project — the Flutter phone APK ships from `../mobile/`
// and the watch APK ships from here. Both write to the same
// applicationId so Wearable Data Layer pairs them automatically.

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.application") version "8.7.0"
        id("org.jetbrains.kotlin.android") version "2.0.21"
        id("org.jetbrains.kotlin.plugin.compose") version "2.0.21"
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "fitness_wear"
include(":wear-app")
project(":wear-app").projectDir = file(".")
