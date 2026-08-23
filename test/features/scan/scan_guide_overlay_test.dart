/// scan — 카메라 스캔 가이드 오버레이([ScanGuideOverlay]) 위젯 테스트.
///
/// ## 이 파일이 있는 이유
///
/// 오버레이는 가이드 사각형 **바깥만** 어둡게 덮는다. 구멍을 좌표로 계산하지 않고
/// **같은 레이아웃 함수를 두 번 그려서**(한 번은 BlendMode 마스크, 한 번은 실제
/// 테두리) 정렬을 보장하는 구조다. 그 보장은 **코드 구조에만** 존재한다 —
/// 마스크 패스에서만 위젯 하나를 빼거나 넣으면 구멍이 조용히 어긋나는데
/// `flutter analyze`·`SSOT guard` 어느 것도 잡지 못한다.
///
/// 그래서 여기서 픽셀로 어서션한다. 오버레이는 카메라와 무관한 순수
/// [StatelessWidget]이라 위젯 테스트로 그릴 수 있다.
///
/// ## 검증 대상
/// 1. 가이드 프레임 **안**은 뚫려 있다(구멍).
/// 2. 프레임 **밖**은 스크림이 덮는다 — 화면 네 귀퉁이까지.
/// 3. 흔한 화면 크기·글꼴 배율에서 레이아웃이 넘치지 않는다(가로 모드 포함).
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/widgets/barcode_scanner_screen.dart';

void main() {
  const ValueKey<String> captureKey = ValueKey<String>('scan-guide-capture');

  Future<void> pumpOverlay(
    WidgetTester tester, {
    required Size size,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;

    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: RepaintBoundary(
                key: captureKey,
                child: ScanGuideOverlay(theme: Theme.of(context)),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('프레임 안은 뚫리고 바깥은 스크림이 덮는다', (WidgetTester tester) async {
    const Size size = Size(400, 800);
    await pumpOverlay(tester, size: size);

    final RenderRepaintBoundary boundary =
        tester.renderObject(find.byKey(captureKey));

    late ui.Image image;
    late Uint8List pixels;

    // toImage는 실제 래스터라이즈라 fake async 밖에서 돌려야 한다.
    await tester.runAsync(() async {
      image = await boundary.toImage();
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
    });

    int alphaAt(Offset p) {
      final int i = ((p.dy.toInt() * image.width) + p.dx.toInt()) * 4;
      return pixels[i + 3];
    }

    // 프레임 중심 = 구멍. 사각형 좌표는 find로 얻은 **실제 레이아웃**에서 가져온다
    // (여기서 좌표를 직접 계산하면 프로덕션 코드와 같은 실수를 테스트가 되풀이한다).
    final Rect frame = tester.getRect(find.byType(AspectRatio).last);

    expect(
      alphaAt(frame.center),
      0,
      reason: '가이드 프레임 안은 뚫려 있어야 한다(구멍)',
    );

    // 네 귀퉁이 = 스크림. 배경 DecoratedBox를 지우면 여기가 깨진다.
    const int expected = 153; // 0.6 * 255

    for (final Offset corner in <Offset>[
      const Offset(5, 5),
      Offset(size.width - 5, 5),
      Offset(5, size.height - 5),
      Offset(size.width - 5, size.height - 5),
    ]) {
      expect(
        alphaAt(corner),
        expected,
        reason: '프레임 바깥($corner)은 스크림이 덮어야 한다',
      );
    }
  });

  group('레이아웃이 넘치지 않는다', () {
    // 가로 모드 두 건은 회귀 방지다 — 상한을 걸기 전에는 640x360에서 112px,
    // 800x360에서 212px 넘쳤고, 마스크·실제 두 패스에서 각각 발생했다.
    const List<Size> sizes = <Size>[
      Size(360, 640), // 일반 세로
      Size(320, 568), // 작은 세로
      Size(280, 600), // 폴더블 커버 디스플레이
      Size(640, 360), // 가로
      Size(800, 360), // 넓은 가로
    ];

    for (final Size size in sizes) {
      for (final double scale in <double>[1.0, 2.0]) {
        testWidgets('$size @ 글꼴 $scale배', (WidgetTester tester) async {
          final List<String> errors = <String>[];
          final void Function(FlutterErrorDetails)? previous =
              FlutterError.onError;

          FlutterError.onError = (FlutterErrorDetails details) {
            errors.add(details.exceptionAsString());
          };

          try {
            await pumpOverlay(tester, size: size, textScale: scale);
          } finally {
            FlutterError.onError = previous;
          }

          expect(errors, isEmpty, reason: errors.join('\n'));
        });
      }
    }
  });
}
