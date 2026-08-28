/// 스캔/추가 페이지.
///
/// 카메라 스캔 / 갤러리 불러오기 / 수동 입력 세 가지 경로를 제공한다.
/// 세 경로는 최종적으로 모두 이 파일의 `_GifticonFormScreen`으로 이동한다.
///
/// route: [AppRoutes.scan]
library;

import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image_picker/image_picker.dart';

import 'package:keepcon/features/scan/services/gifticon_ocr_parser.dart';
import 'package:keepcon/features/scan/services/ml_kit_service.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/features/scan/util/keep_all_ko.dart';
import 'package:keepcon/features/scan/util/price_input_formatter.dart';
import 'package:keepcon/features/scan/widgets/barcode_scanner_screen.dart';
import 'package:keepcon/shared/diagnostics/report_handled_failure.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/theme/theme_tokens.dart';
import 'package:keepcon/shared/util/date_format.dart';

enum _GifticonGroup {
  cafe(label: '카페/음료', emoji: '☕', icon: null),
  chicken(label: '치킨/피자', emoji: '🍗', icon: null),
  convenience(label: '편의점', emoji: '🏪', icon: null),
  bakery(label: '베이커리', emoji: '🥐', icon: null),
  voucher(label: '상품권/금액권', emoji: '💳', icon: null),
  etc(label: '기타', emoji: null, icon: Icons.more_horiz_rounded);

  const _GifticonGroup({
    required this.label,
    required this.emoji,
    required this.icon,
  });

  final String label;
  final String? emoji;
  final IconData? icon;
}

