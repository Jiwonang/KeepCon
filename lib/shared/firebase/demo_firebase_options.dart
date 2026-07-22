/// KeepCon 공유 계약 — **에뮬레이터 전용** Firebase 옵션.
///
/// 이 파일은 `lib/firebase_options.dart`(= `flutterfire configure`가 생성하는 **실제
/// 프로젝트** 옵션)와 **분리된 별도 파일**이다. 분리한 이유:
/// `flutterfire configure`는 `lib/firebase_options.dart`를 통째로 덮어쓴다 —
/// 에뮬레이터 값을 거기 두면 실제 프로젝트를 연결하는 순간 사라진다.
/// 두 경로(에뮬레이터 / 실제 프로젝트)를 각자 파일로 두면 서로를 망가뜨리지 않는다.
///
/// ---
/// ## 왜 값이 전부 가짜인가 (비밀 아님)
/// projectId가 **`demo-` 접두사**면 Firebase 에뮬레이터 스위트는 그 프로젝트를
/// "오프라인 데모"로 취급한다 — 실제 Google 백엔드로 나가는 요청이 차단되고,
/// 자격 증명 검증도 하지 않는다. 따라서 apiKey·appId 등은 **형식만 맞는 더미**면 되고,
/// 커밋해도 노출되는 비밀이 없다(가리키는 실제 프로젝트가 없다).
///
/// `.firebaserc`의 `default`가 [projectId]와 **같아야** `firebase emulators:start`가
/// 이 앱과 같은 프로젝트 네임스페이스를 쓴다. 한쪽만 바꾸면 앱은 빈 DB를 보게 된다.
///
/// ---
/// ## 소비 지점
/// [firebase_bootstrap.dart]의 `FirebaseTarget.emulator` 경로에서만 사용한다.
/// 앱 코드가 직접 참조하지 않는다.
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// 로컬 에뮬레이터(`demo-keepcon`) 전용 [FirebaseOptions].
///
/// 실제 프로젝트 옵션은 `lib/firebase_options.dart`의 `DefaultFirebaseOptions`가
/// 담당한다 — 이 클래스와 혼동하지 마라.
class DemoFirebaseOptions {
  /// 인스턴스화 금지 — 이 클래스는 정적 옵션 모음이다.
  const DemoFirebaseOptions._();

  /// 에뮬레이터가 사용하는 데모 프로젝트 id. `.firebaserc`의 `default`와 일치해야 한다.
  static const String projectId = 'demo-keepcon';

  /// 현재 플랫폼용 데모 [FirebaseOptions].
  ///
  /// 플랫폼별로 다른 것은 `appId`의 플랫폼 세그먼트뿐이다(네이티브 SDK가 형식을 본다).
  /// 에뮬레이터 라우팅을 결정하는 것은 [projectId]다.
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return _web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return _apple;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        // 데스크톱은 Firebase가 web 옵션 형태를 그대로 받는다.
        return _web;
    }
  }

  /// 웹·데스크톱용 데모 옵션. `authDomain`은 에뮬레이터가 로컬에서 응답하므로 `localhost`.
  static const FirebaseOptions _web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: projectId,
    authDomain: 'localhost',
    storageBucket: '$projectId.appspot.com',
  );

  /// Android용 데모 옵션. 호스트 PC 접근은 `10.0.2.2`로 나가며, 그 판정은
  /// `firebase_bootstrap.dart`의 `resolveEmulatorHost()`가 한다.
  static const FirebaseOptions _android = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: projectId,
    storageBucket: '$projectId.appspot.com',
  );

  /// iOS·macOS용 데모 옵션. `iosBundleId`는 네이티브 SDK가 형식을 보므로 채워 둔다.
  static const FirebaseOptions _apple = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: projectId,
    storageBucket: '$projectId.appspot.com',
    iosBundleId: 'com.example.keepcon',
  );
}
