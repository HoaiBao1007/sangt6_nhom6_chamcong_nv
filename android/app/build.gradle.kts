plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // bắt buộc cho Flutter
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.sangt6_nhom6_chamcong_nv" // đổi cho khớp package của bạn
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.sangt6_nhom6_chamcong_nv" // đổi nếu cần
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        debug {
            // tắt shrink để tránh lỗi trong giai đoạn dev
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            // giữ đơn giản cho demo (không shrink)
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // ký debug cho nhanh (đổi khi phát hành)
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.24")
}

flutter {
    source = "../.."
}
