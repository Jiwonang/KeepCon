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
    // `flutterfire configure`가 다시 심어 놓는 선언. `apply false`라 여기서는 무해하지만,
    // **app 모듈에서 적용하면 안 된다** — 이유는 app/build.gradle.kts 주석 참조
    // (백엔드 3개를 실행 시 고르는 구조라 google-services.json 자동 초기화와 충돌한다).
    id("com.google.gms.google-services") version "4.3.15" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")