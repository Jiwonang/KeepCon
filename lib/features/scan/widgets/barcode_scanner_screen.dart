/// 카메라 실시간 바코드/QR 스캔 화면 (scan 페이지 로컬 위젯).
///
/// [ScanPage]의 카메라 경로가 이 화면을 push하고,
/// 사용자가 바코드를 비추면 인식된 rawValue를 결과로 pop한다.
///
/// 반환 계약(얇게 유지):
///
/// ```dart
/// final BarcodeScanResult? scan =
///     await Navigator.of(context).push<BarcodeScanResult>(
///   MaterialPageRoute<BarcodeScanResult>(
///     builder: (_) => const BarcodeScannerScreen(),
///   ),
/// );
/// ```
///
/// - 인식 성공 → [BarcodeScanResult] (바코드 + 인식된 순간의 프레임)
/// - 사용자가 닫음 / 오류로 종료 → `null`
///
/// 화면 자체는 "카메라를 띄워 문자열 하나를 돌려주는" 역할만 한다.
/// 인식 결과를 폼에 넣거나 저장하는 책임은 전부 [ScanPage] 쪽에 있다
/// (그래서 이 화면은 Riverpod 상태를 건드리지 않는다 — 테스트/재사용이 쉬워진다).
///
/// 왜 페이지 로컬인가 (CLAUDE.md '늦게 승격'):
/// 현재 소비자는 스캔 페이지 하나뿐이다. 두 번째 소비자가 실제로 생기면
/// 그때 `contract-architect`에게 공유 승격을 요청한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../shared/theme/theme_tokens.dart';
import '../util/keep_all_ko.dart';

/// [BarcodeScannerScreen]의 반환값.
///
/// 바코드만 돌려주면 폼의 나머지 칸(브랜드·상품명·금액·유효기간)을 사용자가 전부
/// 손으로 채워야 한다. 촬영 방식에서는 정지 이미지를 OCR해 그것들을 미리 채워
/// 줬으므로, 라이브 스캔으로 바꾸면서 그 편의가 사라지지 않도록 **인식된 순간의
/// 프레임**을 함께 돌려준다. 호출자가 이 프레임으로 OCR을 돌린다.
class BarcodeScanResult {
  const BarcodeScanResult({required this.barcode, this.imageBytes});

  /// 인식된 바코드 문자열.
  final String barcode;

  /// 바코드를 인식한 프레임의 **JPEG** 바이트.
  ///
  /// Android/iOS 모두 JPEG으로 인코딩되며 화면 방향에 맞춰 회전까지 보정돼 있다.
  /// 플랫폼이 프레임을 주지 않으면(웹 등) `null`이며, 그 경우 호출자는 OCR 없이
  /// 바코드만 쓰면 된다 — **없다고 해서 스캔이 실패한 것은 아니다.**
  final Uint8List? imageBytes;
}

