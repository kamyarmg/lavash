pluginManagement {
    // Make CI resilient by allowing FLUTTER_HOME/FLUTTER_ROOT env vars if local.properties is absent.
    val flutterSdkPath: String = run {
        val properties = java.util.Properties()
        val localProps = file("local.properties")
        val fromLocal =
            if (localProps.exists()) {
                localProps.inputStream().use { properties.load(it) }
                properties.getProperty("flutter.sdk")
            } else null

        val fromEnv = System.getenv("FLUTTER_HOME")
            ?: System.getenv("FLUTTER_ROOT")

        (fromLocal ?: fromEnv)
            ?: error("flutter.sdk not set in local.properties and FLUTTER_HOME/FLUTTER_ROOT not set")
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
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
