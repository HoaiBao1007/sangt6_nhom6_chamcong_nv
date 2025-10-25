pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    // trỏ tới gradle tool của Flutter
    val props = java.util.Properties()
    file("local.properties").inputStream().use { props.load(it) }
    val flutterSdkPath = props.getProperty("flutter.sdk")
        ?: throw GradleException("flutter.sdk not set in local.properties")
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.6.0" apply false
    id("com.android.library") version "8.6.0" apply false
    // Giữ 1.9.24 để tương thích plugin NFC hiện tại
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}

include(":app")