/// 실시간 카메라 바코드/QR 스캔 화면.
///
/// 첫 유효 바코드를 감지하면 즉시 스캐너를 멈추고 결과를 pop한다.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  /// mobile_scanner 카메라 컨트롤러.
  ///
  /// - `formats`를 지정하지 않아 1D 바코드와 QR을 모두 인식한다
  ///   (기프티콘은 CODE128/EAN 계열과 QR이 섞여 있다).
  /// - `torchEnabled: false` — 플래시는 사용자가 상단 버튼으로 켠다.
  late final MobileScannerController _controller = MobileScannerController(
    torchEnabled: false,

    // 인식한 프레임을 돌려받아 OCR에 쓴다.
    //
    // 이 옵션이 **추가로** 물리는 비용은 JPEG 인코딩뿐이고, 그것도 네이티브
    // 구현이 **바코드가 검출된 프레임에서만** 수행한다(검출이 없으면 그 전에
    // 조기 반환). 프레임 분석 자체는 스캔의 본질이라 이 옵션과 무관하게 매
    // 프레임 돌아간다 — 즉 "스캔 대비 추가 부담"이 검출 순간에만 생긴다는 뜻이지,
    // 카메라가 노는 것은 아니다.
    returnImage: true,

    // Android 기본 분석 해상도는 **640x480**이라 바코드는 읽혀도 기프티콘의
    // 작은 글자(상품명·유효기간)는 OCR이 놓친다. 프레임을 OCR에 쓸 것이므로
    // 올려 잡는다. 기기가 지원하지 않으면 가장 가까운 해상도로 대체된다.
    //
    // ⚠️ mobile_scanner 7.4.0의 `MobileScannerController` 문서는 이 옵션을 **Android**
    // 전용이라고 적어 두었지만, 7.3.0부터 **web 구현도 이 값을 쓴다** — getUserMedia의
    // `ideal` 제약으로 넘겨 브라우저가 못 맞추면 가장 가까운 값으로 대체한다(미지정 시
    // 1920x1080이 기본). KeepCon이 구성한 두 플랫폼(web·android) 모두 이 값이 반영된다.
    cameraResolution: const Size(1920, 1080),
  );

  /// 이미 유효 바코드를 처리했는지 여부.
  ///
  /// mobile_scanner의 onDetect는 프레임마다 반복 호출될 수 있다.
  /// 이 가드가 없으면 같은 바코드로 pop이 여러 번 실행되어
  /// 뒤에 있던 화면까지 함께 닫히는 문제가 생긴다.
  bool _handled = false;

  @override
  void dispose() {
    // 카메라 리소스(네이티브)를 반드시 해제한다.
    _controller.dispose();

    super.dispose();
  }

  /// 바코드 감지 콜백.
  ///
  /// 흐름:
  ///
  /// 감지
  ///   ↓
  /// 중복 처리 가드([_handled])
  ///   ↓
  /// rawValue가 비어 있지 않은 첫 바코드 선택
  ///   ↓
  /// 햅틱 피드백(비동기, 기다리지 않음)
  ///   ↓
  /// Navigator.pop(rawValue)
  ///
  /// pop 전에 어떤 것도 await하지 않는 것이 중요하다:
  ///
  /// - 햅틱/카메라 정지를 기다리는 동안 사용자가 뒤로가기를 누르면
  ///   재개 시점의 pop이 이미 pop 중인 라우트 위에서 한 번 더 실행되어
  ///   아래 화면(ScanPage)까지 닫힌다.
  /// - 햅틱 채널이 예외를 던지는 환경(플러그인 미지원 등)에서
  ///   _handled=true만 남고 pop이 실행되지 않아 스캐너가 영구히 멈춘다.
  ///
  /// 카메라 정지는 별도로 호출하지 않는다 — 화면이 pop되면
  /// [dispose]의 `_controller.dispose()`가 카메라를 정리한다.
  void _onDetect(BarcodeCapture capture) {
    // 이미 처리했으면 이후 프레임은 전부 무시한다.
    if (_handled) return;

    // rawValue가 null이거나 빈 문자열인 인식 결과는 쓸 수 없다.
    //
    // displayValue가 아니라 rawValue를 사용한다:
    // 폼의 바코드 필드는 "실제 스캔되는 값"을 담아야 하고,
    // displayValue는 QR 등에서 사람이 읽기 좋게 가공된 값일 수 있다.
    String? value;

    for (final Barcode barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;

      if (raw != null && raw.trim().isNotEmpty) {
        value = raw;
        break;
      }
    }

    // 유효한 값이 없으면 계속 스캔한다(아직 처리한 것이 아니므로 가드도 세우지 않는다).
    if (value == null) return;

    // 사용자가 이미 뒤로가기로 화면을 닫는 중이면 결과를 버린다.
    //
    // mounted만으로는 부족하다 — pop된 라우트도 exit 애니메이션 동안
    // mounted로 남아 있어, 여기서 pop하면 ScanPage까지 닫힌다.
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;

    // 여기서부터는 되돌리지 않는다 — 가드를 먼저 세운다.
    _handled = true;

    // 인식됐다는 것을 촉각으로 알린다(카메라를 보고 있어 화면 변화를 놓칠 수 있다).
    //
    // 결과를 기다리지 않는다(위 doc 참조). 실패해도 무시한다 —
    // 피드백일 뿐 흐름에 영향을 주면 안 된다.
    unawaited(
      HapticFeedback.mediumImpact().catchError((Object _) {}),
    );

    // 인식 결과를 호출자(ScanPage)에게 즉시 돌려준다.
    //
    // 프레임([BarcodeCapture.image])은 있으면 같이 실어 보낸다. 없더라도 바코드는
    // 유효하므로 그대로 진행한다 — OCR은 덤이지 성공 조건이 아니다.
    Navigator.of(context).pop(
      BarcodeScanResult(barcode: value, imageBytes: capture.image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      // 카메라 프리뷰 위에 얹히는 화면이므로 배경을 어둡게 깐다.
      //
      // 하드코딩(Colors.black) 대신 테마의 scrim 토큰을 사용한다
      // (lib/features/** 색상 하드코딩 금지 규약).
      backgroundColor: theme.colorScheme.scrim,

      extendBodyBehindAppBar: true,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: context.onDarkSurface,
        title: const Text('바코드 스캔'),
        actions: <Widget>[
          // 플래시 토글.
          //
          // 컨트롤러가 ValueNotifier<MobileScannerState>이므로
          // torchState 변화를 그대로 구독한다.
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (
              BuildContext context,
              MobileScannerState state,
              Widget? child,
            ) {
              final TorchState torch = state.torchState;

              // 플래시가 없는 기기(전면 카메라 등)에서는 버튼을 비활성화한다.
              final bool unavailable = torch == TorchState.unavailable;

              return IconButton(
                tooltip: torch == TorchState.on ? '플래시 끄기' : '플래시 켜기',
                onPressed: unavailable ? null : _controller.toggleTorch,
                icon: Icon(
                  torch == TorchState.on ? Icons.flash_on : Icons.flash_off,
                  color: context.onDarkSurface.withValues(
                    alpha: unavailable ? 0.35 : 1,
                  ),
                ),
              );
            },
          ),
        ],
      ),

      // ─────────────────────────────────────────
      // 카메라 프리뷰 + 실시간 인식 + 스캔 가이드
      // ─────────────────────────────────────────
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,

        // 가이드 오버레이는 **프리뷰가 실제로 보일 때만** 그린다.
        //
        // Stack 형제로 두면 프리뷰 자리에 무엇이 오든 그 위에 얹힌다 —
        // 권한 거부 안내(errorBuilder)와 초기화 중 placeholder까지 스크림에
        // 덮여 어두워지고, 그 안내 문구 한복판을 구멍 경계와 테두리가 가로지른다.
        // mobile_scanner 7.4.0은 두 경로에서 overlayBuilder를 **아예 호출하지
        // 않으므로**(mobile_scanner.dart의 321·347 조기 반환 vs 355 프리뷰 경로),
        // 여기로 옮기는 것만으로 세 상태가 한 번에 정리된다.
        //
        // IgnorePointer는 그대로 둔다 — 패키지도 오버레이를 IgnorePointer로
        // 감싸지만 `ignoring: tapToFocus`이고 tapToFocus 기본값이 false라
        // 실제로는 아무것도 막지 않는다(같은 파일 29·399).
        overlayBuilder: (BuildContext context, BoxConstraints constraints) {
          return IgnorePointer(child: ScanGuideOverlay(theme: theme));
        },

        // 카메라를 열 수 없는 경우(권한 거부/미지원 등).
        //
        // mobile_scanner는 이 상황을 예외로 던지지 않고 errorBuilder로 알린다.
        // 그래서 여기서 사용자가 다음 행동(닫고 직접 입력)을 할 수 있게 안내한다.
        errorBuilder: (
          BuildContext context,
          MobileScannerException error,
        ) {
          return _ScannerError(error: error);
        },
      ),
    );
  }
}

