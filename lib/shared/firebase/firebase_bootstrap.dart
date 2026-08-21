/// KeepCon 공유 계약 — Firebase 부트스트랩 / provider 전환.
///
/// 이 파일은 "Firebase 백엔드로 전환하는 방법"을 함수+문서로 제공한다.
/// 조립부(`lib/main.dart`)만 호출한다 — 페이지는 Repository 인터페이스만 본다.
///
/// ---
/// ## 계약의 가치 시연
/// 페이지들은 [AuthRepository]/[GifticonRepository]/[ShareRepository] **인터페이스에만**
/// 의존한다. 따라서 백엔드 교체는 "새 구현체를 provider로 override" 하는 것만으로 끝난다 —
/// 페이지 코드는 단 한 줄도 바뀌지 않는다.
///
/// ---
/// ## 세 가지 Firebase 경로 ([FirebaseTarget]으로 분기)
///
/// | 경로 | 언제 | 프로젝트 | 데이터 |
/// |------|------|----------|--------|
/// | [FirebaseTarget.emulator] | **기본** — 혼자 하는 UI·로직 작업, 파괴적 테스트, 규칙 검증 | `demo-keepcon`(로컬) | 내 PC에 유지(`.emulator-local/`) |
/// | [FirebaseTarget.dev] | 여러 사람이 같은 그룹에 들어가는 **공유 시나리오** | `keepcon-dev` | 팀 공유. 언제든 통째로 밀어도 됨 |
/// | [FirebaseTarget.prod] | 시연·배포 확인 **전용** | `keepcon-ab660` | 실서비스. 함부로 건드리지 말 것 |
///
/// **에뮬레이터와 dev는 대체재가 아니라 역할이 다르다.**
/// 에뮬레이터는 각자 PC에 격리되어 있어 **팀원 A와 B가 같은 그룹에 들어갈 수 없다** —
/// KeepCon의 핵심인 그룹 공유(A가 공유 → B에게 보임 → B가 사용 → A에게 알림)를
/// 진짜 두 사람으로 검증하려면 공유 백엔드가 필요하고, 그게 dev 프로젝트다.
/// 반대로 "그룹 삭제·공유 취소" 같은 **파괴적 테스트나 보안 규칙 검증은 에뮬레이터에서** 한다 —
/// Firestore에는 브랜치도 롤백도 없어서, dev에서 지우면 남이 쓰던 데이터도 같이 사라진다.
///
/// dev 데이터가 지저분해지면 `tool/reset_dev.sh`로 통째로 비우고 다시 시작한다.
/// prod에는 그 스크립트가 동작하지 않도록 막혀 있다.
///
/// ---
/// ## 실행 방법 (조립부는 `lib/main.dart`가 dart-define으로 분기)
/// ```bash
/// # 기본(플래그 없음) = 에뮬레이터. 터미널 A에서 `bash tool/emulators.sh`를 먼저 띄운다.
/// flutter run -d chrome
///
/// # 팀 개발 — dev 프로젝트(keepcon-dev)
/// flutter run -d chrome --dart-define=USE_FIREBASE=true
///
/// # 시연·배포 확인 — 실서비스(keepcon-ab660). 플래그가 별도인 이유는 오타 한 번으로
/// # 실서비스 데이터를 건드리지 않게 하기 위해서다.
/// flutter run -d chrome --dart-define=USE_FIREBASE_PROD=true
///
/// # 백엔드 없는 in-memory 데모 (그룹 공유는 검증 불가)
/// flutter run -d chrome --dart-define=USE_DEMO=true
///
/// # Android 실기기 시연 — USB 연결 + USB 디버깅을 켜고 `-d chrome`만 빼면 된다.
/// # (에뮬레이터 대신 dev를 쓰는 이유는 [resolveEmulatorHost] 주석 참조)
/// flutter run --dart-define=USE_FIREBASE=true
/// ```
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 두 옵션 파일 모두 `flutterfire configure` 생성물이라 클래스명이 `DefaultFirebaseOptions`로
// 같다. 생성물을 손으로 고치면 재생성 때 날아가므로, 파일을 바꾸는 대신 prefix로 구분한다.
import '../../firebase_options.dart' as prod_options;
import '../../firebase_options_dev.dart' as dev_options;
import '../providers/invite_link_providers.dart';
import '../providers/repositories.dart';
import '../repositories/impl/firebase/firebase_auth_repository.dart';
import '../repositories/impl/firebase/firebase_gifticon_repository.dart';
import '../repositories/impl/firebase/firebase_share_repository.dart';
import 'demo_firebase_options.dart';

/// Auth 에뮬레이터 포트. **`firebase.json`의 `emulators.auth.port`와 일치해야 한다.**
const int kAuthEmulatorPort = 9099;

/// Firestore 에뮬레이터 포트. **`firebase.json`의 `emulators.firestore.port`와 일치해야 한다.**
const int kFirestoreEmulatorPort = 8080;

