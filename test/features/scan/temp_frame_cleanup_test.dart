/// 카메라 스캔 프레임 임시 디렉터리 정리(`cleanupTempFrameDir`)의 단위 테스트.
///
/// 정리가 실제로 도는 `_openForm`은 카메라 플러그인을 타서 위젯 테스트로
/// 통째로 지날 수 없다(`scan_form_screen_test.dart` doc — "예외는 카메라·갤러리
/// 도착이다"). 그래서 정리만 떼어 낸 순수 함수를 여기서 못박는다 — 이 테스트가
/// 없으면 정리 로직 전체가 커버리지 0으로 CI를 지나간다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/scan_page.dart';

void main() {
  group('cleanupTempFrameDir', () {
    test('createTemp로 만든 디렉터리를 내용째 지운다', () async {
      final Directory dir =
          await Directory.systemTemp.createTemp('keepcon_scan_test');
      await File('${dir.path}/frame.jpg').writeAsBytes(<int>[1, 2, 3]);

      await cleanupTempFrameDir(dir);

      expect(dir.existsSync(), isFalse);
    });

    test('null이면 던지지 않는다 — 카메라 외 경로·createTemp 전 실패', () async {
      await expectLater(cleanupTempFrameDir(null), completes);
    });

    test('이미 지워진 디렉터리를 넘겨도 던지지 않는다 — 실패를 삼키는 계약', () async {
      final Directory dir =
          await Directory.systemTemp.createTemp('keepcon_scan_test');
      await dir.delete(recursive: true);

      await expectLater(cleanupTempFrameDir(dir), completes);
    });
  });
}
