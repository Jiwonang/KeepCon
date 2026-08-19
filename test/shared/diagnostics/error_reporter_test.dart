/// [ErrorReporter] 계약 테스트.
///
/// 이 계약이 지켜야 할 것은 두 가지다.
///
/// 1. **원본을 그대로 넘긴다.** 잡은 자리에서 문자열로 뭉개면(`'$e'`) 스택도 타입도 잃어,
///    개발자에게 남기는 의미가 사라진다.
/// 2. **절대 던지지 않는다.** 리포터가 터지면 원래 실패를 가린다 — 사용자 안내조차 못 띄운다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/diagnostics/error_reporter.dart';

void main() {
  group('DebugPrintErrorReporter', () {
    late List<String> printed;
    late DebugPrintCallback original;

    setUp(() {
      printed = <String>[];
      original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        printed.add(message ?? '');
      };
    });

    tearDown(() => debugPrint = original);

    test('컨텍스트 라벨과 원본 예외를 한 줄에 남긴다(로그에서 grep 되도록)', () {
      const DebugPrintErrorReporter().report(
        StateError('boom'),
        StackTrace.current,
        context: 'GroupDetailPage.leaveGroup',
      );

      expect(printed, isNotEmpty);
      expect(printed.first, contains('KeepCon:'));
      expect(printed.first, contains('GroupDetailPage.leaveGroup'));
      expect(printed.first, contains('boom'));
    });

    test('스택도 남긴다 — 원본만으로는 어디서 났는지 알 수 없다', () {
      const DebugPrintErrorReporter().report(
        Exception('x'),
        StackTrace.fromString('#0 someFrame (file.dart:1:1)'),
        context: 'ctx',
      );

      expect(printed.length, greaterThanOrEqualTo(2));
      expect(printed.last, contains('someFrame'));
    });

    test('Error도 그대로 받는다 — catch (_)가 삼키던 것이 정확히 이 부류다', () {
      // `catch (_)`는 Exception뿐 아니라 Error(TypeError 등)까지 잡는다. 그 프로그래밍
      // 결함이 사용자 문구 한 줄로 사라지는 것을 막는 것이 이 계약의 존재 이유다.
      const DebugPrintErrorReporter().report(
        ArgumentError('A document path must be a non-empty string'),
        StackTrace.current,
        context: 'ctx',
      );

      expect(printed.first, contains('non-empty string'));
    });

    test('includeMessage=false면 타입만 남긴다 — 예외 메시지에 식별자가 실린다', () {
      // 저장소 예외 메시지에는 초대 토큰·그룹 id가 그대로 들어 있고
      // (`Invite token expired: $inviteToken`), debugPrint는 release에서도
      // 플랫폼 로그로 나간다. 진단하려고 만든 경로가 유출 경로가 되면 안 된다.
      const DebugPrintErrorReporter(includeMessage: false).report(
        StateError('Invite token expired: 481923'),
        StackTrace.current,
        context: 'JoinGroupSheet.joinGroup',
      );

      expect(printed.first, isNot(contains('481923')));
      // 분류에 필요한 것(라벨·타입)은 그대로 남는다.
      expect(printed.first, contains('JoinGroupSheet.joinGroup'));
      expect(printed.first, contains('StateError'));
    });

    test('includeMessage=true면 메시지를 남긴다(debug 빌드 기본값)', () {
      const DebugPrintErrorReporter(includeMessage: true).report(
        StateError('Invite token expired: 481923'),
        StackTrace.current,
        context: 'ctx',
      );

      expect(printed.first, contains('481923'));
    });

    test('로깅이 실패해도 던지지 않는다 — 리포터가 원래 실패를 가리면 안 된다', () {
      debugPrint = (String? message, {int? wrapWidth}) {
        throw StateError('logging itself failed');
      };

      expect(
        () => const DebugPrintErrorReporter()
            .report(Exception('x'), StackTrace.current, context: 'ctx'),
        returnsNormally,
      );
    });
  });

  group('SilentErrorReporter', () {
    test('아무것도 하지 않고 던지지도 않는다', () {
      expect(
        () => const SilentErrorReporter()
            .report(Exception('x'), StackTrace.current, context: 'ctx'),
        returnsNormally,
      );
    });
  });
}
