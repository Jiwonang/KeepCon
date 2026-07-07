/// KeepCon — Firebase 옵션 **플레이스홀더 스텁**.
///
/// ⚠️ 이 파일은 손으로 작성한 임시 스텁이다. 실제 값은 절대 여기 손으로 채우지 마라.
///
/// ## 사용자가 해야 할 일 (이 파일을 덮어쓰는 방법)
/// 1. Firebase 콘솔(https://console.firebase.google.com)에서 프로젝트를 생성한다.
/// 2. FlutterFire CLI를 설치한다:
///    `dart pub global activate flutterfire_cli`
/// 3. 프로젝트 루트에서 실행한다:
///    `flutterfire configure`
///    → 이 명령이 **이 파일(lib/firebase_options.dart)을 실제 값으로 자동 생성·덮어쓴다.**
/// 4. Firebase 콘솔에서 Authentication과 Cloud Firestore를 활성화한다.
///
/// `flutterfire configure`를 실행하기 전까지는 [DefaultFirebaseOptions.currentPlatform]이
/// [UnimplementedError]를 던진다 — 이는 의도된 동작이다. 기본 실행 경로는 in-memory이므로
/// 이 스텁이 존재해도 앱은 정상 실행되며(이 파일을 초기화 경로에서 호출하지 않음), 컴파일도 깨지지 않는다.
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// FlutterFire가 생성하는 것과 동일한 API 형태의 플레이스홀더.
///
/// `flutterfire configure` 실행 시 이 클래스 전체가 실제 값으로 교체된다.
class DefaultFirebaseOptions {
  /// 현재 플랫폼용 [FirebaseOptions]를 반환한다.
  ///
  /// **스텁 동작:** [UnimplementedError]를 던진다. `flutterfire configure`를 실행하면
  /// 플랫폼별 실제 [FirebaseOptions]를 반환하도록 이 getter가 자동 생성된다.
  static FirebaseOptions get currentPlatform {
    throw UnimplementedError(
      'firebase_options.dart는 아직 구성되지 않았습니다. '
      '프로젝트 루트에서 `flutterfire configure`를 실행해 이 파일을 생성하세요. '
      '(자세한 절차는 파일 상단 주석 및 _workspace/01_contract_dependency_matrix.md 참조)',
    );
  }
}