// ─────────────────────── 스캔 가이드 오버레이 ───────────────────────

/// 가이드 사각형 **바깥**을 덮는 스크림의 불투명도.
///
/// 프리뷰가 비쳐 보일 만큼 옅으면서, 사각형 안쪽이 확실히 밝아 보여
/// 시선이 그리로 모이는 정도. 더 어둡게/밝게 하려면 이 값만 바꾸면 된다.
const double _kScanScrimOpacity = 0.6;

/// 가이드 프레임의 세로 위치 — 위쪽 여백과 아래쪽 여백의 비율.
///
/// 1:1이면 화면 정중앙이다. **아래쪽을 크게 잡을수록 프레임이 위로 올라간다.**
/// 정중앙보다 살짝 위가 겨누기 편해서 아래에 여유를 더 준다 — 기기를 들면
/// 손 위치상 화면 아래쪽이 몸 쪽으로 기울고, 안내 문구도 프레임 아래에 있어
/// 정중앙에 두면 둘이 화면 하단으로 몰려 보인다.
///
/// 더 올리려면 [_kGuideBottomFlex]를 키운다(5, 6 …).
const int _kGuideTopFlex = 3;
const int _kGuideBottomFlex = 4;

/// 가이드 프레임의 가로:세로 비율.
///
/// 기프티콘 바코드가 가로로 길어 정사각형이 아닌 가로가 긴 프레임으로 유도한다.
/// 프레임을 더 납작하게(가로로 길게) 하려면 값을 키운다.
///
/// **왜 바코드 모양(16:10)이 아니라 4:3인가.** 이 사각형은 잘라내는 영역이 아니라
/// "어디에 대세요"라는 안내일 뿐이다 — OCR은 가이드 안쪽이 아니라 **카메라 프레임
/// 전체**를 본다([ScanPage]가 `capture.image`를 통째로 ML Kit에 넘긴다).
///
/// 그래서 바코드 띠 모양으로 납작하게 잡으면 사용자가 바코드만 꽉 채우도록
/// 유도되고, 기기를 가까이 대면서 **브랜드·상품명·유효기간이 프레임 밖으로 나가
/// OCR 프리필이 빈다.** 기프티콘 한 장에 가까운 4:3이 그 글자들까지 함께 들어오게
/// 해 준다 — 바코드 인식은 어느 쪽이든 문제없다.
const double _kGuideAspectRatio = 4 / 3;

