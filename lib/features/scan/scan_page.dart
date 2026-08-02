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

      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source == ScanSource.gallery
            ? ImageSource.gallery
            : ImageSource.camera,
        imageQuality: 100,
      );

      if (file == null) {
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

  @override
  void initState() {
    super.initState();
    final initialState = ref.read(gifticonFormControllerProvider);

    // 불필요한 null-aware 연산자(?? '') 제거로 dead_null_aware_expression 경고 수정
    _brandController = TextEditingController(text: initialState.brand);
    _productNameController =
        TextEditingController(text: initialState.productName);
    _priceController = TextEditingController(text: initialState.price);
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

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final notifier = ref.read(gifticonFormControllerProvider.notifier);

    notifier.setBrand(_brandController.text.trim());
    notifier.setProductName(_productNameController.text.trim());
    notifier.setPrice(_priceController.text.trim());
    notifier.setBarcode(_barcodeController.text.trim());

    notifier.submit();

    messenger.showSnackBar(
      const SnackBar(content: Text('기프티콘이 성공적으로 저장되었습니다.')),
    );

    navigator.pop();
    navigator.popUntil((route) => route.isFirst);
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
                decoration: const InputDecoration(
                  labelText: '바코드 번호',
                  hintText: '숫자만 입력',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '바코드 번호를 입력해 주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '금액 / 금액권 잔액 (선택)',
                  hintText: '예: 10000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () => _selectExpiryDate(context),
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '유효기간',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  child: Text(
                    expiryDateText,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _submit,
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
