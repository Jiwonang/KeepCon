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
/// [MobileScannerPlatform.instance]가 공개 setter라 **가짜 플랫폼을 꽂아 인식 결과를
/// 밀어 넣을 수 있다.** 카메라 없이도 `_onDetect`가 실제로 호출되므로, 위 경고가
/// 가리키는 사고를 여기서 재현해 막는다.
///
/// - ✅ 인식 결과에서 쓸 바코드를 고르는 규칙 (여러 개·빈 값·공백만·null 섞임)
/// - ✅ `_onDetect`가 그 선별을 **실제로 쓰는지**(배선) — 함수만 고정하면 호출부가
///   `barcodes.first`로 되돌아가도 초록불이다
/// - ✅ `route.isCurrent` — 닫는 중에 인식돼도 아래 화면이 살아남는지
/// - ✅ 화면이 카메라 없이도 뜨고 기본 요소를 그리는지
/// - ⚠️ `_handled` 중복 pop 가드는 **도달은 되지만 단독으로 무는 테스트를 만들지
///   못했다.** 실측상 중복 pop을 실제로 막는 것은 `route.isCurrent` 쪽이고
///   `_handled`는 중복된 방어다(그 가드만 제거해도 아래 테스트가 전부 통과한다 —
///   `sync: true` 스트림으로 같은 턴에 세 프레임을 밀어도 마찬가지). 즉 127행 주석이
///   보호를 `_handled`에 돌리는 것은 실측과 다르다. 피해가 나는 입력을 찾지 못해
///   가드는 그대로 둔다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/widgets/barcode_scanner_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
// 배럴에 없는 유일한 것. **이걸 상속해야** 패키지의 debug 전용 비동기 경계가 살아나
// `initState` 중 `setState` 어서션을 피한다(`MobileScannerPlatform`을 직접 상속하면
// 그 경계가 없어 어서션을 `takeException()`으로 삼켜야 하고, 그러면 진짜 예외까지
// 가려진다). `implementation_imports` 린트가 꺼져 있어 analyze는 통과한다.
import 'package:mobile_scanner/src/method_channel/mobile_scanner_method_channel.dart';

/// 카메라 대신 인식 결과를 손으로 밀어 넣는 가짜 플랫폼.
class _FakeScannerPlatform extends MethodChannelMobileScanner {
  final StreamController<BarcodeCapture?> _barcodes =
      StreamController<BarcodeCapture?>.broadcast();

  void emit(BarcodeCapture capture) => _barcodes.add(capture);

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream<TorchState>.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream<double>.empty();

  @override
  Widget buildCameraView() => const ColoredBox(color: Color(0xFF000000));

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    await Future<void>.delayed(Duration.zero);
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      numberOfCameras: 1,
      size: Size(1920, 1080),
      initialDeviceOrientation: DeviceOrientation.portraitUp,
    );
  }

  @override
  Future<void> stop({bool force = false}) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> updateScanWindow(Rect? window) async {}
}

/// `rawValue`만 다른 최소 [Barcode].
Barcode _barcode(String? raw) => Barcode(rawValue: raw);

/// [Barcode] 목록만 담은 최소 [BarcodeCapture].
BarcodeCapture _capture(List<String?> raws) =>
    BarcodeCapture(barcodes: raws.map(_barcode).toList());

