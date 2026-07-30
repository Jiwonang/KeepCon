/// 카메라 실시간 바코드/QR 스캔 화면 (scan 페이지 로컬 위젯).
///
/// [ScanPage]의 카메라 경로가 이 화면을 push하고,
/// 사용자가 바코드를 비추면 인식된 rawValue를 결과로 pop한다.
///
/// 반환 계약(얇게 유지):
///
/// ```dart
/// final String? barcode = await Navigator.of(context).push<String>(
///   MaterialPageRoute<String>(builder: (_) => const BarcodeScannerScreen()),
/// );
/// ```
///
/// - 인식 성공 → 인식된 바코드 문자열
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
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      // 카메라 프리뷰 위에 얹히는 화면이므로 배경/전경을 어둡게 고정한다.
      backgroundColor: Colors.black,

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

      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // ─────────────────────────────────────────
          // 카메라 프리뷰 + 실시간 인식
          // ─────────────────────────────────────────
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,

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

          // ─────────────────────────────────────────
          // 스캔 가이드 오버레이
          // ─────────────────────────────────────────
          //
          // 프리뷰 조작(탭 포커스 등)을 가리지 않도록 IgnorePointer로 감싼다.
          IgnorePointer(
            child: _ScanGuideOverlay(theme: theme),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── 스캔 가이드 오버레이 ───────────────────────

/// 카메라 프리뷰 위에 얹는 스캔 가이드.
///
/// 사용자가 바코드를 어디에 맞춰야 하는지 알려주는 사각 프레임과
/// 하단 안내 문구를 표시한다.
///
/// 색·라운드는 공유 테마 토큰([AppRadii], `colorScheme.primary`)을 사용한다.
/// 단, 카메라 프리뷰 위에 놓이는 텍스트는 밝기와 무관하게 항상 흰색이어야 하므로
/// [ThemeTokensX.onDarkSurface]를 쓴다.
class _ScanGuideOverlay extends StatelessWidget {
  const _ScanGuideOverlay({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Color accent = theme.colorScheme.primary;
    final Color onDark = context.onDarkSurface;

    return SafeArea(
      child: Column(
        children: <Widget>[
          const Spacer(),

          // 바코드를 맞출 영역.
          //
          // 기프티콘 바코드는 가로로 길기 때문에 정사각형이 아닌
          // 가로가 긴 프레임으로 유도한다.
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: accent,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.panel),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 사용 안내 + 인식 실패 시 폴백 경로 안내.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: <Widget>[
                Text(
                  '바코드 또는 QR 코드를 사각형 안에 맞춰주세요',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: onDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '인식되지 않으면 화면을 닫고 직접 입력을 이용해 주세요.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: onDark.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),
        ],
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
      color: Colors.black,
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
              Text(
                reason,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: onDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '직접 입력으로도 기프티콘을 등록할 수 있어요.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onDark.withValues(alpha: 0.75),
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
