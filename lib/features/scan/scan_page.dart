/// 스캔/추가 페이지.
///
/// 카메라 스캔 / 갤러리 불러오기 / 수동 입력 세 가지 경로를 제공한다.
///
/// 세 경로는 최종적으로 모두 [GifticonForm]으로 이동한다.
/// 즉, 사용자가 어떤 방법으로 기프티콘을 추가하더라도
///
///   카메라
///      ↓
///   갤러리
///      ↓
///   직접 입력
///      ↓
///   GifticonForm
///      ↓
///   사용자가 확인/수정
///      ↓
///   GifticonFormController.submit()
///      ↓
///   GifticonRepository.addGifticon()
///
/// 동일한 저장 흐름을 사용한다.
///
/// route: [AppRoutes.scan]
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/models/group.dart';
import '../../shared/routes.dart';
import '../../shared/theme/theme_tokens.dart';
import 'services/gifticon_ocr_parser.dart';
import 'services/ml_kit_service.dart';
import 'state/gifticon_form_state.dart';
import 'state/scan_target_group_state.dart';
import 'widgets/barcode_scanner_screen.dart';
import 'widgets/gifticon_form.dart';
import 'widgets/scan_tokens.dart';

/// 스캔/추가 진입 화면.
///
/// 사용자는 세 가지 입력 경로 중 하나를 선택할 수 있다.
///
/// 1. 카메라로 스캔
/// 2. 갤러리에서 이미지 불러오기
/// 3. 직접 입력
///
/// 카메라와 갤러리는 인식 결과를 폼에 미리 채우고,
/// 사용자가 최종적으로 확인/수정한 뒤 저장한다.
///
/// 직접 입력은 빈 폼으로 바로 [GifticonForm]을 연다.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  /// route 등록용 상수.
  ///
  /// AppRoutes.scan과 동일한 값을 사용하여
  /// 라우팅 계약이 서로 어긋나지 않도록 한다.
  static const String routeName = AppRoutes.scan;

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

/// [ScanPage]의 State.
///
/// 추가 흐름 진행 여부([_busy])를 보관하기 위해
/// ConsumerStatefulWidget을 사용한다.
class _ScanPageState extends ConsumerState<ScanPage> {
  /// 현재 추가 흐름(이미지 선택/인식/폼)이 진행 중인지 여부.
  ///
  /// 다음 문제를 막는다.
  ///
  /// - 카드 연타 → pickImage 중복 호출
  ///   (image_picker의 PlatformException: already_active)
  /// - 카드 연타 → 폼 화면 중복 push
  /// - 인식 진행 중 다른 입력 경로 시작
  ///   → 늦게 도착한 인식 결과가 엉뚱한 폼에 주입되는 문제
  bool _busy = false;

  /// 저장 대상 그룹의 id. `null`이면 '내 지갑'(개인 보관 — 그룹 공유 없음).
  ///
  /// 세 입력 경로가 공유하는 선택값이므로 선택 위젯이 아니라 이 State가 소유한다
  /// ([_openForm]이 폼 세션에 넘겨야 한다).
  String? _targetGroupId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 큰 제목은 본문 헤더에서 직접 보여준다.
      // AppBar는 화면 상단의 뒤로가기 역할만 담당한다.
      appBar: AppBar(
        toolbarHeight: 44,
      ),

      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            6,
            20,
            28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 화면 제목 + 알림 아이콘 + 사용자 아바타.
              const _ScanHeader(),

              const SizedBox(height: 26),

              // ─────────────────────────────────────────
              // 1. 카메라 스캔
              // ─────────────────────────────────────────
              //
              // mobile_scanner로 실시간 인식이 연결된 경로다.
              //
              // 카메라 스캔 화면(BarcodeScannerScreen)
              // → 첫 유효 바코드 rawValue 반환
              // → 폼 상태에 바코드 프리필
              // → GifticonForm 화면 이동
              _SourceCard(
                icon: Icons.photo_camera_outlined,
                accent: Theme.of(context).colorScheme.primary,
                title: '카메라로 스캔',
                subtitle: '바코드 또는 QR 코드를 스캔해요',
                onTap: () => _openForm(ScanSource.camera),
              ),