/// [isEmulatorReachable]이 두드려 보는 문서 경로. 실제로 존재할 필요는 없다 —
/// 에뮬레이터가 **응답을 하는지**만 본다(보안 규칙이 막아 주는 편이 오히려 정상).
///
/// 컬렉션 id에 `__이름__`(앞뒤 밑줄 두 개)을 쓰면 Firestore가 내부 예약어로 거부하므로
/// 절대 그 형태로 바꾸지 마라 — 자세한 사정은 [isEmulatorReachable] 문서 참조.
const String kHealthProbePath = 'health_probe/probe';

/// 에뮬레이터 연결을 이미 수행했는지. 중복 연결 시도(핫 리스타트)를 막는다.
bool _emulatorConnected = false;

/// 어느 Firebase 백엔드에 붙을지. 매직 불리언 대신 enum을 쓰는 이유는 경로가 셋으로
/// 늘면서 `useEmulator: false`가 "dev인지 prod인지" 구분할 수 없게 됐기 때문이다
/// (계약 규약: 상태·분기는 매직 값이 아니라 enum).
enum FirebaseTarget {
  /// 로컬 에뮬레이터(`demo-keepcon`). 계정·네트워크 불필요, 재시작하면 리셋.
  emulator,

  /// 팀 공유 개발 프로젝트(`keepcon-dev`). 여러 사람이 같은 그룹에 들어갈 수 있다.
  dev,

  /// 실서비스 프로젝트(`keepcon-ab660`). 시연·배포 확인 전용.
  prod;

  /// 이 대상이 쓰는 [FirebaseOptions].
  FirebaseOptions get options => switch (this) {
        FirebaseTarget.emulator => DemoFirebaseOptions.currentPlatform,
        FirebaseTarget.dev =>
          dev_options.DefaultFirebaseOptions.currentPlatform,
        FirebaseTarget.prod =>
          prod_options.DefaultFirebaseOptions.currentPlatform,
      };

  /// 로그·디버그 표시용 프로젝트 id.
  String get projectId => switch (this) {
        FirebaseTarget.emulator => 'demo-keepcon',
        FirebaseTarget.dev => 'keepcon-dev',
        FirebaseTarget.prod => 'keepcon-ab660',
      };
}

