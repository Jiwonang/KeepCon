// 마이페이지 계정 기능 위젯 테스트 — 프로필 편집·계정 삭제 배선 검증(in-memory).
//
// 프로필 카드 탭 → 표시 이름 변경이 카드에 반영되는지(반응형 스트림),
// 계정 관리 → 비밀번호 재확인 후 삭제/오류 안내가 계약대로 동작하는지 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/mypage/mypage_page.dart';
import 'package:keepcon/features/share/state/share_providers.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';

Widget _app(InMemoryAuthRepository repo, {List<Override> extra = const []}) =>
    ProviderScope(
      overrides: <Override>[
        authRepositoryProvider.overrideWithValue(repo),
        ...extra,
      ],
      child: const MaterialApp(home: MyPage()),
    );

/// 폰 크기 서피스로 페이지를 띄운다(기본 800x600은 UI에 좁아 오버플로).
Future<InMemoryAuthRepository> _pumpMyPage(
  WidgetTester tester, {
  List<Override> extra = const <Override>[],
}) async {
  final InMemoryAuthRepository repo = InMemoryAuthRepository();
  addTearDown(repo.dispose);
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_app(repo, extra: extra));
  await tester.pumpAndSettle();
  return repo;
}

/// 안읽음 점(9×9 원형 Container) 파인더 — 헤더 벨·행 아이콘의 뱃지 점을 찾는다.
/// (프로필 아바타도 원형이지만 60×60이라 크기 제약으로 구분된다.)
Finder _unreadDot() => find.byWidgetPredicate(
      (Widget w) =>
          w is Container &&
          w.constraints == const BoxConstraints.tightFor(width: 9, height: 9) &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle,
    );

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

  testWidgets('프리미엄 — 무료 플랜 표시, 업그레이드하면 프리미엄으로 바뀐다',
      (WidgetTester tester) async {
    await _pumpMyPage(tester);

    // 기본은 무료 플랜.
    expect(find.text('무료 플랜 이용 중'), findsOneWidget);

    // 다이얼로그 → 업그레이드.
    await tester.tap(find.text('프리미엄'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '프리미엄으로 업그레이드'));
    await tester.pumpAndSettle();

    // in-memory는 실동작: 행 부제와 스낵바가 갱신된다.
    expect(find.text('프리미엄 이용 중'), findsOneWidget);
    expect(find.text('프리미엄으로 업그레이드했어요.'), findsOneWidget);
  });

  testWidgets('알림 점 — 안읽음 0이면 꺼지고, 있으면 행·벨 양쪽에 켜진다',
      (WidgetTester tester) async {
    // 안읽음 0 (정본 카운트 provider를 직접 고정).
    await _pumpMyPage(tester, extra: <Override>[
      unreadNotificationCountProvider.overrideWithValue(0),
    ]);
    expect(find.text('알림'), findsOneWidget);
    expect(find.text('알림 설정'), findsOneWidget);
    expect(_unreadDot(), findsNothing);
  });

  testWidgets('알림 점 — 안읽음이 있으면 알림 행과 헤더 벨에 점이 켜진다',
      (WidgetTester tester) async {
    await _pumpMyPage(tester, extra: <Override>[
      unreadNotificationCountProvider.overrideWithValue(2),
    ]);
    // 헤더 벨 + '알림' 행 = 2개.
    expect(_unreadDot(), findsNWidgets(2));
  });
}