              const SizedBox(height: 16),

              // ─────────────────────────────────────────
              // 2. 갤러리에서 이미지 불러오기
              // ─────────────────────────────────────────
              //
              // 현재 실제로 연결된 입력 경로다.
              //
              // 이미지 선택
              // → ML Kit OCR/바코드 인식
              // → OCR Parser로 데이터 정리
              // → 폼 상태에 결과 저장
              // → GifticonForm 화면 이동
              _SourceCard(
                icon: Icons.image_outlined,
                accent: ScanAccents.gallery,
                title: '갤러리에서 불러오기',
                subtitle: '저장된 이미지에서 불러와요',
                onTap: () => _openForm(ScanSource.gallery),
              ),

              const SizedBox(height: 16),

              // ─────────────────────────────────────────
              // 3. 직접 입력
              // ─────────────────────────────────────────
              //
              // 인식 과정 없이 빈 폼을 열어
              // 사용자가 직접 데이터를 입력한다.
              _SourceCard(
                icon: Icons.edit_outlined,
                accent: ScanAccents.manual,
                title: '직접 입력',
                subtitle: '코드 번호를 직접 입력해요',
                onTap: () => _openForm(ScanSource.manual),
              ),

              const SizedBox(height: 16),

              // 이미지 자동 인식 기능 안내.
              // 현재는 디자인 스캐폴드 역할만 한다.
              const _AiBanner(),

              const SizedBox(height: 26),

