/// KeepCon 공유 계약 — Firebase 부트스트랩 / provider 전환.
///
/// 이 파일은 "Firebase 백엔드로 전환하는 방법"을 함수+문서로 제공한다.
/// **기본 실행 경로에서 호출하지 마라.** 기본은 in-memory 유지가 계약이다.
///
/// ---
/// ## 계약의 가치 시연
/// 페이지들은 [AuthRepository]/[GifticonRepository]/[ShareRepository] **인터페이스에만**
/// 의존한다. 따라서 백엔드 교체는 "새 구현체를 provider로 override" 하는 것만으로 끝난다 —
/// 페이지 코드는 단 한 줄도 바뀌지 않는다.
///
/// ---
/// ## 두 가지 Firebase 경로 (둘 다 여기서 분기)
///
/// | 경로 | 언제 | 옵션 출처 | 선행 준비 |
/// |------|------|-----------|-----------|
/// | **에뮬레이터**(권장, 기본 개발) | 일상 개발·테스트·팀 병렬 작업 | [DemoFirebaseOptions] (`demo-keepcon`) | `firebase emulators:start` 만 |
/// | **실제 프로젝트** | 실기기 시연·베타 배포 | [DefaultFirebaseOptions] (`lib/firebase_options.dart`) | 콘솔 프로젝트 생성 + `flutterfire configure` |
///
/// **팀 작업에는 에뮬레이터를 기본으로 쓴다.** 실제 프로젝트 하나를 여럿이 공유하면
/// Firestore에는 브랜치가 없어 서로의 데이터를 밟고(A가 지운 그룹을 B가 쓰는 중),
/// `flutterfire configure`를 각자 돌리면 `firebase_options.dart`가 갈라진다.
/// 에뮬레이터는 로컬 격리 + 재시작 리셋이라 그 두 문제가 모두 없고, 계정도 필요 없다.
///
/// ---
/// ## 실행 방법 (조립부는 `lib/main.dart`가 dart-define으로 분기)
/// ```bash
/// # 1) 에뮬레이터 (터미널 A)
/// firebase emulators:start
/// # 2) 앱 (터미널 B)
/// flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
///
/// # 실제 프로젝트 (flutterfire configure 선행)
/// flutter run -d chrome --dart-define=USE_FIREBASE=true
///
/// # 기본(플래그 없음) = in-memory 데모
/// flutter run -d chrome
/// ```
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';
import '../providers/repositories.dart';
import '../repositories/impl/firebase/firebase_auth_repository.dart';
import '../repositories/impl/firebase/firebase_gifticon_repository.dart';
import '../repositories/impl/firebase/firebase_share_repository.dart';
import 'demo_firebase_options.dart';

/// Auth 에뮬레이터 포트. **`firebase.json`의 `emulators.auth.port`와 일치해야 한다.**
const int kAuthEmulatorPort = 9099;

/// Firestore 에뮬레이터 포트. **`firebase.json`의 `emulators.firestore.port`와 일치해야 한다.**
const int kFirestoreEmulatorPort = 8080;

/// 에뮬레이터 연결을 이미 수행했는지. 중복 연결 시도(핫 리스타트)를 막는다.
bool _emulatorConnected = false;

/// Firebase를 초기화하고, Repository provider를 Firebase 구현으로 교체하는
/// [Override] 목록을 만든다.
///
/// - [useEmulator]가 `true`면 [DemoFirebaseOptions]로 초기화한 뒤 Auth/Firestore를
///   로컬 에뮬레이터에 연결한다. 실제 Firebase 프로젝트도 계정도 필요 없다.
/// - `false`면 [DefaultFirebaseOptions]를 쓴다 — `flutterfire configure`가 선행되지
///   않았으면 [UnimplementedError]가 난다(의도된 안내성 실패).
///
/// [emulatorHost]를 주면 에뮬레이터 호스트를 직접 지정한다(기본값은 플랫폼별 자동 판정 —
/// [resolveEmulatorHost] 참조).
///
/// 반환한 [Override] 목록을 `ProviderScope(overrides: ...)`에 그대로 넣으면,
/// 계약 SSOT provider가 Firebase 구현을 참조하게 된다. 페이지 코드는 변경 불필요.
Future<List<Override>> initFirebaseAndBuildOverrides({
  bool useEmulator = false,
  String? emulatorHost,
}) async {
  await Firebase.initializeApp(
    options: useEmulator
        ? DemoFirebaseOptions.currentPlatform
        : DefaultFirebaseOptions.currentPlatform,
  );

  if (useEmulator) {
    await connectToEmulators(host: emulatorHost);
  }

  return firebaseProviderOverrides();
}