/// 가이드 프레임이 차지할 수 있는 최대 세로 비율.
///
/// [AspectRatio]는 세로 제약이 무한하면 **가로에 맞춰** 높이를 정한다(16:10이므로
/// 화면 폭의 0.625배). 가로 모드에서는 그 높이가 화면 높이를 넘겨 Column이
/// 오버플로하고, 프레임과 구멍의 아래 절반이 화면 밖으로 나간다
/// (640x360에서 112px, 800x360에서 212px — 마스크·실제 두 패스에서 각각).
///
/// 세로 모드에서는 자연 높이가 이 상한보다 작아 아무 영향이 없다
/// (폭 360이면 자연 높이 225 < 상한 288).
const double _kGuideMaxHeightFraction = 0.45;

/// 합성 마스크에서 '불투명한 자리'를 나타내는 피연산자.
///
/// [BlendMode.srcOut]·[BlendMode.dstOut]은 **알파만** 본다
/// (`src×(1−dstA)`, `dst×(1−srcA)`). 피연산자의 RGB는 결과에 들어가지 않으므로
/// 이 값은 **화면에 보이지 않는다** — 실제 보이는 색은 `colorScheme.scrim`이다.
/// 즉 '색상 하드코딩 금지' 규약이 말하는 '보이는 색'이 아니다.
/// 그 사정을 주석이 아니라 이름에 담아 두어, 리뷰에서 매번 다시 따지지 않게 한다.
const Color _kMaskOpaque = Color(0xFF000000);