              // 저장할 그룹 선택 영역.
              //
              // 선택값(groupId)은 이 State가 소유하고, 저장 흐름 시작 시
              // 폼 세션으로 넘어간다(_openForm → startWith).
              _GroupSelector(
                selectedGroupId: _targetGroupId,
                onSelected: (String? groupId) {
                  setState(() {
                    _targetGroupId = groupId;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 선택한 입력 경로에 따라 적절한 추가 흐름을 시작한다.
  ///
  /// 모든 입력 경로는 먼저 [GifticonFormController.startWith]를 호출해
  /// 현재 입력 경로를 폼 상태에 기록한다.
  ///
  /// 이후:
  ///
  /// - manual → 바로 빈 폼 화면으로 이동
  /// - camera → 실시간 바코드 스캔 → 바코드 프리필
  /// - gallery → 이미지 선택 → OCR/바코드 인식 → 폼 프리필
  ///
  /// 흐름이 끝나면(폼이 닫히거나 취소/오류가 나면)
  /// [GifticonFormController.reset]으로 전역 폼 상태를 비워
  /// 다음 진입에 잔존값이 남지 않게 한다.
  Future<void> _openForm(ScanSource source) async {
    // 이미 다른 추가 흐름이 진행 중이면 무시한다.
    // (연타/중복 진입 방지 — [_busy] 문서 참조)
    if (_busy) return;

    _busy = true;

    final GifticonFormController controller =
        ref.read(gifticonFormControllerProvider.notifier);

    try {
      // 사용자가 선택한 입력 경로와 저장 대상 그룹을 폼 상태에 기록하고
      // 이전에 입력되어 있던 폼 상태를 초기화한다.
      //
      // 예:
      // ScanSource.gallery를 선택하면
      // 이후 폼 상태의 source도 gallery가 된다.
      //
      // 대상 그룹은 폼 진입 시점의 선택값으로 고정된다(저장 성공 후 이 그룹으로
      // shareGifticon이 호출된다 — GifticonFormController.submit 참조).
      controller.startWith(source, targetGroupId: _targetGroupId);

      // ─────────────────────────────────────────
      // 직접 입력
      // ─────────────────────────────────────────
      //
      // 직접 입력은 인식할 데이터가 없기 때문에
      // 초기화된 폼을 바로 열면 된다.
      if (source == ScanSource.manual) {
        if (!mounted) return;

        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const _GifticonFormScreen(),
          ),
        );

        return;
      }

      // ─────────────────────────────────────────
      // 카메라 실시간 스캔
      // ─────────────────────────────────────────
      //
      // 갤러리와 동일한 골격이지만 인식 주체가 다르다.
      //
      // - 갤러리: 정지 이미지 1장 → ML Kit OCR + 바코드
      // - 카메라: mobile_scanner가 프리뷰 프레임을 실시간 인식
      //
      // 카메라 경로는 프리뷰에서 바코드만 확정할 수 있으므로
      // (프레임 이미지 파일을 남기지 않는다) 브랜드/상품명/금액/유효기간은
      // 사용자가 폼에서 입력한다. 계약 필수 필드(brand/productName/price/
      // expiryDate)는 GifticonFormState.validate()가 저장 전에 강제한다.
      if (source == ScanSource.camera) {
        if (!mounted) return;

        // 스캔 화면은 "카메라를 띄워 문자열 하나를 돌려주는" 얇은 계약이다.
        //
        // - 인식 성공 → rawValue
        // - 닫기/권한 거부 등 → null
        final String? barcode = await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(
            builder: (_) => const BarcodeScannerScreen(),
          ),
        );

        // 사용자가 스캔을 취소했으면 폼을 열지 않고 그대로 머문다.
        // (finally에서 폼 상태를 비운다 — 갤러리 취소와 동일한 처리)
        if (barcode == null) return;

        // 인식된 바코드만 폼에 채운다.
        //
        // 나머지 필드는 프리필하지 않으므로 기존 빈 값이 유지되고,
        // 사용자가 폼에서 직접 입력한다(= 인식 실패 시 수동 입력 폴백).
        controller.prefillFromRecognition(
          barcode: barcode,
        );

        if (!mounted) return;

        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const _GifticonFormScreen(),
          ),
        );

        return;
      }

      // ─────────────────────────────────────────
      // 갤러리 이미지 선택
      // ─────────────────────────────────────────
      //
      // 정지 이미지 1장에서 OCR + 바코드를 함께 추출하는 경로다.
      // (카메라 경로는 위에서 바코드만 확정한다)
      //
      // pickImage부터 try 안에 두어, 갤러리 연타 시
      // image_picker가 던지는 PlatformException(already_active)도
      // 아래 catch에서 스낵바로 처리되게 한다.
      final ImagePicker picker = ImagePicker();

      // 시스템 갤러리를 열어 이미지를 선택한다.
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
      );

      // 사용자가 갤러리에서 선택을 취소하면
      // 아무 작업도 하지 않고 현재 화면에 그대로 머문다.
      // (finally에서 폼 상태를 비운다)
      if (pickedFile == null) return;

      if (!mounted) return;

      // ─────────────────────────────────────────
      // 1단계: XFile → File
      // ─────────────────────────────────────────
      //
      // image_picker가 반환하는 XFile을
      // Dart의 File 객체로 변환한다.
      final File imageFile = File(pickedFile.path);

      // ─────────────────────────────────────────
      // 2단계: File → ML Kit InputImage
      // ─────────────────────────────────────────
      //
      // Google ML Kit이 이미지를 분석할 수 있도록
      // InputImage 형태로 변환한다.
      final InputImage inputImage = InputImage.fromFile(
        imageFile,
      );

      // ─────────────────────────────────────────
      // 3단계: ML Kit 서비스 생성
      // ─────────────────────────────────────────
      //
      // OCR과 바코드 인식을 담당하는 서비스다.
      final MlKitService mlKitService = MlKitService();

