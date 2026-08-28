/// scan — 카메라 바코드 스캔 화면 테스트.
///
/// ## 이 파일이 있는 이유
///
/// `barcode_scanner_screen.dart`는 608줄인데 테스트가 **0건**이었다. 스캔 페이지에서
/// 두 번째로 큰 파일이고, 카메라라는 **가장 실패하기 쉬운 경로**를 담당한다.
///
/// 특히 인식 콜백에는 주석으로만 지켜지던 위험이 있었다 — 원문 그대로:
///
/// > 이 가드가 없으면 같은 바코드로 pop이 여러 번 실행되어
/// > **뒤에 있던 화면까지 함께 닫힌다**
///
/// ## 무엇을 덮고 무엇을 못 덮나
///
/// 카메라 자체는 위젯 테스트로 띄울 수 없다(플랫폼 채널). 그래서 **카메라 없이
/// 검증되는 부분**을 [firstUsableBarcode]로 분리해 그쪽을 직접 잰다.
///
/// - ✅ 인식 결과에서 쓸 바코드를 고르는 규칙 (여러 개·빈 값·공백만·null 섞임)
/// - ✅ 화면이 카메라 없이도 뜨고 기본 요소를 그리는지
/// - ❌ **미확인:** `_handled` 중복 pop 가드와 `route.isCurrent` 검사는 실제 pop이
///   걸린 상태를 만들어야 해서 여기서 못 덮는다. 그 둘이 위 주석이 경고하는 바로
///   그 지점이므로, 콜백을 손볼 때는 이 파일이 아니라 **실기기 확인**이 필요하다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/widgets/barcode_scanner_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// `rawValue`만 다른 최소 [Barcode].
Barcode _barcode(String? raw) => Barcode(rawValue: raw);

/// [Barcode] 목록만 담은 최소 [BarcodeCapture].
BarcodeCapture _capture(List<String?> raws) =>
    BarcodeCapture(barcodes: raws.map(_barcode).toList());

void main() {
  group('firstUsableBarcode — 인식 결과에서 쓸 값 고르기', () {
    test('빈 목록이면 null', () {
      expect(firstUsableBarcode(_capture(<String?>[])), isNull);
    });

    test('첫 유효값을 고른다', () {
      expect(
        firstUsableBarcode(_capture(<String?>['8801234567890', '9999'])),
        '8801234567890',
      );
    });

    test('null·빈 문자열은 건너뛰고 뒤의 유효값을 고른다', () {
      // 한 프레임에 여러 바코드가 잡히고 그중 값이 비어 있는 것이 섞이는 상황.
      // 앞의 쓸모없는 것 때문에 뒤의 진짜 바코드를 놓치면 사용자는 계속 비춰야 한다.
      expect(
        firstUsableBarcode(_capture(<String?>[null, '', '8801234567890'])),
        '8801234567890',
      );
    });

    test('공백뿐인 값도 버린다', () {
      // 저장되면 바코드가 있는 것처럼 보이지만 매장에서 못 쓴다.
      expect(firstUsableBarcode(_capture(<String?>['   ', '\t\n'])), isNull);
      expect(
        firstUsableBarcode(_capture(<String?>['  ', '8801234567890'])),
        '8801234567890',
      );
    });

    test('쓸 값이 하나도 없으면 null — 계속 스캔하라는 신호다', () {
      // 호출부는 이 null을 보고 `_handled` 가드를 **세우지 않는다.**
      // 여기서 빈 문자열 같은 것을 돌려주면 스캐너가 첫 프레임에 멈춰 버린다.
      expect(firstUsableBarcode(_capture(<String?>[null, '', '  '])), isNull);
    });

    test('값을 다듬지 않고 원본 그대로 돌려준다', () {
      // 판정(공백뿐이면 버림)과 값(원본 유지)을 분리한다 — 다듬기 규칙이 나중에
      // 바뀌어도 이 함수의 계약은 그대로다.
      expect(firstUsableBarcode(_capture(<String?>[' 880123 '])), ' 880123 ');
    });
  });

  group('BarcodeScannerScreen — 카메라 없이도 화면이 선다', () {
    testWidgets('제목과 플래시 버튼을 그린다', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: BarcodeScannerScreen()),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // 카메라가 없는 환경에서 예외로 죽지 않아야 한다 — 죽으면 실기기에서
      // 권한 거부·미지원 상황이 그대로 크래시가 된다.
      expect(tester.takeException(), isNull);

      expect(find.text('바코드 스캔'), findsOneWidget);
      expect(find.byType(IconButton), findsWidgets);
    });

    testWidgets('뒤로가기로 닫으면 결과 없이(null) 돌아간다', (WidgetTester tester) async {
      // 호출부(ScanPage)는 null을 "사용자가 인식 전에 닫았다"로 읽고 폼을 열지
      // 않는다. 여기서 빈 결과라도 돌려주면 빈 폼이 열린다.
      BarcodeScanResult? result;
      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<BarcodeScanResult>(
                    MaterialPageRoute<BarcodeScanResult>(
                      builder: (_) => const BarcodeScannerScreen(),
                    ),
                  );
                  popped = true;
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('바코드 스캔'), findsOneWidget);

      // AppBar의 뒤로가기.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(popped, isTrue, reason: '화면이 닫히지 않았다');
      expect(result, isNull);
    });
  });
}
