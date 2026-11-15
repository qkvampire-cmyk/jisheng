plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.poker_tracker"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.poker_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 固定签名：jisheng-release.p12（PKCS12，密码 jisheng2026）
    // 这是自签名（sideload 用途），目的是让每次 CI 产物签名一致、可覆盖升级。
    signingConfigs {
        create("release") {
            storeFile = file("jisheng-release.p12")
            storePassword = "jisheng2026"
            keyAlias = "jisheng"
            keyPassword = "jisheng2026"
            storeType = "PKCS12"
        }
    }

    buildTypes {
        release {
            // 固定签名（仓库内 jisheng-release.p12，PKCS12）
            // 目的：CI 每次构建签名一致，手机才能覆盖升级；换签名会导致
            // “软件包与现有软件包存在冲突”而必须卸载重装。
            signingConfig = signingConfigs.getByName("release")
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