      // ─────────────────────────────────────────
      // 4단계: OCR + 바코드 인식
      // ─────────────────────────────────────────
      //
      // 하나의 이미지에서
      //
      // - OCR 텍스트
      // - 바코드 값
      //
      // 을 동시에 추출한다.
      //
      // ML Kit이 사용하는 네이티브 리소스는 인식이 끝나면
      // 즉시 정리한다. (이전에는 폼 화면이 닫힐 때까지
      // 리소스를 붙잡고 있었다 — 이후 단계는 서비스를 쓰지 않는다)
      final MlKitScanResult result;
      try {
        result = await mlKitService.scan(inputImage);
      } finally {
        await mlKitService.dispose();
      }

      // ─────────────────────────────────────────
      // 5단계: OCR 텍스트 → 기프티콘 데이터 변환
      // ─────────────────────────────────────────
      //
      // ML Kit이 반환하는 OCR 결과는 단순 문자열이다.
      //
      // 예:
      // "스타벅스
      // 아이스 카페 아메리카노 T
      // 4,500원
      // 2026.12.31"
      //
      // GifticonOcrParser는 이 텍스트를 분석해
      // 브랜드 / 상품명 / 금액 / 유효기간 등의 데이터로 분리한다.
      const GifticonOcrParser parser = GifticonOcrParser();

      final GifticonOcrResult ocrResult = parser.parse(result.text);

      // ─────────────────────────────────────────
      // 디버깅용 로그 (debug 빌드에서만)
      // ─────────────────────────────────────────
      //
      // 바코드는 금전적 가치가 있는 값이므로
      // release 빌드의 기기 로그에 남지 않도록
      // 반드시 kDebugMode로 가드한다.
      //
      // (프리필 직후의 폼 상태는 prefillFromRecognition 내부에서
      //  '===== GifticonForm 상태 변경 ====='으로 로깅된다)
      if (kDebugMode) {
        // Parser에 전달되기 전 원본 OCR 문자열.
        debugPrint('===== ML Kit OCR 원본 =====');
        debugPrint(result.text);

        // Parser가 분리해 낸 값.
        debugPrint('===== OCR 파싱 결과 =====');
        debugPrint('브랜드명: ${ocrResult.brand}');
        debugPrint('상품명: ${ocrResult.productName}');
        debugPrint('금액: ${ocrResult.price}');
        debugPrint('유효기간: ${ocrResult.expiryDate}');

        // 바코드 인식 결과.
        debugPrint('===== ML Kit 바코드 =====');
        debugPrint(result.firstBarcodeValue ?? '바코드 없음');
      }

      // ─────────────────────────────────────────
      // 6단계: 인식 결과를 폼 상태에 저장
      // ─────────────────────────────────────────
      //
      // 여기서 중요한 점은
      //
      // OCR 결과를 Gifticon으로 바로 저장하지 않는다는 것이다.
      //
      // 먼저 GifticonFormController의 상태에 넣고,
      // 사용자가 폼 화면에서 결과를 확인/수정할 수 있도록 한다.
      //
      // 따라서 인식이 일부 실패해도
      // 사용자가 직접 수정하여 저장할 수 있다.
      controller.prefillFromRecognition(
        brand: ocrResult.brand,
        productName: ocrResult.productName,
        price: ocrResult.price,
        barcode: result.firstBarcodeValue,
        expiryDate: ocrResult.expiryDate,
        imagePath: pickedFile.path,
      );

      // 화면이 아직 살아있는지 확인한다.
      //
      // 비동기 OCR 작업 중 사용자가 화면을 떠났을 경우
      // context를 사용하면 문제가 발생할 수 있으므로 확인한다.
      if (!mounted) return;

