// 비밀번호 찾기 화면 — 스팸함 안내가 보이는지 고정한다.
//
// 안내 문구가 이 화면의 산출물이다(메일 자체는 Firebase가 보낸다). Firebase
// 기본 발신자로 나간 메일이 Gmail 스팸함에 격리되는 것을 dev에서 재현했고,
// 사용자에게는 "메일이 안 왔다"로 보인다 — 문구가 지워지면 그 혼선이 돌아온다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepcon/features/auth/reset_password_page.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authRepositoryProvider
            .overrideWithValue(InMemoryAuthRepository(initialUser: null)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ResetPasswordPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('안내 문구가 스팸함 확인을 알려 준다', (WidgetTester tester) async {
    await _pump(tester);

    expect(
      find.textContaining('스팸함'),
      findsOneWidget,
      reason: '메일 미수신 문의의 실제 원인이 스팸 격리였다 — 안내에서 빠지면 안 된다',
    );
  });

  testWidgets('발송 성공 스낵바도 스팸함을 언급한다', (WidgetTester tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'a@b.com');
    await tester.tap(find.widgetWithText(ElevatedButton, '재설정 링크 보내기'));
    await tester.pump(); // 스낵바 등장

    expect(find.textContaining('스팸함까지'), findsOneWidget);
  });
}
