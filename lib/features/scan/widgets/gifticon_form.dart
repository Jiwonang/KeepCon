/// scan 입력 폼 위젯.
///
/// 사용자가 기프티콘 정보를 확인 및 수정하고 제출할 수 있는 UI 폼이다.
///
/// 주요 역할:
/// - 브랜드, 상품명, 금액, 바코드 입력 필드 제공
/// - 카테고리 프리셋 선택 및 유효기간 quick pick 기능 제공
/// - GifticonFormController와 연동하여 폼 상태 변경 및 제출 처리
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/gifticon_form_state.dart';

/// 카테고리 선택용 프리셋 목록 상수.
const List<String> kScanCategoryPresets = <String>[
  '카페',
  '베이커리',
  '치킨',
  '편의점',
  '영화/문화',
  '기타',
];

/// 유효기간 빠른 선택 옵션 enum.
enum ExpiryQuickPick {
  /// 30일 후
  after30Days('+30일', 30),

  /// 90일 후
  after90Days('+90일', 90),

  /// 1년 후
  after1Year('+1년', 365);

  /// ExpiryQuickPick 생성을 위한 생성자.
  const ExpiryQuickPick(this.label, this.days);

  /// 버튼에 표시될 라벨 문자열
  final String label;

  /// 더해질 일수
  final int days;

  /// 기준 시점([now]) 기준으로 유효기간 DateTime을 계산하여 반환한다.
  ///
  /// [now]가 지정되지 않으면 내부적으로 현재 시각을 구하여 계산한다.
  DateTime resolve([DateTime? now]) {
    final DateTime base = now ?? DateTime.now();
    if (this == ExpiryQuickPick.after1Year) {
      return DateTime(base.year + 1, base.month, base.day);
    }
    final DateTime calculated = base.add(Duration(days: days));
    // 밀리초 오차로 인한 테스트 실패 방지 및 자정 단위 규격화
    return DateTime(calculated.year, calculated.month, calculated.day);
  }
}

/// 유효기간 빠른 선택 버튼 목록 위젯.
class ExpiryQuickPickChips extends StatelessWidget {
  /// [ExpiryQuickPickChips] 위젯 생성자.
  const ExpiryQuickPickChips({
    super.key,
    required this.onSelected,
    this.now,
  });

  /// 날짜가 선택되었을 때 실행될 콜백 함수.
  final ValueChanged<DateTime> onSelected;

  /// 날짜 계산 기준 시점 (테스트 주입용).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: ExpiryQuickPick.values.map((option) {
        return OutlinedButton(
          onPressed: () {
            final DateTime base = now ?? DateTime.now();
            onSelected(option.resolve(base));
          },
          child: Text(option.label),
        );
      }).toList(),
    );
  }
}

/// 기프티콘 입력 및 수정 폼 위젯.
class GifticonForm extends ConsumerStatefulWidget {
  /// [GifticonForm] 위젯 생성자.
  const GifticonForm({
    super.key,
    this.now,
  });

  /// 유효기간 계산 기준 시점 (테스트용 시간 주입).
  final DateTime? now;

  @override
  ConsumerState<GifticonForm> createState() => _GifticonFormState();
}

class _GifticonFormState extends ConsumerState<GifticonForm> {
  /// 브랜드명 입력 컨트롤러.
  late final TextEditingController _brandController;

  /// 상품명 입력 컨트롤러.
  late final TextEditingController _productNameController;

  /// 금액 입력 컨트롤러.
  late final TextEditingController _priceController;

  /// 바코드 번호 입력 컨트롤러.
  late final TextEditingController _barcodeController;

  /// 카테고리 입력 컨트롤러.
  late final TextEditingController _categoryController;

  @override
  void initState() {
    super.initState();
    final GifticonFormState state = ref.read(gifticonFormControllerProvider);
    _brandController = TextEditingController(text: state.brand);
    _productNameController = TextEditingController(text: state.productName);
    _priceController = TextEditingController(text: _formatPrice(state.price));
    _barcodeController = TextEditingController(text: state.barcode);
    _categoryController = TextEditingController(text: state.category);
  }