      // ─────────────────────────────────────────
      // 7단계: 인식 결과 확인 폼으로 이동
      // ─────────────────────────────────────────
      //
      // 앞에서 prefillFromRecognition()으로 상태를 채웠기 때문에
      // GifticonForm 화면이 열리면 입력창에 OCR 결과가 표시된다.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const _GifticonFormScreen(),
        ),
      );
    } catch (e) {
      // 카메라 실행/이미지 선택/OCR/바코드 인식 과정에서
      // 예외가 발생한 경우 사용자에게 알려준다.
      //
      // 카메라 미지원·권한 거부는 mobile_scanner가 예외로 던지지 않고
      // 스캔 화면 내부의 errorBuilder로 안내하지만, 그 밖의 실패
      // (플랫폼 채널 오류 등)는 여기로 올라온다.
      if (!mounted) return;

      // 어떤 경로에서 실패했는지 문구를 맞춘다(매직 문자열 분기 대신 enum switch).
      final String what = switch (source) {
        ScanSource.camera => '카메라 스캔',
        ScanSource.gallery => '이미지 인식',
        ScanSource.manual => '입력 화면을 여는',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$what 중 오류가 발생했습니다: $e',
          ),
        ),
      );
    } finally {
      // 흐름 종료(폼 닫힘/취소/오류): 전역 폼 상태를 비운다.
      //
      // provider가 autoDispose가 아니므로 여기서 비우지 않으면
      // 바코드/이미지 경로 등이 앱 수명 동안 잔존한다.
      //
      // reset()은 세션 번호도 증가시켜, 아직 완료되지 않은
      // 이전 제출(submit)이 새 폼 상태를 덮어쓰지 못하게 한다.
      controller.reset();

      _busy = false;
    }
  }
}

// ─────────────────────────── 헤더 ───────────────────────────

/// 상단 헤더.
///
/// 홈 화면과 동일한 톤으로
///
/// [기프티콘 추가] + 알림 아이콘 + 사용자 아바타
///
/// 를 배치한다.
///
/// 현재 알림/아바타 기능은 정적 디자인 자리표시자다.
class _ScanHeader extends StatelessWidget {
  const _ScanHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: [
        // 제목이 남은 공간을 모두 차지하도록 Expanded를 사용한다.
        Expanded(
          child: Text(
            '기프티콘 추가',
            style: context.pageHeaderStyle,
          ),
        ),

        // 알림 벨 + 초록색 알림 표시 점.
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.notifications_none,
                color: scheme.onSurface,
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.surface,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 10),

