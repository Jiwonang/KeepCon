plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    //id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// google-services 플러그인(`com.google.gms.google-services`)은 **일부러 적용하지 않는다.**
//
// 그 플러그인은 `android/app/google-services.json` 하나를 읽어 [DEFAULT] FirebaseApp을
// 네이티브에서 자동 초기화한다. 그런데 KeepCon은 백엔드가 셋(emulator·dev·prod)이고
// `FirebaseTarget` enum으로 **실행 시** 고른다(`lib/shared/firebase/firebase_bootstrap.dart`).
// json이 있으면 자동 초기화된 [DEFAULT]와 Dart가 넘긴 옵션이 어긋나는 순간
// `Firebase.initializeApp`이 `[core/duplicate-app]`으로 죽는다 — 즉 json에 적힌 한 프로젝트
// 말고는 안드로이드에서 전부 실행 불가가 된다(팀 기본 경로인 에뮬레이터 포함).
//
// 그래서 안드로이드도 web과 같이 **생성된 Dart 옵션(`DefaultFirebaseOptions.android`)만**
// 쓴다. firebase_core·auth·firestore는 명시 옵션만으로 동작하며, json이 필요한 것은
// Crashlytics·Analytics 같은 네이티브 자동 초기화 의존 서비스인데 KeepCon은 쓰지 않는다.
//
// 주의: `flutterfire configure`를 다시 돌리면 위 플러그인 선언과 json이 되살아난다.
// 되살아나면 **지우고 이 주석을 남겨라**(json은 `.gitignore`에 등록돼 있다).

android {
    namespace = "com.keepcon.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications가 **필수로 요구한다.** 예약 알림이 java.time API를
        // 쓰는데, 이걸 켜지 않으면 구형 Android에서 클래스가 없어 런타임에 죽는다
        // (플러그인 문서: 예약을 쓰지 않더라도 켜야 한다).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Firebase 콘솔(keepcon-dev·keepcon-ab660)에 등록된 Android 앱 패키지명과
        // **반드시 일치해야 한다** — 바꾸면 두 프로젝트 모두 앱을 재등록해야 한다.
        // 템플릿 기본값 `com.example.*`을 쓰지 않는 이유: Google이 게시용으로 쓰지 말라고
        // 못박은 예시 네임스페이스라, 소유 도메인 기반 고유 식별자를 써야 한다.
        applicationId = "com.keepcon.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // ML Kit 텍스트 인식의 **언어 모델은 앱이 직접 넣어야 한다.**
    // google_mlkit_text_recognition 플러그인은 라틴 문자만 `implementation`으로 넣고
    // 한국어·중국어·일본어·데바나가리는 `compileOnly`로 둔다(쓰지도 않는 모델로 APK가
    // 커지지 않게 하려는 것). 그래서 앱이 선언하지 않으면 클래스 자체가 APK에 없고,
    // 스캔 화면이 인식기를 만드는 순간 `NoClassDefFoundError`로 죽는다.
    //
    // KeepCon은 `TextRecognitionScript.korean`을 쓴다
    // (`lib/features/scan/services/ml_kit_service.dart`) — 그래서 한국어만 넣는다.
    // 스크립트를 바꾸면 여기도 같이 바꿔야 한다.
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")

    // core library desugaring 런타임. `isCoreLibraryDesugaringEnabled = true`와 짝이며
    // 버전은 flutter_local_notifications가 요구하는 값에 맞춘다
    // (플러그인 android/build.gradle의 coreLibraryDesugaring 선언과 동일해야 한다).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}