void main() {
  /// 가짜 플랫폼은 **모든 그룹에** 설치한다.
  ///
  /// [MobileScannerPlatform.instance]는 전역이라, 한 그룹에만 설치하면 그 그룹이
  /// 남긴 상태에 다른 그룹이 의존한다 — 단독 실행하면 진짜 플랫폼을 쓰고, 전체
  /// 실행하면 순서에 따라 결과가 달라진다. 매번 새 인스턴스로 덮어 그 의존을 끊는다.
  late _FakeScannerPlatform fake;

  setUp(() {
    fake = _FakeScannerPlatform();
    MobileScannerPlatform.instance = fake;
  });

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

  group('_onDetect — 가짜 플랫폼으로 인식 결과를 밀어 넣는다', () {
    /// 앞에 쓸 수 없는 것이 섞인 프레임 — **선별이 실제로 돌아야** 통과한다.
    ///
    /// 유효값 하나만 담은 프레임으로는 `barcodes.first.rawValue` 뮤테이션과
    /// 구별되지 않는다. 잡음을 섞는 것이 이 픽스처의 요점이다.
    BarcodeCapture noisy(String raw) => BarcodeCapture(
          barcodes: <Barcode>[
            const Barcode(),
            const Barcode(rawValue: ''),
            const Barcode(rawValue: '   '),
            Barcode(rawValue: raw),
          ],
        );

    Future<GlobalKey<NavigatorState>> pumpHost(WidgetTester tester) async {
      final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Center(child: Text('아래 화면'))),
        ),
      );
      return nav;
    }

    testWidgets('인식 결과를 그대로 pop한다 — _onDetect가 선별 로직을 실제로 쓴다',
        (WidgetTester tester) async {
      // **배선을 고정한다.** 함수만 단위 테스트하면 호출부가 `barcodes.first`로
      // 되돌아가도 전부 초록불이다 — 화면에 유효한 바코드가 떠 있는데 스캐너가
      // 영원히 계속 스캔하는 상태가 되는데도.
      final GlobalKey<NavigatorState> nav = await pumpHost(tester);
      BarcodeScanResult? result;

      unawaited(
        nav.currentState!
            .push<BarcodeScanResult>(
              MaterialPageRoute<BarcodeScanResult>(
                builder: (_) => const BarcodeScannerScreen(),
              ),
            )
            .then((BarcodeScanResult? r) => result = r),
      );
      await tester.pumpAndSettle();

      fake.emit(noisy('8801234567890'));
      await tester.pumpAndSettle();

      expect(result?.barcode, '8801234567890');
      expect(find.text('아래 화면'), findsOneWidget);
    });

    testWidgets('같은 바코드가 연달아 인식돼도 뒤 화면은 살아 있다', (WidgetTester tester) async {
      // 파일 헤더가 인용한 그 사고다 — pop이 여러 번 실행되면 ScanPage까지 닫힌다.
      final GlobalKey<NavigatorState> nav = await pumpHost(tester);

      unawaited(
        nav.currentState!.push<BarcodeScanResult>(
          MaterialPageRoute<BarcodeScanResult>(
            builder: (_) => const BarcodeScannerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      fake
        ..emit(noisy('8801234567890'))
        ..emit(noisy('8801234567890'))
        ..emit(noisy('8801234567890'));
      await tester.pumpAndSettle();

      expect(
        find.text('아래 화면'),
        findsOneWidget,
        reason: '중복 pop으로 뒤 화면까지 닫히면 안 된다',
      );
    });

    testWidgets('닫는 중에 인식되면 결과를 버린다 — route.isCurrent',
        (WidgetTester tester) async {
      // mounted만으로는 부족한 이유가 여기 있다 — pop된 라우트도 exit 애니메이션
      // 동안 mounted로 남아 있어, 그때 pop하면 아래 화면까지 닫힌다.
      final GlobalKey<NavigatorState> nav = await pumpHost(tester);

      unawaited(
        nav.currentState!.push<BarcodeScanResult>(
          MaterialPageRoute<BarcodeScanResult>(
            builder: (_) => const BarcodeScannerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 50));

      fake.emit(noisy('8801234567890'));
      await tester.pumpAndSettle();

      expect(
        find.text('아래 화면'),
        findsOneWidget,
        reason: '닫는 중 인식이 아래 화면까지 닫으면 안 된다',
      );
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
      // `find.byType(IconButton)`으로 세지 않는다 — 이 테스트는 `home:`으로 띄워
      // BackButton이 없지만, 훗날 라우트 push 형태로 바꾸면 그 단언이 BackButton을
      // 세면서 **조용히 무의미해진다.** 툴팁으로 플래시 버튼 자체를 짚는다.
      expect(find.byTooltip('플래시 켜기'), findsOneWidget);
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