  /// 정규식을 이용하여 문자열 숫자에 천 단위 콤마(,)를 적용한다.
  String _formatPrice(String raw) {
    final String clean = raw.replaceAll(',', '');
    final int? parsed = int.tryParse(clean);
    if (parsed == null) return raw;
    return parsed.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  @override
  void dispose() {
    _brandController.dispose();
    _productNameController.dispose();
    _priceController.dispose();
    _barcodeController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GifticonFormState state = ref.watch(gifticonFormControllerProvider);
    final GifticonFormController controller =
        ref.read(gifticonFormControllerProvider.notifier);

    // 외부(OCR 등)에서 프리필 값이 변경되었을 때 텍스트 컨트롤러 동기화
    ref.listen<GifticonFormState>(gifticonFormControllerProvider,
        (GifticonFormState? previous, GifticonFormState next) {
      if (previous?.brand != next.brand && _brandController.text != next.brand) {
        _brandController.text = next.brand;
      }
      if (previous?.productName != next.productName &&
          _productNameController.text != next.productName) {
        _productNameController.text = next.productName;
      }
      if (previous?.price != next.price) {
        final String formatted = _formatPrice(next.price);
        if (_priceController.text != formatted) {
          _priceController.text = formatted;
        }
      }
      if (previous?.barcode != next.barcode &&
          _barcodeController.text != next.barcode) {
        _barcodeController.text = next.barcode;
      }
      if (previous?.category != next.category &&
          _categoryController.text != next.category) {
        _categoryController.text = next.category;
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.submit is ScanSubmitFailure)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                (state.submit as ScanSubmitFailure).message,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          TextFormField(
            controller: _brandController,
            decoration: const InputDecoration(labelText: '브랜드명'),
            onChanged: controller.setBrand,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _productNameController,
            decoration: const InputDecoration(labelText: '상품명'),
            onChanged: controller.setProductName,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '금액(원) *'),
            onChanged: (String value) {
              final String formatted = _formatPrice(value);
              if (formatted != value) {
                _priceController.value = TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
              }
              controller.setPrice(formatted);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _barcodeController,
            decoration: const InputDecoration(labelText: '바코드 번호'),
            onChanged: controller.setBarcode,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _categoryController,
            decoration: const InputDecoration(labelText: '카테고리'),
            onChanged: controller.setCategory,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: kScanCategoryPresets.map((String category) {
              final bool isSelected = state.category == category;
              return ChoiceChip(
                label: Text(category),
                selected: isSelected,
                onSelected: (bool selected) {
                  if (selected) {
                    controller.setCategory(category);
                  } else {
                    controller.setCategory('');
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  state.expiryDate == null
                      ? '유효기간 선택 필요'
                      : '유효기간: ${state.expiryDate!.year}.${state.expiryDate!.month.toString().padLeft(2, '0')}.${state.expiryDate!.day.toString().padLeft(2, '0')}',
                ),
              ),
              TextButton(
                onPressed: () async {
                  final DateTime base = widget.now ?? DateTime.now();
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: state.expiryDate ?? base,
                    firstDate: base,
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    controller.setExpiryDate(picked);
                  }
                },
                child: const Text('날짜 선택'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExpiryQuickPickChips(
            onSelected: controller.setExpiryDate,
            now: widget.now,
          ),
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: state.submit is ScanSubmitInProgress
                      ? null
                      : () async {
                          final saved = await controller.submit();
                          if (saved != null) {
                            final targetGroupId = state.targetGroupId;
                            controller.reset();
                            controller.startWith(
                              ScanSource.manual,
                              targetGroupId: targetGroupId,
                            );
                          }
                        },
                  child: const Text('저장 후 계속 등록'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: state.submit is ScanSubmitInProgress
                      ? null
                      : () => controller.submit(),
                  child: const Text('저장'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}