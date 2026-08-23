// 비밀번호 찾기 화면 — 스팸함 안내가 보이는지 고정한다.
//
// 안내 문구가 이 화면의 산출물이다(메일 자체는 Firebase가 보낸다). 문구가
// 지워지면 "메일이 안 온다"는 문의가 그대로 돌아온다.
//
// 로그인 화면에서 push해 들어간다 — 발송 성공 뒤 페이지를 pop하므로, home으로
// 직접 띄우면 maybePop()이 no-op이 되어 "pop 이후에도 안내가 남는가"라는
// 이 화면의 유일한 위험 구간이 검증되지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepcon/features/auth/login_page.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

Future<void> _pumpResetPage(WidgetTester tester) async {
  final InMemoryAuthRepository auth =
      InMemoryAuthRepository(initialUser: null);
  addTearDown(auth.dispose);
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authRepositoryProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const LoginPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(TextButton, '비밀번호 찾기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('안내 문구가 스팸함 확인을 알려 준다', (WidgetTester tester) async {
    await _pumpResetPage(tester);

    expect(
      find.textContaining('메일이 안 보이면 스팸함도 확인해 주세요.'),
      findsOneWidget,
      reason: '메일 미수신 문의의 실제 원인이 스팸 격리였다 — 안내에서 빠지면 안 된다',
    );
  });

  testWidgets('발송 성공 스낵바는 화면을 빠져나온 뒤에도 남는다',
      (WidgetTester tester) async {
    await _pumpResetPage(tester);

    await tester.enterText(find.byType(TextField), 'a@b.com');
    await tester.tap(find.widgetWithText(ElevatedButton, '재설정 링크 보내기'));
    await tester.pumpAndSettle();

    // 페이지는 pop돼 로그인 화면으로 돌아왔지만, 스낵바는 살아 있어야 한다.
    expect(find.widgetWithText(ElevatedButton, '재설정 링크 보내기'), findsNothing);
    expect(
      find.text('재설정 링크를 보냈어요. 스팸함도 확인해 주세요.'),
      findsOneWidget,
    );
  });
}