/// 카메라 프리뷰 위에 얹는 스캔 가이드.
///
/// 사용자가 바코드를 어디에 맞춰야 하는지 알려주는 사각 프레임과
/// 하단 안내 문구를 표시한다.
///
/// 색·라운드는 공유 테마 토큰([AppRadii], `colorScheme.primary`)을 사용한다.
/// 단, 카메라 프리뷰 위에 놓이는 텍스트는 밝기와 무관하게 항상 흰색이어야 하므로
/// [ThemeTokensX.onDarkSurface]를 쓴다.
@visibleForTesting
class ScanGuideOverlay extends StatelessWidget {
  const ScanGuideOverlay({super.key, required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // 딤 레이어와 가이드 레이어를 **같은 레이아웃 코드**로 두 번 그린다.
    //
    // 구멍 좌표를 따로 계산하지 않는 것이 요점이다 — 여백·폰트 크기가 바뀌면
    // 계산한 좌표는 조용히 틀어져 구멍과 프레임이 어긋난다. [_guideLayout]을
    // 두 번 부르면 구멍이 언제나 프레임과 정확히 겹친다.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 스크림은 **정적**인데(테마가 바뀔 때만 변한다) [ColorFiltered]가 그릴 때마다
        // 화면 크기의 saveLayer를 뜬다. 그리고 `RenderColorFilter`는
        // `alwaysNeedsCompositing`만 정의하고 `isRepaintBoundary`는 오버라이드하지
        // 않으므로(기본값 false), 이 경계는 중복이 아니라 실제로 서브트리를 격리한다.
        //
        // 이 오버레이는 `overlayBuilder`로 들어가 있어 부모가
        // `ValueListenableBuilder<MobileScannerState>` 안쪽이다 — **플래시를 토글할
        // 때마다** 서브트리가 rebuild되므로 캐시가 실제로 값을 한다.
        // (카메라 프리뷰 갱신은 별도 합성 레이어라 여기에 영향을 주지 않는다)
        RepaintBoundary(child: _scrim(context)),
        _guideLayout(context, cutout: false),
      ],
    );
  }

  /// 가이드 사각형 **바깥만** 반투명하게 덮는 레이어.
  ///
  /// 구멍은 좌표가 아니라 합성 모드로 뚫는다. [BlendMode.srcOut]은 "자식이
  /// 불투명한 곳을 **제외한** 나머지"에 색을 칠하므로, 자식으로 가이드 사각형
  /// 자리에 불투명 박스만 놓아 주면 그 자리가 그대로 구멍이 된다.
  Widget _scrim(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        theme.colorScheme.scrim.withValues(alpha: _kScanScrimOpacity),
        BlendMode.srcOut,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // ⚠️ 지우지 말 것 — '합성의 바탕'이 아니라 **saveLayer 범위 확보용**이다.
          //
          // dstOut을 빈 레이어에 걸면 결과도 비어 있으므로, 이 박스는 합성 결과에
          // 아무것도 더하지 않는다 — 읽으면 죽은 코드로 보인다. 남겨 두는 이유는
          // [ColorFiltered]의 saveLayer 범위를 '실제로 그려진 내용'으로 잡는
          // 렌더러에서, 스크림이 프레임 사각형만큼만 칠해지는 것을 막기 위해서다.
          //
          // flutter test 래스터라이저에서는 이 박스가 있으나 없으나 픽셀이 같다
          // (2026-08-23 알파 측정) — 즉 **CI가 이 줄의 제거를 잡지 못한다.**
          // 실기기(Impeller) 확인 없이 지우지 말 것.
          const DecoratedBox(
            decoration: BoxDecoration(
              color: _kMaskOpaque,
              backgroundBlendMode: BlendMode.dstOut,
            ),
            child: SizedBox.expand(),
          ),
          _guideLayout(context, cutout: true),
        ],
      ),
    );
  }

  /// 가이드 프레임과 안내 문구의 레이아웃.
  ///
  /// [cutout]이 참이면 **구멍을 뚫기 위한 마스크**로 그린다 — 사각형은 테두리
  /// 대신 불투명하게 채우고, 문구는 자리(레이아웃)만 차지하고 그리지 않는다.
  /// 문구를 그대로 그리면 글자 모양대로 구멍이 뚫린다.
  Widget _guideLayout(BuildContext context, {required bool cutout}) {
    final Color accent = theme.colorScheme.primary;
    final Color onDark = context.onDarkSurface;

    // 사용 안내 + 인식 실패 시 폴백 경로 안내.
    //
    // 두 패스가 **같은 위젯**을 쓰도록 먼저 만들어 둔다 — 아래에서 마스크일 때만
    // Opacity로 감싼다(레이아웃에는 영향이 없어 세로 위치는 그대로 유지된다).
    final Widget caption = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: <Widget>[
          // 좌우 32씩 물린 가운데 정렬이라 좁은 기기에서는 두 문구 모두 접힌다.
          // 한글은 UAX #14상 음절 사이 어디서나 끊을 수 있어 '맞춰주 / 세요'처럼
          // 어절 한가운데가 갈라지는데, 가운데 정렬에서는 갈라진 조각이 줄마다
          // 다른 위치에 놓여 더 어수선해 보인다. [keepAllKo]로 끊어도 되는 자리를
          // 어절 경계로 제한한다(문구는 무변경).
          KeepAllText(
            '바코드 또는 QR 코드를 사각형 안에 맞춰주세요',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: onDark,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          KeepAllText(
            '인식되지 않으면 화면을 닫고 직접 입력을 이용해 주세요.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: onDark.withValues(alpha: 0.75),
              height: 1.45,
            ),
          ),
        ],
      ),
    );

    // 프레임 높이 상한은 **Column 바깥**에서 잰다.
    //
    // Column은 flex가 아닌 자식에게 세로 무한 제약을 주므로, Center 안쪽에서
    // LayoutBuilder를 쓰면 maxHeight가 infinity라 상한이 아무 일도 하지 않는다
    // (가로 모드 오버플로가 그대로 남는다 — 테스트가 이걸 잡았다).
    return SafeArea(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints viewport) {
          final double maxFrameHeight =
              viewport.maxHeight * _kGuideMaxHeightFraction;

          return Column(
            children: <Widget>[
              const Spacer(flex: _kGuideTopFlex),

              // 바코드를 맞출 영역.
              //
              // 기프티콘 바코드는 가로로 길기 때문에 정사각형이 아닌
              // 가로가 긴 프레임으로 유도한다.
              //
              // ⚠️ 좌우 여백은 [AspectRatio] **바깥**에 두어야 한다. 안쪽(자식의
              // margin)에 두면 AspectRatio는 자기 자신만 비율에 맞추고 그 안에서
              // 여백만큼 줄어든 테두리가 그려져, **실제로 보이는 사각형이 비율을
              // 벗어난다** — 폭 360에서 296x225(약 13.2:10), 폭 280에서
              // 216x175(약 12.3:10). 화면이 좁을수록 왜곡이 커진다.
              //
              // [AspectRatio]는 maxHeight가 유한하면 높이에 맞춰 폭을 다시
              // 계산하므로, 세로 상한을 걸어도 비율은 그대로 유지된다.
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxFrameHeight),
                    child: AspectRatio(
                      aspectRatio: _kGuideAspectRatio,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          // 마스크일 때는 이 영역이 '뚫릴 자리'이므로 꽉 채운다.
                          color: cutout ? _kMaskOpaque : null,
                          border: cutout
                              ? null
                              : Border.all(
                                  color: accent,
                                  width: 3,
                                ),
                          borderRadius: BorderRadius.circular(AppRadii.panel),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 마스크 패스에서만 Opacity로 감싼다 — 자리(레이아웃)는 그대로
              // 차지하므로 위 사각형의 세로 위치가 두 패스에서 동일하게 유지된다.
              //
              // 보이는 패스를 감싸지 않는 이유: `RenderOpacity`는 alpha가 0보다
              // 크면 **항상** 합성 레이어와 리페인트 경계를 만들지만
              // (`alwaysNeedsCompositing`), alpha가 0이면 paint에서 바로 반환한다.
              // 즉 `cutout ? 0 : 1`로 두면 비용이 붙는 쪽이 반대가 된다.
              if (cutout) Opacity(opacity: 0, child: caption) else caption,

              const Spacer(flex: _kGuideBottomFlex),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────── 카메라 오류 안내 ───────────────────────

/// 카메라를 열 수 없을 때 프리뷰 자리에 표시하는 안내.
///
/// 권한 거부/미지원은 사용자가 이 화면에서 해결할 수 없으므로,
/// 원인을 알려주고 직접 입력으로 폴백하도록 유도한다.
class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onDark = context.onDarkSurface;

    // 프리뷰 자리와 동일하게 테마의 scrim 토큰으로 어둡게 깐다
    // (색상 하드코딩 금지 규약).
    final Color backdrop = theme.colorScheme.scrim;

    // 사용자에게 보여줄 원인 문구.
    //
    // 패키지의 영문 message를 그대로 노출하지 않고
    // 우리 문구로 매핑한다(매직 스트링 비교 대신 enum 분기).
    final String reason = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        '카메라 권한이 거부되어 있어요.\n설정에서 카메라 접근을 허용해 주세요.',
      MobileScannerErrorCode.unsupported => '이 기기에서는 카메라 스캔을 사용할 수 없어요.',
      _ => '카메라를 시작할 수 없어요.',
    };

    return ColoredBox(
      color: backdrop,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.no_photography_outlined,
                color: onDark,
                size: 48,
              ),
              const SizedBox(height: 16),
              // [reason]은 권한 거부 경우에만 줄바꿈을 품는다. 줄 단위로 나눠
              // 적용해 그 의도된 줄바꿈은 그대로 두고, 각 줄 안에서만 어절을
              // 보호한다(다른 안내 문구와 같은 방식 — 가운데 정렬이라 갈라지면 더 어수선하다).
              Text(
                reason.split('\n').map(keepAllKo).join('\n'),
                // 원문을 낭독·탐색용으로 남긴다([KeepAllText]와 같은 이유).
                // 이쪽은 줄 단위로 조립하므로 래퍼를 쓰지 않는다.
                semanticsLabel: reason,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: onDark,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              KeepAllText(
                '직접 입력으로도 기프티콘을 등록할 수 있어요.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onDark.withValues(alpha: 0.75),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),

              // 결과 반환 계약을 얇게 유지하기 위해 null(취소)로 닫는다.
              // 이후 사용자는 스캔 화면에서 '직접 입력' 카드를 선택할 수 있다.
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: onDark,
                  side: BorderSide(color: onDark.withValues(alpha: 0.6)),
                ),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
