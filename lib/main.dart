/// KeepCon 앱 진입점 (조립부).
///
/// 이 파일은 페이지가 아니라 **앱 조립부**다. 공유 계약의 조립 규칙
/// (lib/shared/providers/repositories.dart 상단 문서)을 따른다.
///
/// ## 백엔드 선택 (실행 시 결정)
/// - **기본(플래그 없음): 내 PC의 로컬 에뮬레이터.** 내가 만든 계정·데이터가
///   `.emulator-local/`에 유지된다(`tool/emulators.sh` 참조). 별도 터미널에서
///   에뮬레이터를 **먼저 띄워야** 하며, 안 떠 있으면 [EmulatorUnavailableApp]이
///   무엇을 해야 하는지 안내한다. 실제 Firebase 프로젝트도 계정도 필요 없다.
/// - `--dart-define=USE_FIREBASE=true`: **팀 개발 프로젝트**(`keepcon-dev`)로 실행.
///   팀원끼리 같은 그룹에 들어가 공유 시나리오를 검증할 때 쓴다. **팀 공유 데이터다.**
/// - `--dart-define=USE_FIREBASE_PROD=true`: **실서비스 프로젝트**(`keepcon-ab660`).
///   시연·배포 확인 전용이며, 플래그를 분리한 이유는 오타 한 번으로 실서비스 데이터를
///   건드리지 않게 하기 위해서다.
/// - `--dart-define=USE_DEMO=true`: **in-memory 데모** — 시드 기프티콘(user-1 소유)으로
///   즉시 목록/통계 시연. 백엔드가 아예 없어 준비물이 없지만, 데이터가 앱 프로세스
///   메모리에만 있어 **그룹 공유는 검증할 수 없다**(팀원은커녕 내 두 번째 창에도 안 보인다).
/// - `--dart-define=USE_FIREBASE_EMULATOR=true`: 기본값과 같다. 기본이 바뀌어도
///   에뮬레이터를 고정하고 싶을 때 명시적으로 쓴다.
///
/// dev·prod에 붙어 있으면 **화면 모서리에 배지**가 뜬다([_backendBanner]) — 콘솔 로그를
/// 보지 않아도 "지금 남의 데이터 위에 있다"는 걸 알 수 있어야 하기 때문이다.
///
/// 실제 백엔드(dev·prod)는 **web·android·ios**가 구성돼 있다(데스크톱은 미구성 — 초기화가
/// [UnsupportedError]로 실패한다). 어느 쪽도 시드가 없어 회원가입부터 해야 한다.
///
/// 두 Firebase 경로 모두 세션이 비어 있어 [AuthGate]가 로그인 화면부터 시작한다.
/// 경로 선택 근거(왜 팀 작업에는 에뮬레이터인가)는 `shared/firebase/firebase_bootstrap.dart` 참조.
///
/// ## 화면 진입
/// `home`은 [AuthGate] — 세션 유무에 따라 로그인/앱 셸을 라우팅한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/auth_gate.dart';
import 'app/deep_link_listener.dart';
import 'app/emulator_unavailable_page.dart';
import 'shared/firebase/firebase_bootstrap.dart';
import 'shared/models/gifticon.dart';
import 'shared/providers/repositories.dart';
import 'shared/providers/theme_mode_provider.dart';
import 'shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'shared/theme/app_theme.dart';

/// `--dart-define=USE_FIREBASE=true` → 팀 개발 프로젝트(`keepcon-dev`).
const bool _useFirebase = bool.fromEnvironment('USE_FIREBASE');

/// `--dart-define=USE_FIREBASE_PROD=true` → 실서비스 프로젝트(`keepcon-ab660`).
const bool _useProd = bool.fromEnvironment('USE_FIREBASE_PROD');

/// `--dart-define=USE_FIREBASE_EMULATOR=true` → Firebase + 로컬 에뮬레이터.
///
/// 에뮬레이터 경로는 Firebase 백엔드를 쓰는 것이므로 [_useFirebase]를 **함의한다**
/// (플래그 두 개를 같이 넘길 필요 없음).
const bool _useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

