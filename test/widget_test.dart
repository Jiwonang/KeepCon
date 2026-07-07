// KeepCon 스모크 테스트.
//
// 앱이 정상 조립되어 메인 페이지(나의 기프티콘)가 렌더되고, 시드된 기프티콘이
// 목록에 표시되는지 확인한다. scan→main 공유 인스턴스 조립이 깨지면 여기서 잡힌다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepcon/features/main/main_page.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

void main() {
  testWidgets('메인 페이지가 시드된 기프티콘을 표시한다', (WidgetTester tester) async {
    final now = DateTime.now();
    final repo = InMemoryGifticonRepository(seed: <Gifticon>[
      Gifticon(
        id: 'seed-1',
        ownerId: 'user-1',
        brand: '스타벅스',
        productName: '아메리카노 T',
        category: '카페',
        price: 4500,
        expiryDate: now.add(const Duration(days: 5)),
        registeredAt: now,
        status: GifticonStatus.available,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          gifticonRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: MainPage()),
      ),
    );
    // 스트림/비동기 provider가 정착하도록 프레임을 진행한다.
    await tester.pumpAndSettle();

    expect(find.text('내 기프티콘'), findsOneWidget);
    expect(find.text('스타벅스'), findsWidgets);
  });
}