        // 사용자 아바타.
        //
        // 현재는 로그인 사용자 정보를 연결하지 않고
        // "K"라는 이니셜을 정적으로 보여준다.
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.darkSurface,
            shape: BoxShape.circle,
          ),
          child: Text(
            'K',
            style: TextStyle(
              color: context.onDarkSurface,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────── 입력 경로 리치 카드 ───────────────────────

/// 입력 경로 선택 카드.
///
/// 각 카드에는
///
/// - 아이콘
/// - 제목
/// - 설명
/// - 오른쪽 화살표
///
/// 를 표시한다.
///
/// 실제 동작은 [onTap]에서 전달받는다.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(
        AppRadii.card,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          AppRadii.card,
        ),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 22,
          ),
          decoration: AppDecorations.softCard(
            scheme,
          ),
          child: Row(
            children: [
              // 입력 경로를 구분하기 위한 아이콘 타일.
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(
                    alpha: ScanAccents.tileTintAlpha,
                  ),
                  borderRadius: BorderRadius.circular(
                    AppRadii.button,
                  ),
                ),
                child: Icon(
                  icon,
                  color: accent,
                  size: 26,
                ),
              ),

              const SizedBox(width: 18),

              // 제목과 설명 영역.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.navTitleStyle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 카드를 누르면 다음 단계로 이동한다는 시각적 표시.
              Icon(
                Icons.chevron_right,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────── AI 안내 배너 (정적) ───────────────────────

/// 이미지 자동 인식 안내 배너.
///
/// 현재는 실제 동작을 수행하지 않는 디자인 스캐폴드다.
///
/// TODO(scan):
/// 향후 AI/OCR 기능이 확장되면
/// 이미지에서 브랜드, 상품명, 금액, 만료일 등을
/// 자동으로 정리해준다는 안내와 실제 기능을 연결할 수 있다.
class _AiBanner extends StatelessWidget {
  const _AiBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(
          AppRadii.panel,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            color: scheme.primary,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '이미지에서 브랜드와 만료일을\n자동으로 정리해요',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── 저장할 그룹 선택 ───────────────────────

/// 저장 대상 그룹 선택 그리드.
///
/// 첫 타일은 항상 '내 지갑'(개인 보관 — 그룹 공유 없음, groupId `null`)이고,
/// 이어서 계약에서 읽어온 **내 그룹**([scanTargetGroupsProvider])이 이모지·이름으로 붙는다.
///
/// 연동 방식(계약 무변경):
///
/// 정본 `myGroupsProvider`(lib/shared/providers — 내부에서
/// `ShareRepository.watchGroups(uid)` 구독) → scan 파생
/// `scanTargetGroupsProvider`(빈 목록 폴딩)  ← 목록
///   ↓ 사용자가 타일 선택 → groupId
/// `GifticonFormController.startWith(source, targetGroupId: groupId)`
///   ↓ 저장 버튼
/// `GifticonRepository.addGifticon(...)` → 성공 후
/// `ShareRepository.shareGifticon(groupId:, gifticon: saved)`
///
/// 즉 [Gifticon]에 groupId를 추가하지 않고, 그룹 소속은 share 도메인의 공유 항목으로만
/// 표현한다(등록 알림·1회 공유 불변식·markUsed 시 원본 동기화에 그대로 합류).
///
/// 선택 식별자는 index가 아니라 **groupId**다 — 스트림이 갱신돼 그룹 순서가 바뀌어도
/// 선택이 다른 그룹으로 옮겨가지 않는다. 그룹이 없거나(미로그인/로딩 포함) 목록이 비면
/// '내 지갑' 한 장만 보인다.
///
/// 선택된 groupId가 현재 목록에 없는 순간에는 어떤 타일도 선택으로 보이지 않는다.
/// 이 상태는 두 경로로 생긴다:
///
/// - **로딩 지연**(실서버 watchGroups가 아직 방출 전): 잠시 표시만 비어 보일 뿐
///   `_targetGroupId`는 살아 있어, 목록이 도착하면 선택 표시가 복원되고
///   그 사이 저장해도 선택한 그룹으로 정상 공유된다(데이터 정상, 표시만 일시 stale).
/// - **탈퇴/삭제로 실제 소멸**: 그 상태로 저장하면 공유 단계만 실패한다
///   (저장은 성공 — [GifticonFormController.submit]의 부분 실패 정책).
class _GroupSelector extends ConsumerWidget {
  const _GroupSelector({
    required this.selectedGroupId,
    required this.onSelected,
  });

  /// 현재 선택된 그룹 id. `null`이면 '내 지갑'.
  final String? selectedGroupId;

  /// 타일을 선택했을 때 호출한다. '내 지갑'은 `null`을 넘긴다.
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Group> groups = ref.watch(scanTargetGroupsProvider);

    // 첫 타일은 항상 개인 보관('내 지갑'), 이후가 실제 그룹이다.
    final List<_GroupTileData> tiles = <_GroupTileData>[
      const _GroupTileData(
        icon: Icons.account_balance_wallet_outlined,
        label: '내 지갑',
      ),
      for (final Group group in groups)
        _GroupTileData(
          groupId: group.id,
          emoji: group.emoji,
          label: group.name,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '저장할 그룹 선택',
          style: context.sectionTitleStyle,
        ),
        const SizedBox(height: 14),

        // 한 줄에 3개씩 같은 폭으로 배치한다.
        //
        // 그룹 수는 가변(0개~정원)이므로 고정 Row로는 4개 이상에서 타일이 짜부라진다.
        // 폭을 직접 계산해 Wrap에 넘기면, 3개까지는 기존 Row+Expanded와 동일한 폭이
        // 유지되고 그 이상은 다음 줄로 넘어간다.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const int perRow = 3;
            const double gap = 12;

            // floorToDouble: (w-24)/3을 그대로 쓰면 3개 합이 부동소수 오차로
            // maxWidth를 1ulp 초과할 수 있고, RenderWrap은 엄격 비교(>)라
            // 세 번째 타일이 다음 줄로 밀린다(특정 기기 폭에서 간헐 재현).
            //
            // clamp(0, …): web/데스크톱 창을 극단적으로 좁히면 계산이 음수가
            // 되어 SizedBox 어설션으로 크래시하므로 하한을 0으로 막는다.
            final double tileWidth =
                ((constraints.maxWidth - gap * (perRow - 1)) / perRow)
                    .floorToDouble()
                    .clamp(0.0, double.maxFinite);

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (final _GroupTileData data in tiles)
                  SizedBox(
                    width: tileWidth,
                    child: _GroupTile(
                      data: data,
                      selected: data.groupId == selectedGroupId,
                      onTap: () => onSelected(data.groupId),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 그룹 타일의 표시 데이터.
///
/// 아이콘 또는 이모지 중 하나를 사용한다.
class _GroupTileData {
  const _GroupTileData({
    this.groupId,
    this.icon,
    this.emoji,
    required this.label,
  }) : assert(
          icon != null || emoji != null,
          'icon 또는 emoji 중 하나는 필요',
        );

  /// 이 타일이 가리키는 그룹 id. `null`이면 '내 지갑'(그룹 공유 없음).
  final String? groupId;

  final IconData? icon;
  final String? emoji;
  final String label;
}

/// 그룹 선택 타일.
///
/// 선택된 그룹은 brand color 테두리와 전경색을 사용한다.
class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _GroupTileData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // 선택된 타일은 primary 색상을 사용한다.
    final Color fg = selected ? scheme.primary : scheme.onSurface;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(
        AppRadii.panel,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          AppRadii.panel,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 20,
            horizontal: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              AppRadii.panel,
            ),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outline.withValues(alpha: 0.25),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34,
                child: Center(
                  child: data.icon != null
                      ? Icon(
                          data.icon,
                          color: fg,
                          size: 32,
                        )
                      : Text(
                          data.emoji!,
                          style: const TextStyle(
                            fontSize: 30,
                            height: 1,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 폼 화면.
///
/// 세 입력 경로가 최종적으로 모두 이 화면으로 수렴한다.
///
/// 여기서 사용자는 OCR/바코드 인식 결과를 확인하고 수정하거나
/// 직접 데이터를 입력할 수 있다.
///
/// 저장 버튼을 누르면
///
/// GifticonForm
/// → GifticonFormController.submit()
/// → GifticonRepository.addGifticon()
///
/// 순서로 실제 저장이 진행된다.
class _GifticonFormScreen extends ConsumerWidget {
  const _GifticonFormScreen();

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {
    // 현재 입력 경로를 확인한다.
    //
    // 이 값에 따라 AppBar 제목을 다르게 표시한다.
    final source = ref.watch(
      gifticonFormControllerProvider.select(
        (s) => s.source,
      ),
    );

    final title = switch (source) {
      ScanSource.camera => '카메라 스캔 결과 확인',
      ScanSource.gallery => '갤러리 인식 결과 확인',
      ScanSource.manual => '기프티콘 직접 입력',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),

      // 실제 입력 UI는 GifticonForm에서 담당한다.
      //
      // ScanPage는 "어떤 경로로 폼에 들어왔는지"와
      // "인식 결과를 폼 상태에 넣는 것"까지만 담당한다.
      body: const GifticonForm(),
    );
  }
}
