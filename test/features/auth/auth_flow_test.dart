// AuthGate 통합 배선 테스트 — 로그인/회원가입 시 앱 셸로 전환되는지 검증(in-memory).
//
// 세션(AuthRepository)만 바뀌면 AuthGate가 로그인 화면 ↔ 앱 셸을 라우팅한다는
// 계약을 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepcon/app/auth_gate.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';

Widget _app() => ProviderScope(
      overrides: <Override>[
        // 로그아웃 상태로 시작해 로그인 플로우를 검증.
        authRepositoryProvider
            .overrideWithValue(InMemoryAuthRepository(initialUser: null)),
      ],
      child: const MaterialApp(home: AuthGate()),
    );

/// 폰 크기 서피스로 앱을 띄운다(기본 800x600은 셸 UI에 좁아 오버플로).
Future<void> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('로그아웃 상태에서 로그인하면 앱 셸(홈)로 진입한다', (WidgetTester tester) async {
    await _pumpApp(tester);

    // 로그인 화면.
    expect(find.widgetWithText(ElevatedButton, '로그인'), findsOneWidget);
    expect(find.text('우리집 기프티콘'), findsNothing);

    // 데모 기본 계정으로 로그인(이메일/비밀번호 순서).
    final Finder fields = find.byType(TextField);
    await tester.enterText(
        fields.at(0), InMemoryAuthRepository.defaultUser.email);
    await tester.enterText(
        fields.at(1), InMemoryAuthRepository.defaultPassword);
    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await tester.pumpAndSettle();

    // 세션이 생겨 AuthGate가 앱 셸(홈)로 전환.
    expect(find.text('우리집 기프티콘'), findsOneWidget);
  });

  testWidgets('잘못된 비밀번호면 로그인 화면에 머문다', (WidgetTester tester) async {
    await _pumpApp(tester);

    final Finder fields = find.byType(TextField);
    await tester.enterText(
        fields.at(0), InMemoryAuthRepository.defaultUser.email);
    await tester.enterText(fields.at(1), 'wrong-password');
    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await tester.pumpAndSettle();

    // 실패 → 홈 진입 안 함, 안내 스낵바 노출.
    expect(find.text('우리집 기프티콘'), findsNothing);
    expect(find.text('이메일 또는 비밀번호가 올바르지 않아요.'), findsOneWidget);
  });

  testWidgets('회원가입하면 앱 셸(홈)로 진입한다', (WidgetTester tester) async {
    await _pumpApp(tester);

    // 로그인 → 회원가입 이동.
    await tester.tap(find.widgetWithText(TextButton, '회원가입'));
    await tester.pumpAndSettle();

    // 닉네임/이메일/비밀번호/비밀번호확인.
    final Finder fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '새유저');
    await tester.enterText(fields.at(1), 'new@keepcon.app');
    await tester.enterText(fields.at(2), 'secret1');
    await tester.enterText(fields.at(3), 'secret1');
    await tester.tap(find.widgetWithText(ElevatedButton, '가입하기'));
    await tester.pumpAndSettle();

    // 가입 → 즉시 로그인 상태 → 홈 진입.
    expect(find.text('우리집 기프티콘'), findsOneWidget);
  });
}