/// `--dart-define=USE_DEMO=true` → 백엔드 없는 in-memory 데모.
const bool _useDemo = bool.fromEnvironment('USE_DEMO');

/// 플래그 조합에서 백엔드를 결정한다. `null`이면 in-memory 데모.
///
/// 우선순위는 **안전한 쪽이 이긴다** — 여러 플래그를 같이 넘긴 실수 상황에서 공유·
/// 실서비스 데이터가 선택되는 일이 없도록 demo > emulator > dev > prod 순으로 판정한다.
///
/// ## 플래그가 하나도 없으면 왜 에뮬레이터인가
/// 기본값은 **"아무것도 정하지 않았을 때 일어나는 일"** 이고, 그건 대개 실수다.
/// 그러니 기본은 **남의 데이터에 닿을 수 없는 쪽**이어야 한다.
///
/// 팀 공유 dev를 기본으로 두면, `firebase_bootstrap.dart`가 "그룹 삭제·공유 취소 같은
/// 파괴적 테스트는 에뮬레이터에서 하라"고 규정해 놓고도 **플래그를 깜빡한 한 번으로
/// 남의 작업이 날아간다**(Firestore에는 롤백이 없다). 규정과 기본값이 어긋나면
/// 규정이 지는 쪽으로 사고가 난다.
///
/// in-memory 데모를 기본으로 두는 것도 답이 아니었다 — 안전하지만 KeepCon의 핵심인
/// **그룹 공유를 아예 검증할 수 없어**, "되는 줄 알았는데 팀원 그룹이 안 보인다"로
/// 헤매게 된다(그래서 한때 기본이 dev로 바뀌었다). 에뮬레이터는 진짜 Firebase 동작을
/// 쓰면서 PC별로 격리돼 있어 **두 요구를 동시에 만족하는 유일한 지점**이다.
FirebaseTarget? _resolveTarget() {
  if (_useDemo) return null;
  if (_useEmulator) return FirebaseTarget.emulator;
  if (_useFirebase) return FirebaseTarget.dev;
  if (_useProd) return FirebaseTarget.prod;
  return FirebaseTarget.emulator;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final FirebaseTarget? target = _resolveTarget();
  if (target == null) {
    runApp(ProviderScope(
      overrides: _inMemoryOverrides(),
      child: const KeepConApp(target: null),
    ));
    return;
  }

  final List<Override> overrides =
      await initFirebaseAndBuildOverrides(target: target);

  // 에뮬레이터는 사람이 별도 터미널에서 띄워야 한다. 안 띄운 채 실행하면 SDK는 요청을
  // localhost로 보내고 아무도 응답하지 않아 **화면이 영원히 로딩**이 된다. 앱은 멀쩡히
  // 뜨는데 아무것도 안 되는 상태라 원인을 찾기 어려우므로, 여기서 먼저 확인해 안내한다.
  if (target == FirebaseTarget.emulator && !await isEmulatorReachable()) {
    runApp(const EmulatorUnavailableApp());
    return;
  }

  runApp(ProviderScope(
    overrides: overrides,
    child: KeepConApp(target: target),
  ));
}