/// 저장 결과 안내 다이얼로그(한도 도달·중복 등록)가 **공유하는 배치 규약.**
///
/// 둘은 같은 화면군에서 같은 역할을 하는 형제다. 값을 각자 들고 있으면 한쪽만
/// 고쳐졌을 때 여백·행간이 어긋나 폭이 들쭉날쭉해 보인다 — 한곳에 두어 그
/// 비대칭이 생길 여지를 없앤다.
abstract final class _ResultDialog {
  /// 좁은 화면일수록 좌우 여백이 본문 폭을 크게 깎는다 — 375px에서 기본
  /// 여백(40)이면 글자가 쓸 수 있는 폭이 250px 남짓이라 짧은 문장도 두 줄로
  /// 접힌다. 여백을 줄여 폭을 돌려주면 줄 수가 줄고, 줄 수가 줄면 읽기 쉽다.
  ///
  /// 넓은 화면에서는 기본값을 유지한다 — 거기서는 폭이 모자라지 않고, 문단이
  /// 지나치게 길어지면 오히려 시선이 줄을 놓친다.
  static EdgeInsets insetPadding(BuildContext context) => EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 400 ? 16 : 40,
        vertical: 24,
      );

  /// 흐린 보조 안내 스타일.
  ///
  /// 좁은 폭에서 두 줄로 접히는데, bodySmall 기본 행간으로는 접힌 두 줄이 서로
  /// 붙어 **어디까지가 한 문장인지** 보이지 않는다. 글자 크기는 그대로 두고
  /// 행간만 넓힌다.
  static TextStyle? mutedStyle(ThemeData theme) =>
      theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.45,
      );
}

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  _GifticonGroup _selectedGroup = _GifticonGroup.cafe;
  String? _selectedTargetGroupId; // null이면 내 지갑(개인 소장)
  bool _busy = false;

  /// 스캔 프레임(JPEG)을 임시 파일로 떨군다.
  ///
  /// ML Kit의 [InputImage.fromFilePath]와 폼의 이미지 미리보기([Image.file])가
  /// 모두 경로를 요구하므로, 바이트를 한 번만 파일로 만들어 둘 다에 쓴다.
  /// 갤러리 경로에서 image_picker가 만드는 임시 파일과 같은 성격이다.
  Future<File> _writeTempFrame(Uint8List bytes) async {
    final Directory dir = await Directory.systemTemp.createTemp('keepcon_scan');
    final File file = File('${dir.path}/frame.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _openForm(ScanSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });

    HapticFeedback.lightImpact();

    final controller = ref.read(gifticonFormControllerProvider.notifier);
    controller.startWith(source, targetGroupId: _selectedTargetGroupId);

    MlKitService? mlKitService;

    try {
      if (source == ScanSource.manual) {
        controller.setCategory(_selectedGroup.label);
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const _GifticonFormScreen(),
          ),
        );
        return;
      }

      // 카메라는 촬영 버튼 없이 "비추기만 해도" 인식되는 실시간 스캔을 쓴다.
      //
      // [BarcodeScannerScreen]이 첫 유효 바코드를 감지하는 즉시 pop하므로 사용자는
      // 셔터를 누를 필요가 없다. 그러면서도 인식된 **프레임**을 함께 받아 OCR을
      // 돌려, 촬영 방식이 해 주던 프리필(브랜드·상품명·금액·유효기간·이미지)을
      // 그대로 유지한다.
      if (source == ScanSource.camera) {
        controller.setCategory(_selectedGroup.label);
        if (!mounted) return;

        final BarcodeScanResult? scan =
            await Navigator.of(context).push<BarcodeScanResult>(
          MaterialPageRoute<BarcodeScanResult>(
            builder: (_) => const BarcodeScannerScreen(),
          ),
        );

        // 사용자가 인식 전에 닫았으면(null) 폼을 열지 않는다.
        if (scan == null || !mounted) return;

        controller.setBarcode(scan.barcode);

        // OCR은 **덤이다.** 프레임이 없거나 인식이 실패해도 바코드는 이미 유효하므로
        // 폼은 반드시 연다 — 여기서 예외가 새어 나가면 바깥 catch가 폼을 열지 않아,
        // 힘들게 잡은 바코드가 통째로 버려진다.
        final Uint8List? frame = scan.imageBytes;

        if (frame != null) {
          try {
            final File file = await _writeTempFrame(frame);

            mlKitService = MlKitService();
            final scanResult =
                await mlKitService.scan(InputImage.fromFilePath(file.path));
            final parsed = const GifticonOcrParser().parse(scanResult.text);

            controller.prefillFromRecognition(
              brand: parsed.brand,
              productName: parsed.productName,
              price: parsed.price,
              category: _selectedGroup.label,
              expiryDate: parsed.expiryDate,
              imagePath: file.path,
            );
          } catch (e) {
            // **여기는 보고 대상이 아니다.** OCR은 덤이고 바코드는 이미 유효하므로
            // 작업 자체는 성공한다 — 이건 실패가 아니라 성능 저하다. 프레임 품질에
            // 따라 흔히 일어나므로 [ErrorReporter]로 보내면 진짜 실패가 묻힌다.
            // 그래서 형제들과 달리 의도적으로 로그만 남긴다.
            //
            // ⚠️ 그래도 **release에서는 예외를 찍지 않는다.** [debugPrint]는 release
            // 빌드에서도 플랫폼 로그로 나가므로, 보고를 안 한다고 해서 원시 예외를
            // 그대로 실어도 되는 것은 아니다 — 이 PR이 없애려는 유출이 여기만
            // 남는다. `DebugPrintErrorReporter`가 `includeMessage: kDebugMode`로
            // 하는 것과 같은 판단이다.
            if (kDebugMode) {
              debugPrint('KeepCon: 스캔 프레임 OCR 실패(바코드만 사용): $e');
            }
          }
        }

        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const _GifticonFormScreen(),
          ),
        );
        return;
      }

      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (file == null || !mounted) {
        return;
      }

      mlKitService = MlKitService();
      final inputImage = InputImage.fromFilePath(file.path);
      final scanResult = await mlKitService.scan(inputImage);
      final parsed = const GifticonOcrParser().parse(scanResult.text);

      controller.prefillFromRecognition(
        brand: parsed.brand,
        productName: parsed.productName,
        price: parsed.price,
        barcode: scanResult.firstBarcodeValue,
        category: _selectedGroup.label,
        expiryDate: parsed.expiryDate,
        imagePath: file.path,
      );

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const _GifticonFormScreen(),
        ),
      );
    } catch (e, s) {
      // **원인은 로그로, 화면에는 다음 행동만.** 여기 오는 것은 이미지 디코딩·
      // ML Kit 실패라 사용자가 예외 문자열로 할 수 있는 것이 없다. 진단은 공유
      // 계약의 진입점으로 넘긴다 — 이 자리는 [WidgetRef]가 있어 그대로 쓸 수 있다
      // (컨트롤러 쪽은 [Ref]라 못 쓴다. `gifticon_form_state.dart` 참조).
      reportHandledFailure(ref, e, s, context: 'ScanPage._openForm');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          // 이 파일의 스낵바 중 유일하게 어절 보호가 빠져 있던 자리다. 좁은
          // 폭에서 '오류가 발/생했습니다'처럼 갈라진다.
          content: KeepAllText('이미지를 처리하지 못했어요. 다시 시도해 주세요.'),
        ),
      );
    } finally {
      await mlKitService?.dispose();
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('기프티콘 등록'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text(
                  '등록 방식을 선택해 주세요',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 6),
                KeepAllText(
                  '바코드 이미지 분석 또는 수동 입력이 가능합니다.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _ScanMethodCard(
                        title: '갤러리',
                        subtitle: '앨범에서 선택',
                        icon: Icons.photo_library_rounded,
                        accentColor: scheme.primary,
                        onTap: () => _openForm(ScanSource.gallery),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ScanMethodCard(
                        title: '카메라',
                        subtitle: '직접 촬영하기',
                        icon: Icons.camera_alt_rounded,
                        accentColor: scheme.secondary,
                        onTap: () => _openForm(ScanSource.camera),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ManualEntryCard(
                  onTap: () => _openForm(ScanSource.manual),
                ),
                const SizedBox(height: 28),
                // 두 글자 덩어리를 [Flexible]로 감싼다 — 감싸지 않으면 각자 자연
                // 너비를 고집해, 글자 확대 설정(접근성)을 켠 기기에서 둘의 합이
                // 폭을 넘는다(360px·1.3배에서 1.5px 넘쳤다). 넘치면 잘려서 안
                // 보이므로, 넘기는 대신 접히게 두는 편이 읽는 데 낫다.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: KeepAllText(
                        '자주 쓰는 카테고리',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: KeepAllText(
                        '미리 분류하기',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 타일 높이는 원래 비율(0.95)로 잡되, **내용이 필요로 하는 높이
                // 아래로는 내려가지 않게 바닥을 깐다.**
                //
                // 비율만 쓰면 폭이 좁아질수록 타일이 낮아져 고정 높이인 내용이
                // 넘친다(390px에서 2.4px 오버플로 — 디버그 빌드는 매 프레임
                // 예외를 던지고 릴리스에서는 내용이 잘린다). 넓은 화면에서는
                // 비율이 이기므로 지금 보이는 모양이 그대로 유지된다.
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    const int columns = 3;
                    const double spacing = 10;

                    final double tileWidth =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                    final double byRatio = tileWidth / 0.95;
                    final double floor = _GroupTile.minExtentFor(context);

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        mainAxisExtent: byRatio > floor ? byRatio : floor,
                      ),
                      itemCount: _GifticonGroup.values.length,
                      itemBuilder: (BuildContext context, int index) {
                        final group = _GifticonGroup.values[index];
                        final selected = _selectedGroup == group;

                        return _GroupTile(
                          data: group,
                          selected: selected,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedGroup = group;
                            });
                          },
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  '저장할 그룹 선택',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () {
                    setState(() {
                      _selectedTargetGroupId = null; // 내 지갑 선택
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _selectedTargetGroupId == null
                            ? scheme.primary
                            : scheme.outline.withValues(alpha: 0.25),
                        width: _selectedTargetGroupId == null ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_rounded,
                          color: _selectedTargetGroupId == null
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '내 지갑',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _selectedTargetGroupId == null
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        if (_selectedTargetGroupId == null)
                          Icon(
                            Icons.check_circle_rounded,
                            color: scheme.primary,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanMethodCard extends StatelessWidget {
  const _ScanMethodCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualEntryCard extends StatelessWidget {
  const _ManualEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                color: scheme.primary,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '직접 입력하기',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    // :258의 부제와 같은 역할·같은 화면이다. 한쪽만 처리하면
                    // 320~375px에서 위는 어절 경계로, 아래는 어절 한가운데로
                    // 갈라져 같은 화면 안에서 문단 모양이 어긋난다.
                    KeepAllText(
                      '이미지 없이 정보를 직접 작성합니다.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _GifticonGroup data;
  final bool selected;
  final VoidCallback onTap;

  // 타일 내용은 **높이가 고정이다** — 아이콘 칸, 간격, 한 줄 라벨, 위아래 여백.
  // 그리드가 높이를 폭에서 끌어오면(childAspectRatio) 좁은 화면에서 타일이 이
  // 높이보다 낮아져 내용이 넘친다. 값을 여기 모아 두고 [minExtentFor]가 같은
  // 값을 쓰게 해, 한쪽만 바뀌어 계산이 어긋나는 일을 막는다.
  static const double _padV = 20;
  static const double _iconBox = 34;
  static const double _emojiSize = 30;
  static const double _gap = 12;
  static const double _labelSize = 15;
  static const double _selectedBorder = 2;

  /// 내용이 넘치지 않으려면 타일이 최소한 가져야 하는 높이.
  ///
  /// 라벨 높이는 **어림하지 않고 실제로 잰다.** 행간 계수를 곱해 추정했더니
  /// 360px에서 5.5px 모자랐다 — 이유가 둘이고 둘 다 상수로는 못 맞춘다:
  ///
  /// - `치킨/피자`처럼 `/`가 섞인 라벨은 폰트 폴백이 일어나 2px 더 높다. 타일
  ///   높이는 하나뿐이므로 **가장 높은 라벨**을 기준으로 잡아야 한다.
  /// - 테두리가 안쪽 높이를 먹는다. 가장 두꺼운 경우인 **선택 상태**(위아래 각
  ///   [_selectedBorder] = 총 4px)를 기준으로 잡아야 한다. 비선택과의 '차이'인
  ///   2px으로 잡았다가 선택된 타일만 딱 그만큼 넘쳤다.
  ///
  /// [TextScaler]를 함께 넘겨 글자 확대 설정도 반영된다.
  static double minExtentFor(BuildContext context) {
    final TextStyle? labelStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontSize: _labelSize, fontWeight: FontWeight.w700);
    final TextScaler scaler = MediaQuery.textScalerOf(context);

    double tallestLabel = 0;
    for (final _GifticonGroup group in _GifticonGroup.values) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: group.label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.height > tallestLabel) tallestLabel = painter.height;
      painter.dispose();
    }

    // 테두리도 안쪽 높이를 먹는다 — Flutter는 CSS와 달리 [BoxDecoration]의
    // 테두리 두께를 Container의 padding에 더한다. 가장 두꺼운 경우(선택 상태,
    // 위아래 각 [_selectedBorder])를 기준으로 잡아야 선택된 타일에서만 넘치는
    // 일이 없다 — 비선택과의 '차이'로 잡았다가 딱 그만큼 2px 모자랐다.
    //
    // 끝의 1px은 반올림 여유다 — 위 계산은 필요한 높이와 **정확히** 같아져서
    // 서브픽셀 반올림 한 번이면 다시 넘친다. 1px 남는 것은 눈에 띄지 않지만
    // 모자라면 오버플로로 드러난다.
    return _padV * 2 +
        _selectedBorder * 2 +
        _iconExtentFor(scaler) +
        _gap +
        tallestLabel +
        1;
  }

  /// 아이콘 칸의 높이.
  ///
  /// 칸에 든 이모지는 [Icon]이 아니라 **[Text]라서 글자 확대 설정을 따라 커진다**
  /// (`Icon`은 `applyTextScaling` 기본값이 false라 그대로다 — 그래서 '기타'
  /// 타일만 멀쩡했다). 칸을 상수 [_iconBox]로 고정하면 배율이 오를 때 이모지가
  /// 칸을 넘어 아래 라벨을 덮는다 — 2.0배에서 자연 높이 60px, [_gap] 12px을
  /// 넘어 13px이 라벨 위로 내려온다.
  ///
  /// ⚠️ 이 결함은 **오버플로 예외를 던지지 않는다.** `SizedBox`가 tight 제약이라
  /// 렌더 객체는 자기 크기를 34로 보고하고 이모지는 그냥 칸 밖에 그려진다.
  /// 그래서 폭·배율 전수 스윕으로도 잡히지 않았다 — 눈으로 봐야 보인다.
  ///
  /// 확대분이 [_iconBox]를 넘을 때만 칸을 넓혀 기본 배율의 모양은 그대로 둔다.
  static double _iconExtentFor(TextScaler scaler) {
    final double emoji = scaler.scale(_emojiSize);
    return emoji > _iconBox ? emoji : _iconBox;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color fg = selected ? scheme.primary : scheme.onSurface;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: _padV,
            horizontal: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outline.withValues(alpha: 0.25),
              width: selected ? _selectedBorder : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: _iconExtentFor(MediaQuery.textScalerOf(context)),
                child: Center(
                  child: data.icon != null
                      ? Icon(data.icon, color: fg, size: 32)
                      : Text(
                          data.emoji!,
                          style: const TextStyle(
                            fontSize: _emojiSize,
                            height: 1,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: _gap),
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: _labelSize,
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

class _GifticonFormScreen extends ConsumerStatefulWidget {
  const _GifticonFormScreen();

  @override
  ConsumerState<_GifticonFormScreen> createState() =>
      __GifticonFormScreenState();
}

class __GifticonFormScreenState extends ConsumerState<_GifticonFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _brandController;
  late final TextEditingController _productNameController;
  late final TextEditingController _priceController;
  late final TextEditingController _barcodeController;

  /// 중복으로 판정돼 저장이 거부된 바코드 번호.
  ///
  /// 직접 입력 경로에서 바코드 필드 아래에 빨간 안내를 띄우는 데 쓴다.
  /// 사용자가 번호를 고치면 필드의 재검증에서 자동으로 문구가 사라진다.
  String? _duplicateBarcode;

  @override
  void initState() {
    super.initState();
    final initialState = ref.read(gifticonFormControllerProvider);

    // 불필요한 null-aware 연산자(?? '') 제거로 dead_null_aware_expression 경고 수정
    _brandController = TextEditingController(text: initialState.brand);
    _productNameController =
        TextEditingController(text: initialState.productName);
    // 갤러리 OCR이 채운 값도 처음부터 콤마가 붙은 형태로 보여준다.
    _priceController =
        TextEditingController(text: formatThousands(initialState.price));
    _barcodeController = TextEditingController(text: initialState.barcode);
  }

  @override
  void dispose() {
    _brandController.dispose();
    _productNameController.dispose();
    _priceController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _selectExpiryDate(BuildContext context) async {
    final formNotifier = ref.read(gifticonFormControllerProvider.notifier);
    final currentState = ref.read(gifticonFormControllerProvider);

    final initialDate = currentState.expiryDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked != null) {
      formNotifier.setExpiryDate(picked);
    }
  }

  /// 저장 버튼 처리.
  ///
  /// [GifticonFormController.submit]은 **비동기**다 — 반드시 await하고 그 결과로
  /// 안내를 갈라야 한다. await 없이 성공 스낵바를 띄우면 검증 실패·중복·저장 실패가
  /// 전부 "저장되었습니다"로 보이고 화면까지 닫혀, 홈에는 아무것도 없는 상태가 된다.
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      // 필드마다 빨간 안내가 뜨지만, 스크롤 밖에 있으면 눌러도 아무 일도
      // 안 일어난 것처럼 보인다 — 왜 막혔는지 함께 알린다.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const KeepAllText('입력하지 않은 필수 항목이 있습니다.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final notifier = ref.read(gifticonFormControllerProvider.notifier);

    notifier.setBrand(_brandController.text.trim());
    notifier.setProductName(_productNameController.text.trim());
    notifier.setPrice(_priceController.text.trim());
    notifier.setBarcode(_barcodeController.text.trim());

    await notifier.submit();

    if (!mounted) return;

    final GifticonFormState formState =
        ref.read(gifticonFormControllerProvider);

    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    switch (formState.submit) {
      case ScanSubmitSuccess():
        messenger.showSnackBar(
          const SnackBar(
            content: KeepAllText('기프티콘이 성공적으로 저장되었습니다.'),
          ),
        );
        navigator.popUntil((route) => route.isFirst);

      case ScanSubmitLimitReached(:final int saved, :final int limit):
        // 중복과 달리 **경로를 가르지 않는다.** 중복은 직접 입력이면 그 자리에서
        // 번호를 고칠 수 있어 화면에 머물렀지만, 한도는 입력을 어떻게 바꿔도
        // 저장되지 않는다 — 어느 경로든 폼에 남겨 둘 이유가 없다.
        navigator.popUntil((route) => route.isFirst);
        await showDialog<void>(
          context: navigator.context,
          builder: (BuildContext dialogContext) {
            final ThemeData dialogTheme = Theme.of(dialogContext);

            final ColorScheme dialogScheme = dialogTheme.colorScheme;
            final TextStyle? mutedStyle = _ResultDialog.mutedStyle(dialogTheme);

            return AlertDialog(
              insetPadding: _ResultDialog.insetPadding(dialogContext),
              title: const Text('저장 한도에 도달했어요'),
              // 중복 안내와 같은 짜임 — 무슨 일인지(제목) / 지금 상태(카드) /
              // 왜 그런지(한 문장) / 어떻게 푸는지(흐린 글씨).
              //
              // 숫자를 문장에 녹이면 "10개까지 저장할 수 있어요. 지금 10개를…"처럼
              // 같은 수가 두 번 나오고 문장이 늘어진다. 카드로 빼면 한눈에 읽히고
              // 아래 문장도 짧아진다.
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: dialogScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          '$saved',
                          style: dialogTheme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            // 한도에 닿았다는 것을 색으로도 알린다.
                            color: dialogScheme.error,
                          ),
                        ),
                        Text(' / $limit개', style: mutedStyle),
                        const Spacer(),
                        Text('사용 중', style: mutedStyle),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 문구는 그대로 두고 **끊어도 되는 자리만** 어절 경계로 제한한다
                  // ([keepAllKo]). 좁은 폭에서 '이 / 번 기프티콘은'처럼 갈라지던 것을
                  // 막으면서, `\n`을 손으로 넣는 방식과 달리 폭이 넓어져도 어색하게
                  // 일찍 끊기지 않는다.
                  KeepAllText('무료 플랜은 $limit개까지 보관할 수 있어, 이번 기프티콘은 저장하지 않았어요.'),
                  const SizedBox(height: 18),

                  // 해법 두 가지를 **한 문단에 몰아넣지 않는다.** 좁은 폭에서 첫
                  // 해법이 두 줄로 접히면 다음 해법과 붙어, 어디서 하나가 끝나고
                  // 다음이 시작하는지 보이지 않는다(`\n`은 줄만 바꿀 뿐 사이를
                  // 벌리지 못한다). 블록으로 나누고 간격을 주면 "방법이 둘"이라는
                  // 구조가 글을 읽기 전에 눈에 먼저 들어온다.
                  //
                  // **먼저 제시하는 길은 '사용 완료'다.** 프리미엄 전환은 dev·prod에서
                  // 보안 규칙이 plan 쓰기를 막아 실제로는 되지 않는다("결제 연동 준비 중").
                  // 그것만 안내하면 사용자를 막다른 곳으로 보내는 셈이라, 지금 바로
                  // 통하는 방법을 앞에 둔다.
                  KeepAllText(
                    '다 쓴 기프티콘을 사용 완료 처리하면 자리가 납니다.',
                    style: mutedStyle,
                  ),
                  const SizedBox(height: 12),
                  KeepAllText(
                    '프리미엄으로 올리면 개수 제한이 없어져요.',
                    style: mutedStyle,
                  ),

                  // 경로는 **바로 위 문장에 딸린 부속**이다. 앞 블록과 같은 간격을
                  // 주면 독립된 세 번째 해법으로 읽히므로, 간격을 좁게 붙여
                  // 종속 관계를 위치로 드러낸다.
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      // 경로 표기는 실제 UI와 맞춘다 — 앱에 '설정'이나 '마이페이지'라는
                      // 라벨은 없다. 진입점은 홈 오른쪽 위 톱니바퀴(툴팁 '마이')다.
                      //
                      // 아이콘은 ⚙ **이모지가 아니라 앱이 실제로 그리는 아이콘**
                      // ([Icons.settings_outlined] — main_page의 그 버튼과 같은 글리프)을
                      // WidgetSpan으로 넣는다. 이모지는 컬러로 렌더링돼 회색 본문과 톤이
                      // 어긋나지만, 이 방식은 주변 글자와 같은 색·크기를 따라가면서
                      // "찾아야 할 그 모양"을 그대로 보여 준다.
                      style: mutedStyle,
                      children: <InlineSpan>[
                        TextSpan(
                          text: keepAllKo('홈 오른쪽 위 '),
                          semanticsLabel: '홈 오른쪽 위 ',
                        ),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            Icons.settings_outlined,
                            size: (mutedStyle?.fontSize ?? 12) + 2,
                            color: dialogScheme.onSurfaceVariant,
                          ),
                        ),
                        TextSpan(
                          text: keepAllKo(' › 프리미엄'),
                          semanticsLabel: ' › 프리미엄',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('확인'),
                ),
              ],
            );
          },
        );

      case ScanSubmitDuplicate(:final Gifticon existing):
        // 직접 입력은 사용자가 그 자리에서 번호를 고칠 수 있으므로 화면에 머무르며
        // 바코드 필드 아래에 빨간 문구로 알린다.
        if (formState.source == ScanSource.manual) {
          setState(() {
            _duplicateBarcode = _barcodeController.text.trim();
          });
          _formKey.currentState?.validate();
          return;
        }

        // 카메라/갤러리는 인식된 이미지·바코드가 이미 화면에 떠 있어 필드 문구로
        // 고칠 것이 없다. 홈으로 돌려보낸 뒤 팝업으로 알린다.
        //
        // 다이얼로그는 이 화면의 context가 아니라 Navigator 자신의 context로 띄운다 —
        // 이 화면은 popUntil 직후 사라지므로 그 context로는 열 수 없다.
        navigator.popUntil((route) => route.isFirst);
        await showDialog<void>(
          context: navigator.context,
          builder: (BuildContext dialogContext) {
            final ThemeData dialogTheme = Theme.of(dialogContext);
            final ColorScheme dialogScheme = dialogTheme.colorScheme;

            // 보조 정보(브랜드·만료일)는 한 단계 눌러 두고 상품명만 굵게 —
            // 눈이 "무엇과 겹쳤는지"에 먼저 닿게 한다.
            //
            // 배치 규약은 한도 다이얼로그와 **공유한다**([_ResultDialog]) — 형제인데
            // 여백·행간이 어긋나면 같은 화면군에서 폭이 들쭉날쭉해 보인다.
            final TextStyle? mutedStyle = _ResultDialog.mutedStyle(dialogTheme);

            return AlertDialog(
              insetPadding: _ResultDialog.insetPadding(dialogContext),
              title: const Text('이미 등록된 기프티콘'),
              // 제목이 "이미 등록됨"을 이미 말하므로 본문은 그것을 되풀이하지 않는다.
              // 대신 세 박자로 나눈다 — 무슨 일인지 / 무엇과 겹쳤는지 / 그래서 어떻게 됐는지.
              // 한 문장에 다 담으면 좁은 다이얼로그에서 어색하게 줄바꿈된다.
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const KeepAllText('같은 바코드의 기프티콘이 이미 있어요.'),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: dialogScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(existing.brand, style: mutedStyle),
                        const SizedBox(height: 2),
                        Text(
                          existing.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: dialogTheme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // 같은 상품이 여러 개일 때 만료일이 있어야 어떤 건지 특정된다.
                        Text(
                          '${formatYmdDot(existing.expiryDate)} 만료',
                          style: mutedStyle,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  KeepAllText('새로 등록하지 않았어요.', style: mutedStyle),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('확인'),
                ),
              ],
            );
          },
        );

      case ScanSubmitFailure(:final String message):
        // 실패 시 화면을 닫지 않는다 — 닫으면 입력이 사라지고 사용자는 무엇이
        // 잘못됐는지 알 수 없다(유효기간 미선택 등이 여기로 온다).
        //
        // 어절 보호를 **여기서** 건다. 상태 쪽 주석이 "표시 지점에서만 건다"고
        // 가리키는 지점이 여기인데 정작 빠져 있었다 — 형제 스낵바 셋(219·800·
        // 829행)은 모두 [KeepAllText]다. 그래서 문구가 길어질수록 이 스낵바만
        // 어절이 갈라졌다('네트'/'워크').
        //
        // 이 자리를 지나는 메시지는 이제 전부 프로즈다 — 예전에는 둘이
        // `'…: $e'` 꼴로 원시 예외를 품었고, 그래서 어절 보호가 긴 식별자를
        // 넘치게 하지 않는지가 문제였다. 원인을 로그로 옮기면서 그 전제가
        // 사라졌다(`gifticon_form_state.dart`의 `_reportFailure`).
        messenger.showSnackBar(
          SnackBar(
            content: KeepAllText(message),
            backgroundColor: scheme.error,
          ),
        );

      case ScanSubmitIdle():
      case ScanSubmitInProgress():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(gifticonFormControllerProvider);
    final theme = Theme.of(context);

    final expiryDateText = formState.expiryDate != null
        ? '${formState.expiryDate!.year}-${formState.expiryDate!.month.toString().padLeft(2, '0')}-${formState.expiryDate!.day.toString().padLeft(2, '0')}'
        : '날짜를 선택해 주세요';

    return Scaffold(
      appBar: AppBar(
        title: const Text('기프티콘 정보 확인'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20.0),
            children: [
              if (formState.imagePath != null &&
                  formState.imagePath!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 200,
                    width: double.infinity,
                    color: theme.colorScheme.surfaceContainerHigh,
                    child: Image.file(
                      File(formState.imagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            '이미지를 불러올 수 없습니다.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              TextFormField(
                controller: _brandController,
                // 네 필수 항목이 모두 같은 방식으로 반응해야 한다 — 일부만 즉시
                // 갱신되면 채워 넣은 칸에 "입력해 주세요"가 남아 혼란스럽다.
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: '브랜드 / 사용처',
                  hintText: '예: 스타벅스, GS25',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '브랜드를 입력해 주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _productNameController,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: '상품명',
                  hintText: '예: 카페 아메리카노 T',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '상품명을 입력해 주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _barcodeController,
                keyboardType: TextInputType.number,
                // 번호를 고치는 즉시 재검증돼 중복 안내가 사라진다.
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: '바코드 번호',
                  hintText: '숫자만 입력',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final String trimmed = value?.trim() ?? '';

                  // 바코드는 계약상 nullable이다 — [Gifticon.barcode] 문서가
                  // "수동 입력 미기재 시 없을 수 있다"고 명시하고
                  // [GifticonFormState.validate]도 요구하지 않는다. 화면만 필수로
                  // 강제하면 바코드 없는 기프티콘을 아예 등록할 수 없다.
                  //
                  // 값이 없으면 중복 검사 대상도 아니다(컨트롤러가 건너뛴다).
                  if (trimmed.isEmpty) {
                    return null;
                  }
                  if (trimmed == _duplicateBarcode) {
                    return '이미 등록된 바코드 번호입니다.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                // 입력하는 동안 천 단위 콤마를 붙인다(1000 → 1,000).
                // 커서 복원·선행 0 처리까지 검증된 scan 정본 포매터를 그대로 쓴다.
                // 상태에는 콤마가 남아도 되고, 계약 변환은 parsedPrice가 콤마를
                // 제거한 뒤 int로 바꾼다.
                inputFormatters: const <TextInputFormatter>[
                  ThousandsSeparatorInputFormatter(),
                ],
                decoration: const InputDecoration(
                  labelText: '금액 / 금액권 잔액 (선택)',
                  hintText: '예: 10,000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // 유효기간은 계약상 필수인데 [Form] validator가 없어서
              // `_formKey.validate()`를 그냥 통과했다 — 저장 단계에서야 실패하니
              // "저장되었습니다"만 뜨고 홈에는 아무것도 없던 원인이다.
              // FormField로 감싸 다른 필수 항목과 똑같이 저장을 막는다.
              FormField<DateTime>(
                initialValue: formState.expiryDate,
                // 날짜를 고르는 즉시 재검증돼 빨간 안내가 사라진다.
                // (없으면 값은 들어갔는데 "선택해 주세요"가 남아 있다)
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (DateTime? value) {
                  if (value == null) {
                    return '유효기간을 선택해 주세요.';
                  }
                  return null;
                },
                builder: (FormFieldState<DateTime> field) {
                  return InkWell(
                    onTap: () async {
                      await _selectExpiryDate(context);
                      if (!mounted) return;
                      // 고른 날짜를 FormField에도 알려야 빨간 안내가 사라진다.
                      field.didChange(
                        ref.read(gifticonFormControllerProvider).expiryDate,
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: '유효기간',
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.calendar_today_rounded),
                        errorText: field.errorText,
                      ),
                      child: Text(
                        expiryDateText,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                // 저장이 이제 비동기라 연타하면 같은 기프티콘이 두 번 들어갈 수 있다.
                onPressed:
                    formState.submit is ScanSubmitInProgress ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '저장하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
