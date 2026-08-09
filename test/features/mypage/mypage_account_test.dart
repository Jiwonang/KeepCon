// 마이페이지 계정 기능 위젯 테스트 — 프로필 편집·계정 삭제 배선 검증(in-memory).
//
// 프로필 카드 탭 → 표시 이름 변경이 카드에 반영되는지(반응형 스트림),
// 계정 관리 → 비밀번호 재확인 후 삭제/오류 안내가 계약대로 동작하는지 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/mypage/mypage_page.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';

Widget _app(InMemoryAuthRepository repo) => ProviderScope(
      overrides: <Override>[
        authRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: MyPage()),
    );

/// 폰 크기 서피스로 페이지를 띄운다(기본 800x600은 UI에 좁아 오버플로).
Future<InMemoryAuthRepository> _pumpMyPage(WidgetTester tester) async {
  final InMemoryAuthRepository repo = InMemoryAuthRepository();
  addTearDown(repo.dispose);
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_app(repo));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('프로필 카드가 현재 사용자 이름/이메일을 표시한다', (WidgetTester tester) async {
    await _pumpMyPage(tester);

    expect(find.text(InMemoryAuthRepository.defaultUser.displayName),
        findsOneWidget);
    expect(find.text(InMemoryAuthRepository.defaultUser.email), findsOneWidget);
  });

  testWidgets('프로필 편집으로 표시 이름을 바꾸면 카드에 즉시 반영된다', (WidgetTester tester) async {
    final InMemoryAuthRepository repo = await _pumpMyPage(tester);

    // 프로필 카드 탭 → 편집 다이얼로그.
    await tester.tap(find.text(InMemoryAuthRepository.defaultUser.displayName));
    await tester.pumpAndSettle();
    expect(find.text('프로필 편집'), findsOneWidget);

    // 새 이름 입력 후 저장.
    await tester.enterText(find.byType(TextField), '새이름');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    // 저장소 반영 + 스트림 방출로 카드가 새 이름 표시.
    expect(repo.currentUser?.displayName, '새이름');
    expect(find.text('새이름'), findsOneWidget);
    expect(find.text('표시 이름을 변경했어요.'), findsOneWidget);
  });

  testWidgets('계정 삭제 — 비밀번호가 틀리면 안내하고 세션을 유지한다', (WidgetTester tester) async {
    final InMemoryAuthRepository repo = await _pumpMyPage(tester);

    await tester.tap(find.text('계정 관리'));
    await tester.pumpAndSettle();
    expect(find.text('계정 삭제'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(find.text('비밀번호가 올바르지 않아요.'), findsOneWidget);
    expect(repo.currentUser, isNotNull); // 세션 유지.
  });

  testWidgets('계정 삭제 — 올바른 비밀번호면 세션이 종료된다', (WidgetTester tester) async {
    final InMemoryAuthRepository repo = await _pumpMyPage(tester);

    await tester.tap(find.text('계정 관리'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField), InMemoryAuthRepository.defaultPassword);
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    // 세션 종료(실앱에선 AuthGate가 로그인 화면으로 전환).
    expect(repo.currentUser, isNull);
    expect(find.text('계정이 삭제됐어요.'), findsOneWidget);
  });

  testWidgets('앱 정보 — 버전과 라이선스 진입이 있는 다이얼로그를 띄운다', (WidgetTester tester) async {
    await _pumpMyPage(tester);

    await tester.tap(find.text('앱 정보'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutDialog), findsOneWidget);
    expect(find.text('0.1.0'), findsOneWidget); // 버전 표기.
  });
}
