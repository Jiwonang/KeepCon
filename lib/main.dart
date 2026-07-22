/// KeepCon 앱 진입점 (조립부).
///
/// 이 파일은 페이지가 아니라 **앱 조립부**다. 공유 계약의 조립 규칙
/// (lib/shared/providers/repositories.dart 상단 문서)을 따른다.
///
/// ## 백엔드 선택 (실행 시 결정)
/// - 기본(플래그 없음): **in-memory 데모** — 시드 기프티콘(user-1 소유)으로 즉시
///   목록/통계 시연. 기본 세션이 로그인된 상태라 [AuthGate]가 바로 앱 셸을 보여준다.
/// - `--dart-define=USE_FIREBASE_EMULATOR=true`: **Firebase + 로컬 에뮬레이터**
///   (권장 개발 경로). 별도 터미널에서 `firebase emulators:start`가 떠 있어야 한다.
///   실제 Firebase 프로젝트도 계정도 필요 없다.
/// - `--dart-define=USE_FIREBASE=true`: **실제 Firebase 프로젝트**(`keepcon-ab660`)로
///   실행. 추가 설정은 필요 없지만 시드가 없어 회원가입부터 해야 한다. web만 구성돼
///   있어 다른 플랫폼에서는 초기화가 [UnsupportedError]로 실패한다.
///
/// 두 Firebase 경로 모두 세션이 비어 있어 [AuthGate]가 로그인 화면부터 시작한다.
/// 경로 선택 근거(왜 팀 작업에는 에뮬레이터인가)는 `shared/firebase/firebase_bootstrap.dart` 참조.
///
/// ## 화면 진입
/// `home`은 [AuthGate] — 세션 유무에 따라 로그인/앱 셸을 라우팅한다.
/// 로그인·회원가입·로그아웃은 세션만 바꾸면 게이트가 화면을 전환한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/auth_gate.dart';
import 'shared/firebase/firebase_bootstrap.dart';
import 'shared/models/gifticon.dart';
import 'shared/providers/repositories.dart';
import 'shared/providers/theme_mode_provider.dart';
import 'shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'shared/theme/app_theme.dart';

/// `--dart-define=USE_FIREBASE=true` → 실제 Firebase 프로젝트.
const bool _useFirebase = bool.fromEnvironment('USE_FIREBASE');

/// `--dart-define=USE_FIREBASE_EMULATOR=true` → Firebase + 로컬 에뮬레이터.
///
/// 에뮬레이터 경로는 Firebase 백엔드를 쓰는 것이므로 [_useFirebase]를 **함의한다**
/// (플래그 두 개를 같이 넘길 필요 없음).
const bool _useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final List<Override> overrides = (_useFirebase || _useEmulator)
      ? await initFirebaseAndBuildOverrides(useEmulator: _useEmulator)
      : _inMemoryOverrides(); // 기본: in-memory 데모

  runApp(ProviderScope(overrides: overrides, child: const KeepConApp()));
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
  const KeepConApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'KeepCon',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: const AuthGate(),
    );
  }
}