/// Auth/Firestore SDK를 로컬 에뮬레이터로 연결한다.
///
/// **반드시 [Firebase.initializeApp] 직후, 첫 Auth/Firestore 호출 이전에** 불러야 한다 —
/// 한 번이라도 실제 요청이 나간 뒤에는 SDK 설정 변경이 거부된다.
///
/// 핫 리스타트 시 Dart 상태는 초기화되지만 네이티브/JS SDK의 연결 상태는 남아 있어
/// 재연결이 예외를 던질 수 있다. 그 경우는 "이미 연결됨"이므로 삼킨다.
Future<void> connectToEmulators({String? host}) async {
  if (_emulatorConnected) return;
  final String target = host ?? resolveEmulatorHost();
  try {
    FirebaseFirestore.instance
        .useFirestoreEmulator(target, kFirestoreEmulatorPort);
    await FirebaseAuth.instance.useAuthEmulator(target, kAuthEmulatorPort);
    _emulatorConnected = true;
    debugPrint(
      'KeepCon: Firebase 에뮬레이터 연결됨 '
      '($target — auth:$kAuthEmulatorPort, firestore:$kFirestoreEmulatorPort)',
    );
  } catch (e) {
    // 재연결 시도(핫 리스타트)는 무해하다. 최초 연결 실패라면 이후 Firebase 호출이
    // 실패하며 드러나므로, 여기서 앱을 죽이지 않고 경고만 남긴다.
    _emulatorConnected = true;
    debugPrint('KeepCon: 에뮬레이터 연결 건너뜀(이미 연결되었거나 실패): $e');
  }
}

/// 플랫폼별 에뮬레이터 호스트를 판정한다.
///
/// Android 에뮬레이터의 `localhost`는 **에뮬레이터 자신**을 가리키므로, 호스트 PC는
/// 특수 주소 `10.0.2.2`로 접근해야 한다. 그 외(web/데스크톱/iOS 시뮬레이터)는 `localhost`.
String resolveEmulatorHost() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return '10.0.2.2';
  }
  return 'localhost';
}

/// 이미 [Firebase.initializeApp]이 완료된 상태에서, provider override만 만든다.
///
/// (초기화를 호출부가 직접 제어하고 싶을 때 사용. 초기화 없이 이 override만 넣으면
///  Firebase 호출 시점에 예외가 난다.)
///
/// gifticonRepository는 scan·main·share가 **같은 단일 인스턴스**를 공유하도록
/// 하나만 생성해 주입한다(계약 SSOT 규칙 — 인스턴스 분기 방지). share는 그 auth·
/// gifticon 인스턴스를 그대로 주입받아, 사용 완료 시 원본 동기화가 같은 저장소에 반영된다.
List<Override> firebaseProviderOverrides() {
  final FirebaseAuthRepository authRepo = FirebaseAuthRepository();
  final FirebaseGifticonRepository gifticonRepo = FirebaseGifticonRepository();
  final FirebaseShareRepository shareRepo = FirebaseShareRepository(
    authRepository: authRepo,
    gifticonRepository: gifticonRepo,
  );

  return <Override>[
    authRepositoryProvider.overrideWithValue(authRepo),
    gifticonRepositoryProvider.overrideWithValue(gifticonRepo),
    shareRepositoryProvider.overrideWithValue(shareRepo),
  ];
}
