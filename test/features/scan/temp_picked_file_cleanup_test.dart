/// 갤러리 pick 사본 정리(`cleanupTempPickedFile`)와 그 소유권 판정
/// (`isPickedGalleryFileDisposable`)의 단위 테스트 (#178).
///
/// `_openForm`의 갤러리 분기는 image_picker 플러그인을 타서 위젯 테스트로
/// 통째로 지날 수 없다(`scan_form_screen_test.dart` doc) — 정리와 판정만
/// 떼어 낸 순수 함수를 여기서 못박는다. 특히 소유권 판정은 **틀리면 사용자
/// 사진을 지우는** 쪽으로 깨지므로(데스크톱은 원본 경로를 돌려준다) 플랫폼별로
/// 전부 고정한다.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/scan_page.dart';

void main() {
  group('cleanupTempPickedFile', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('keepcon_pick_test');
    });

    tearDown(() async {
      if (sandbox.existsSync()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('사본 파일을 지운다 — 담고 있던 디렉터리는 남긴다(플러그인 소유)', () async {
      final File copy = File('${sandbox.path}/picked.jpg');
      await copy.writeAsBytes(<int>[1, 2, 3]);

      await cleanupTempPickedFile(copy.path);

      expect(copy.existsSync(), isFalse);
      expect(sandbox.existsSync(), isTrue);
    });

    test('null이면 던지지 않는다 — 카메라·수동 경로, 원본을 돌려주는 플랫폼', () async {
      await expectLater(cleanupTempPickedFile(null), completes);
    });

    test('이미 없는 파일을 넘겨도 던지지 않는다 — 실패를 삼키는 계약', () async {
      await expectLater(
        cleanupTempPickedFile('${sandbox.path}/absent.jpg'),
        completes,
      );
    });

    test('디렉터리 경로를 넘기면 지우지 않고 던지지도 않는다 — recursive 없음이 안전장치', () async {
      final Directory pluginDir = Directory('${sandbox.path}/uuid-like');
      await pluginDir.create();
      await File('${pluginDir.path}/inside.jpg').writeAsBytes(<int>[9]);

      await expectLater(cleanupTempPickedFile(pluginDir.path), completes);

      expect(pluginDir.existsSync(), isTrue);
      expect(File('${pluginDir.path}/inside.jpg').existsSync(), isTrue);
    });
  });

  group('isPickedGalleryFileDisposable', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('Android — 플러그인이 앱 캐시에 사본을 만든다 → 지워도 된다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(isPickedGalleryFileDisposable(), isTrue);
    });

    test('iOS — tmp 사본 → 지워도 된다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(isPickedGalleryFileDisposable(), isTrue);
    });

    for (final TargetPlatform desktop in <TargetPlatform>[
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      test('$desktop — file_selector가 사용자 원본 경로를 돌려준다 → 지우면 안 된다', () {
        debugDefaultTargetPlatformOverride = desktop;
        expect(isPickedGalleryFileDisposable(), isFalse);
      });
    }
  });
}
