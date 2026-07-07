/// KeepCon 앱 진입점 (검증/데모 조립부).
///
/// 이 파일은 페이지가 아니라 **앱 조립부**다. contract/orchestrator 소유 영역으로,
/// 공유 계약의 조립 규칙(lib/shared/providers/repositories.dart 상단 문서)을 따른다:
/// - 단일 [ProviderScope]에서 scan·main·share가 **같은** [GifticonRepository] 인스턴스를 공유.
/// - auth는 mock([InMemoryAuthRepository])이 기본 `user-1`로 로그인된 상태를 제공.
/// - 테마는 공유 SSOT([AppTheme])를 사용하고, 라이트/다크 전환은 [themeModeProvider]가 관리
///   (기본 라이트, 설정에서 토글).
///
/// 데모 편의를 위해 시드 기프티콘 몇 개를 넣어, 실행 즉시 목록/정렬/통계를 확인할 수 있게 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/keepcon_shell.dart';
import 'shared/models/gifticon.dart';
import 'shared/providers/repositories.dart';
import 'shared/providers/theme_mode_provider.dart';
import 'shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'shared/theme/app_theme.dart';

void main() {
  final DateTime now = DateTime.now();

  // 데모 시드 — user-1 소유. 브랜드/카테고리/만료일/상태/가격을 다양하게 두어
  // 홈의 통계·정렬·카드(가격/D-day)를 바로 시연한다.
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

  runApp(
    ProviderScope(
      // 계약 조립 규칙: gifticonRepository는 앱 전체가 하나의 인스턴스를 공유하도록 주입.
      // auth는 기본 mock(user-1 로그인) 사용.
      overrides: <Override>[
        gifticonRepositoryProvider.overrideWithValue(sharedGifticonRepo),
      ],
      child: const KeepConApp(),
    ),
  );
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
      home: const KeepConShell(),
    );
  }
}
