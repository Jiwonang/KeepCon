/// 편집 가능한 기프티콘 폼 위젯.
///
/// 세 입력 경로(카메라/갤러리/수동)가 모두 이 폼으로 수렴한다. 인식 결과가 있으면
/// 프리필된 상태로, 없으면 빈 상태로 열려 사용자가 수동 편집한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/gifticon_form_state.dart';

/// 기프티콘 필드 편집 폼.
class GifticonForm extends ConsumerWidget {
  const GifticonForm({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(gifticonFormControllerProvider);
    final controller = ref.read(gifticonFormControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _labeledField(
          label: '브랜드명 *',
          hint: '예: 스타벅스',
          initialValue: form.brand,
          onChanged: controller.setBrand,
        ),
        _labeledField(
          label: '상품명 *',
          hint: '예: 아메리카노 T',
          initialValue: form.productName,
          onChanged: controller.setProductName,
        ),
        _labeledField(
          label: '금액(원) *',
          hint: '예: 4500 (무료/사은품은 0)',
          initialValue: form.price,
          keyboardType: TextInputType.number,
          // 숫자만 허용 — 문자/기호 입력 차단.
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: controller.setPrice,
        ),
        _labeledField(
          label: '카테고리',
          hint: '미입력 시 "$kDefaultCategory"로 저장',
          initialValue: form.category,
          onChanged: controller.setCategory,
        ),
        _labeledField(
          label: '바코드',
          hint: '선택 입력',
          initialValue: form.barcode,
          keyboardType: TextInputType.number,
          onChanged: controller.setBarcode,
        ),
        const SizedBox(height: 8),
        _ExpiryDateField(
          value: form.expiryDate,
          onPicked: controller.setExpiryDate,
        ),
        const SizedBox(height: 24),
        if (form.submit is ScanSubmitFailure)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              (form.submit as ScanSubmitFailure).message,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        FilledButton(
          onPressed: form.submit is ScanSubmitInProgress
              ? null
              : () async {
                  final saved = await controller.submit();
                  if (saved != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('저장됨: ${saved.brand} ${saved.productName}'),
                      ),
                    );
                    Navigator.of(context).maybePop(saved);
                  }
                },
          child: form.submit is ScanSubmitInProgress
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('저장'),
        ),
      ],
    );
  }

  Widget _labeledField({
    required String label,
    required String hint,
    required String initialValue,
    required ValueChanged<String> onChanged,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        // 프리필 값을 반영하되, 매 rebuild마다 커서가 튀지 않도록 key로 초기값 고정.
        key: ValueKey('$label:$initialValue'),
        initialValue: initialValue,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// 유효기간(만료일) 선택 필드.
class _ExpiryDateField extends StatelessWidget {
  const _ExpiryDateField({required this.value, required this.onPicked});

  final DateTime? value;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    final label = value == null
        ? '유효기간 선택 *'
        : '유효기간: ${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}';
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today),
      label: Text(label),
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) onPicked(picked);
      },
    );
  }
}
