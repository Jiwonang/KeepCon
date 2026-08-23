/// 스캔/추가 페이지.
///
/// 카메라 스캔 / 갤러리 불러오기 / 수동 입력 세 가지 경로를 제공한다.
/// 세 경로는 최종적으로 모두 [GifticonForm]으로 이동한다.
///
/// route: [AppRoutes.scan]
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image_picker/image_picker.dart';

import 'package:keepcon/features/scan/services/gifticon_ocr_parser.dart';
import 'package:keepcon/features/scan/services/ml_kit_service.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/features/scan/util/price_input_formatter.dart';
import 'package:keepcon/features/scan/widgets/barcode_scanner_screen.dart';
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
            debugPrint('KeepCon: 스캔 프레임 OCR 실패(바코드만 사용): $e');
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('이미지를 처리하는 중 오류가 발생했습니다: $e'),
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
                Text(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '자주 쓰는 카테고리',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '미리 분류하기',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: _GifticonGroup.values.length,
                  itemBuilder: (context, index) {
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
                    Text(
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
            vertical: 20,
            horizontal: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
                      ? Icon(data.icon, color: fg, size: 32)
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
          content: const Text('입력하지 않은 필수 항목이 있습니다.'),
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
          const SnackBar(content: Text('기프티콘이 성공적으로 저장되었습니다.')),
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
            final TextStyle? mutedStyle = dialogTheme.textTheme.bodySmall
                ?.copyWith(color: dialogScheme.onSurfaceVariant);

            return AlertDialog(
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
                  Text('무료 플랜은 $limit개까지 보관할 수 있어, 이번 기프티콘은 저장하지 않았어요.'),
                  const SizedBox(height: 14),
                  Text(
                    // **먼저 제시하는 길은 '사용 완료'다.** 프리미엄 전환은 dev·prod에서
                    // 보안 규칙이 plan 쓰기를 막아 실제로는 되지 않는다("결제 연동 준비 중").
                    // 그것만 안내하면 사용자를 막다른 곳으로 보내는 셈이라, 지금 바로
                    // 통하는 방법을 앞에 둔다.
                    //
                    // 경로 표기는 실제 UI와 맞춘다 — 앱에 '설정'이나 '마이페이지'라는
                    // 라벨은 없다. 진입점은 홈 오른쪽 위 톱니바퀴(툴팁 '마이')다.
                    '다 쓴 기프티콘을 사용 완료 처리하면 자리가 납니다.\n'
                    '프리미엄으로 올리면 개수 제한이 없어져요 (홈 오른쪽 위 ⚙ › 프리미엄).',
                    style: mutedStyle,
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
            final TextStyle? mutedStyle = dialogTheme.textTheme.bodySmall
                ?.copyWith(color: dialogScheme.onSurfaceVariant);

            return AlertDialog(
              title: const Text('이미 등록된 기프티콘'),
              // 제목이 "이미 등록됨"을 이미 말하므로 본문은 그것을 되풀이하지 않는다.
              // 대신 세 박자로 나눈다 — 무슨 일인지 / 무엇과 겹쳤는지 / 그래서 어떻게 됐는지.
              // 한 문장에 다 담으면 좁은 다이얼로그에서 어색하게 줄바꿈된다.
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('같은 바코드의 기프티콘이 이미 있어요.'),
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
                  Text('새로 등록하지 않았어요.', style: mutedStyle),
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
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
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