/// in-memory 데모 조립 — 시드 기프티콘(user-1 소유)으로 홈의 통계·정렬·카드를 바로 시연.
List<Override> _inMemoryOverrides() {
  final DateTime now = DateTime.now();
  final InMemoryGifticonRepository sharedGifticonRepo =
      InMemoryGifticonRepository(seed: <Gifticon>[
    Gifticon(
      id: 'seed-1',
      ownerId: 'user-1',
      brand: '스타벅스',
      productName: '아메리카노 T',
      category: '카페',
      barcode: '1234-5678-9012',
      price: 4500,
      expiryDate: now.add(const Duration(days: 5)),
      registeredAt: now.subtract(const Duration(days: 1)),
      status: GifticonStatus.available,
    ),
    Gifticon(
      id: 'seed-2',
      ownerId: 'user-1',
      brand: '배스킨라빈스',
      productName: '파인트 아이스크림',
      category: '디저트',
      price: 8900,
      expiryDate: now.add(const Duration(days: 2)),
      registeredAt: now.subtract(const Duration(days: 3)),
      status: GifticonStatus.available,
    ),
    Gifticon(
      id: 'seed-3',
      ownerId: 'user-1',
      brand: 'GS25',
      productName: '모바일 상품권 1만원',
      category: '편의점',
      price: 10000,
      expiryDate: now.add(const Duration(days: 40)),
      registeredAt: now.subtract(const Duration(hours: 6)),
      status: GifticonStatus.available,
    ),
    Gifticon(
      id: 'seed-4',
      ownerId: 'user-1',
      brand: 'CU',
      productName: '도시락 교환권',
      category: '편의점',
      price: 4800,
      expiryDate: now.subtract(const Duration(days: 1)),
      registeredAt: now.subtract(const Duration(days: 10)),
      status: GifticonStatus.expired,
    ),
    Gifticon(
      id: 'seed-5',
      ownerId: 'user-1',
      brand: '교보문고',
      productName: '도서 상품권 3만원',
      category: '도서',
      price: 30000,
      expiryDate: now.add(const Duration(days: 100)),
      registeredAt: now.subtract(const Duration(days: 5)),
      status: GifticonStatus.used,
    ),
  ]);

  // 계약 조립 규칙: gifticonRepository는 앱 전체가 하나의 인스턴스를 공유하도록 주입.
  // auth는 기본 mock(user-1 로그인) 사용.
  return <Override>[
    gifticonRepositoryProvider.overrideWithValue(sharedGifticonRepo),
  ];
}

/// KeepCon 루트 앱. 공유 테마(SSOT)를 쓰고, [themeModeProvider]로 라이트/다크를 전환한다.
class KeepConApp extends ConsumerWidget {
  const KeepConApp({super.key, required this.target});

  /// 지금 붙어 있는 백엔드. `null`이면 in-memory 데모.
  ///
  /// 화면 배지([_backendBanner])에만 쓴다 — 데이터 접근은 provider override가 담당한다.
  final FirebaseTarget? target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'KeepCon',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      builder: (BuildContext context, Widget? child) =>
          _backendBanner(child, target),
      // 딥링크 수신은 **인증 게이트 바깥**에 둔다 — 초대 링크로 앱을 처음 여는 사용자는
      // 아직 로그인 전이다. 목적지를 버스에 실어 두면 로그인 후 셸이 소비한다.
      home: const DeepLinkListener(child: AuthGate()),
    );
  }
}

/// 공유·실서비스 백엔드에 붙어 있으면 화면 모서리에 배지를 얹는다.
///
/// 콘솔 로그(`KeepCon: Firebase 연결됨 …`)만으로는 부족하다 — 로그는 스크롤되어 사라지고
/// 아무도 계속 보지 않는다. **"지금 남의 데이터 위에 있다"는 사실은 화면에 남아 있어야**
/// 파괴적 동작을 하기 전에 눈에 들어온다.
///
/// 에뮬레이터·데모는 표시하지 않는다. 안전한 기본 상태에까지 배지를 붙이면 늘 떠 있는
/// 장식이 되어, 정작 dev·prod에서 떴을 때 아무도 알아채지 못한다.
Widget _backendBanner(Widget? child, FirebaseTarget? target) {
  final Widget content = child ?? const SizedBox.shrink();
  final (String, Color)? badge = switch (target) {
    FirebaseTarget.prod => ('실서비스', Colors.red),
    FirebaseTarget.dev => ('공유 dev', Colors.orange),
    FirebaseTarget.emulator || null => null,
  };
  if (badge == null) return content;
  return Banner(
    message: badge.$1,
    location: BannerLocation.topEnd,
    color: badge.$2,
    child: content,
  );
}