/// Firebase를 초기화하고, Repository provider를 Firebase 구현으로 교체하는
/// [Override] 목록을 만든다.
///
/// [target]이 [FirebaseTarget.emulator]면 초기화 직후 Auth/Firestore를 로컬
/// 에뮬레이터에 연결한다(실제 프로젝트도 계정도 불필요). 나머지 둘은 실제 백엔드에
/// 붙으며, **web·android가 구성돼 있다**(iOS·데스크톱은 미구성 — [UnsupportedError]).
///
/// 재생성할 일이 있으면 **프로젝트별로 `--out`을 명시해** 두 번 돌린다.
/// `--out`을 빼면 CLI가 기본값(`lib/firebase_options.dart` = 실서비스)에 쓰므로,
/// dev를 재생성한 한 번으로 실서비스 옵션이 dev 값으로 덮여 쓰인다:
/// ```bash
/// flutterfire configure --project=keepcon-dev    --platforms=android,web \
///   --android-package-name=com.keepcon.app \
///   --out=lib/firebase_options_dev.dart
/// flutterfire configure --project=keepcon-ab660  --platforms=android,web \
///   --android-package-name=com.keepcon.app \
///   --out=lib/firebase_options.dart
/// ```
///
/// ⚠️ **android의 `google-services.json`은 두지 않는다** — 그 파일이 있으면 네이티브가
/// [DEFAULT] FirebaseApp을 먼저 만들어 백엔드를 하나로 고정하고, 나머지 둘이
/// `[core/duplicate-app]`으로 죽는다. 두 플랫폼 모두 생성된 Dart 옵션만 쓴다.
/// (iOS를 되살릴 일이 생기면 `GoogleService-Info.plist`도 같은 이유로 두지 않는다.)
///
/// [emulatorHost]를 주면 에뮬레이터 호스트를 직접 지정한다(기본값은 플랫폼별 자동 판정 —
/// [resolveEmulatorHost] 참조).
///
/// 반환한 [Override] 목록을 `ProviderScope(overrides: ...)`에 그대로 넣으면,
/// 계약 SSOT provider가 Firebase 구현을 참조하게 된다. 페이지 코드는 변경 불필요.
Future<List<Override>> initFirebaseAndBuildOverrides({
  required FirebaseTarget target,
  String? emulatorHost,
}) async {
  await Firebase.initializeApp(options: target.options);

  if (target == FirebaseTarget.emulator) {
    await connectToEmulators(host: emulatorHost);
  } else {
    // 어느 백엔드에 붙었는지 콘솔에 남긴다 — dev인 줄 알고 prod를 만지는 사고를 막는다.
    debugPrint('KeepCon: Firebase 연결됨 (${target.name} — ${target.projectId})');
  }

  return <Override>[
    ...firebaseProviderOverrides(),
    // 초대 링크가 가리킬 곳은 백엔드마다 다르다 — 기본값이 `null`이라 **안 덮어쓰면
    // 어느 플랫폼에서도 링크가 만들어지지 않고**(데모의 의도된 상태다), 옛 코드처럼
    // prod로 고정하면 에뮬레이터·dev에서 실서비스 링크를 발급한다.
    inviteOriginProvider.overrideWithValue(inviteOriginFor(target)),
  ];
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

/// 에뮬레이터가 **실제로 떠 있는지** 확인한다.
///
/// [connectToEmulators]는 "요청을 이 주소로 보내라"고 SDK 설정만 바꿀 뿐, 그 주소에
/// 무언가 떠 있는지는 보지 않는다. 그래서 에뮬레이터를 띄우지 않은 채 실행하면 앱은
/// 멀쩡히 뜨고 **화면만 영원히 로딩 상태**가 된다 — 원인을 찾기 어려운 침묵 실패다.
/// 조립부가 이 함수로 먼저 확인해 안내 화면을 띄운다.
///
/// [GetOptions]에 `Source.server`를 주어 **캐시로 성공한 척하는 것을 막는다.**
/// `permission-denied`는 **연결 성공으로 친다** — 보안 규칙이 평가됐다는 건
/// 에뮬레이터가 요청을 받고 응답했다는 뜻이기 때문이다.
///
/// ⚠️ **프로브 경로에 `__이름__` 형태를 쓰지 마라.** Firestore는 앞뒤로 밑줄 두 개인
/// 컬렉션 id를 내부 예약어로 막아 두어(`invalid-argument: Collection id "__health__" is
/// invalid because it is reserved.`), 에뮬레이터가 멀쩡히 떠 있어도 요청이 거부된다.
/// 예전 경로 `__health__/probe`가 정확히 그랬고, 그래서 이 체크는 **항상 실패해**
/// 안내 화면이 늘 떴다. 실패를 통째로 삼키고 있었던 탓에 원인이 오래 안 보였다.
///
/// 실패하면 **사유를 반드시 로그로 남긴다.** 예전에는 `catch (_)`로 통째로 삼켜서,
/// 안내 화면이 떴을 때 "에뮬레이터가 정말 없는지, 요청 자체가 잘못됐는지"를 코드를
/// 고쳐 보기 전에는 구분할 수 없었다 — 위의 예약어 버그가 오래 숨어 있던 이유다.
/// 판정을 바꾸는 코드가 아니라 **틀렸을 때 그 사실이 드러나게 하는 코드**다.
Future<bool> isEmulatorReachable({
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    await FirebaseFirestore.instance
        .doc(kHealthProbePath)
        .get(const GetOptions(source: Source.server))
        .timeout(timeout);
    return true;
  } on FirebaseException catch (e) {
    if (e.code == 'permission-denied') return true;
    debugPrint(
      'KeepCon: 에뮬레이터 확인 실패 — FirebaseException(${e.code}): ${e.message}',
    );
    return false;
  } catch (e) {
    // 타임아웃·연결 거부 등. 에뮬레이터가 없다고 본다.
    debugPrint('KeepCon: 에뮬레이터 확인 실패 — $e');
    return false;
  }
}

/// 플랫폼별 에뮬레이터 호스트를 판정한다.
///
/// Android 에뮬레이터의 `localhost`는 **에뮬레이터 자신**을 가리키므로, 호스트 PC는
/// 특수 주소 `10.0.2.2`로 접근해야 한다. 그 외(web/데스크톱)는 루프백.
///
/// ## 왜 `localhost`가 아니라 `127.0.0.1`인가
/// 에뮬레이터는 **IPv4 루프백에만 바인딩한다**(`firebase.json`에 `emulators.*.host`가
/// 없을 때의 기본값 — `[::1]:8080`은 연결 자체가 거부된다). 그런데 Windows에서
/// `localhost`는 IPv6 `::1`로 먼저 해석되므로, 브라우저가 매 요청마다 IPv6를 시도했다가
/// 실패하고 IPv4로 되돌아온다. 실측으로 같은 요청이 `localhost` 327ms / `127.0.0.1` 12ms였다.
/// 동작은 하지만 부팅 직후처럼 빠듯한 구간에서 [isEmulatorReachable]의 여유를 갉아먹는다.
///
/// ⚠️ **USB로 연결한 Android 실기기는 이 기본값으로 닿지 않으며, 그 조합은 지원하지 않는다.**
/// `10.0.2.2`는 AVD의 가상 라우팅이라 실기기에는 그런 주소가 없다. [connectToEmulators]의
/// `host`에 PC 사설 IP를 넘겨 우회하려면 ①에뮬레이터를 LAN에 바인딩(`firebase.json`의
/// `emulators.*.host`) ②PC 방화벽 인바운드 허용 ③에뮬레이터가 평문 HTTP라
/// `networkSecurityConfig`로 cleartext 허용 — 셋을 다 손봐야 한다.
/// **실기기 시연은 dev 프로젝트를 써라**(`--dart-define=USE_FIREBASE=true`) — 설정이 없다.
String resolveEmulatorHost() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return '10.0.2.2';
  }
  return '127.0.0.1';
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
