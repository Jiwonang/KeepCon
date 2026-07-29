/// 편집 가능한 기프티콘 폼 위젯.
///
/// 세 입력 경로(카메라/갤러리/수동)가 모두 이 폼으로 수렴한다.
///
/// 입력 흐름:
///
/// 카메라/갤러리 인식
///        ↓
/// GifticonFormController.prefillFromRecognition()
///        ↓
/// Riverpod GifticonFormState 변경
///        ↓
/// TextEditingController에 값 반영
///        ↓
/// 사용자가 값 확인/수정
///        ↓
/// 사용자가 직접 입력할 때마다 Controller 상태 업데이트
///        ↓
/// 저장 버튼
///        ↓
/// GifticonFormController.submit()
///
/// 직접 입력 경로에서는 처음부터 빈 입력창으로 시작한다.
///
/// 이 위젯은 "입력 UI"를 담당하고,
/// 실제 데이터 저장 로직은 [GifticonFormController]가 담당한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/gifticon_form_state.dart';

/// 기프티콘 필드 편집 폼.
///
/// TextEditingController를 사용해 OCR/바코드 인식 결과를
/// 이미 화면이 열린 이후에도 입력창에 안정적으로 반영한다.
///
/// 단순히 TextFormField의 initialValue를 사용하는 경우
/// 위젯이 생성된 이후 Riverpod 상태가 변경되어도
/// 입력창 값이 자동으로 변경되지 않는다.
///
/// 따라서 OCR 결과를 비동기로 받은 현재 구조에서는
/// TextEditingController 방식이 적합하다.
class GifticonForm
    extends ConsumerStatefulWidget {
  const GifticonForm({super.key});

  @override
  ConsumerState<GifticonForm> createState() =>
      _GifticonFormState();
}

class _GifticonFormState
    extends ConsumerState<GifticonForm> {
  // ─────────────────────────────────────────
  // TextEditingController
  // ─────────────────────────────────────────
  //
  // 각각의 입력창을 직접 관리한다.
  //
  // OCR 결과가 나중에 들어왔을 때
  // controller.text를 변경해 화면에 반영할 수 있다.

  late final TextEditingController
      _brandController;

  late final TextEditingController
      _productNameController;

  late final TextEditingController
      _priceController;

  late final TextEditingController
      _categoryController;

  late final TextEditingController
      _barcodeController;

  @override
  void initState() {
    super.initState();

    // ─────────────────────────────────────────
    // 1단계: 현재 Riverpod 상태로 Controller 초기화
    // ─────────────────────────────────────────
    //
    // 직접 입력 경로라면 대부분 빈 값으로 초기화된다.
    //
    // 갤러리/OCR 경로인데 이미 상태에 인식 결과가 들어온 경우에는
    // 인식된 값으로 입력창이 초기화된다.
    final form = ref.read(
      gifticonFormControllerProvider,
    );

    _brandController =
        TextEditingController(
      text: form.brand,
    );

    _productNameController =
        TextEditingController(
      text: form.productName,
    );

    _priceController =
        TextEditingController(
      text: form.price,
    );

    _categoryController =
        TextEditingController(
      text: form.category,
    );

    _barcodeController =
        TextEditingController(
      text: form.barcode,
    );

    // ─────────────────────────────────────────
    // 2단계: Riverpod 상태 변경 감시
    // ─────────────────────────────────────────
    //
    // OCR/바코드 인식 결과가 비동기로 들어오거나
    // 다른 코드에서 폼 상태가 변경되면
    // 입력창에도 해당 값을 반영한다.
    //
    // 예:
    //
    // OCR 결과:
    // brand = "스타벅스"
    //
    // Riverpod 상태 변경
    //        ↓
    // next.brand = "스타벅스"
    //        ↓
    // _brandController.text = "스타벅스"
    //
    // 단, 사용자가 직접 입력 중인 값과 동일하면
    // 불필요하게 커서를 이동시키지 않는다.
    ref.listenManual<GifticonFormState>(
      gifticonFormControllerProvider,
      (previous, next) {
        _syncController(
          controller: _brandController,
          value: next.brand,
        );

        _syncController(
          controller: _productNameController,
          value: next.productName,
        );

        _syncController(
          controller: _priceController,
          value: next.price,
        );

        _syncController(
          controller: _categoryController,
          value: next.category,
        );

        _syncController(
          controller: _barcodeController,
          value: next.barcode,
        );
      },
    );
  }

  /// Riverpod 상태의 값을 TextEditingController에 반영한다.
  ///
  /// 현재 입력창의 값과 새로운 값이 동일하면
  /// 아무 작업도 하지 않는다.
  ///
  /// 이 비교가 중요한 이유는
  /// 매번 controller.value를 변경하면
  /// 사용자가 입력 중인 커서 위치가 강제로 이동할 수 있기 때문이다.
  void _syncController({
    required TextEditingController controller,
    required String value,
  }) {
    // 이미 동일한 값이면 불필요한 업데이트를 하지 않는다.
    if (controller.text == value) {
      return;
    }

    // 새로운 텍스트를 입력창에 반영한다.
    controller.value =
        controller.value.copyWith(
      text: value,

      // 값이 변경된 뒤 커서를 텍스트 마지막으로 이동한다.
      selection:
          TextSelection.collapsed(
        offset: value.length,
      ),

      // 기존 composing 상태를 초기화한다.
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    // ─────────────────────────────────────────
    // Controller 리소스 정리
    // ─────────────────────────────────────────
    //
    // TextEditingController는 화면이 종료될 때
    // 반드시 dispose해야 한다.

    _brandController.dispose();
    _productNameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    _barcodeController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 현재 폼 상태를 구독한다.
    //
    // 입력값 또는 submit 상태가 변경되면
    // 화면이 다시 그려진다.
    final form = ref.watch(
      gifticonFormControllerProvider,
    );

    // 실제 상태 변경은 notifier를 통해 수행한다.
    //
    // TextField onChanged에서
    // controller.setBrand()
    // controller.setPrice()
    // 등을 호출한다.
    final controller = ref.read(
      gifticonFormControllerProvider.notifier,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ─────────────────────────────────────────
        // 필수 입력 안내
        // ─────────────────────────────────────────
        //
        // 별표(*)가 붙은 항목은 저장에 필요한 필수 입력값이다.
        Container(
          margin: const EdgeInsets.only(
            bottom: 16,
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.08),
            borderRadius:
                BorderRadius.circular(12),
          ),
          child: Text(
            '* 표시된 항목은 필수 입력 항목입니다.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),

        // ─────────────────────────────────────────
        // 브랜드명
        // ─────────────────────────────────────────
        //
        // OCR 결과가 있다면 자동으로 채워진다.
        // 사용자가 수정하면 setBrand()를 통해
        // Riverpod 상태도 함께 변경된다.
        _labeledField(
          label: '브랜드명 *',
          hint: '예: 스타벅스',
          controller: _brandController,
          onChanged: controller.setBrand,
        ),

        // ─────────────────────────────────────────
        // 상품명
        // ─────────────────────────────────────────
        _labeledField(
          label: '상품명 *',
          hint: '예: 아메리카노 T',
          controller:
              _productNameController,
          onChanged:
              controller.setProductName,
        ),

        // ─────────────────────────────────────────
        // 금액
        // ─────────────────────────────────────────
        //
        // 숫자만 입력할 수 있도록 제한한다.
        //
        // 실제 저장 시에는 GifticonFormState.parsedPrice가
        // 문자열을 int로 변환한다.
        _labeledField(
          label: '금액(원) *',
          hint: '예: 4500 (무료/사은품은 0)',
          controller: _priceController,
          keyboardType:
              TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter
                .digitsOnly,
          ],
          onChanged: controller.setPrice,
        ),

        // ─────────────────────────────────────────
        // 카테고리
        // ─────────────────────────────────────────
        //
        // 입력하지 않아도 저장은 가능하다.
        // submit()에서 빈 값이면 "기타"로 자동 보정한다.
        _labeledField(
          label: '카테고리',
          hint:
              '미입력 시 "$kDefaultCategory"로 저장',
          controller:
              _categoryController,
          onChanged:
              controller.setCategory,
        ),

        // ─────────────────────────────────────────
        // 바코드
        // ─────────────────────────────────────────
        //
        // ML Kit이 바코드를 인식하면 자동으로 채워진다.
        // 인식되지 않은 경우 사용자가 직접 입력할 수도 있다.
        _labeledField(
          label: '바코드',
          hint:
              '바코드 번호가 자동으로 입력됩니다.',
          controller:
              _barcodeController,
          keyboardType:
              TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter
                .digitsOnly,
          ],
          onChanged:
              controller.setBarcode,
        ),

        const SizedBox(height: 8),

        // ─────────────────────────────────────────
        // 유효기간
        // ─────────────────────────────────────────
        //
        // TextField 대신 날짜 선택기를 사용한다.
        //
        // 선택한 날짜는 Riverpod 상태의
        // expiryDate에 저장된다.
        _ExpiryDateField(
          value: form.expiryDate,
          onPicked:
              controller.setExpiryDate,
        ),

        const SizedBox(height: 24),

        // ─────────────────────────────────────────
        // 저장 오류 메시지
        // ─────────────────────────────────────────
        //
        // submit 상태가 Failure인 경우에만 표시한다.
        if (form.submit
            is ScanSubmitFailure)
          Padding(
            padding:
                const EdgeInsets.only(
              bottom: 12,
            ),
            child: Text(
              (form.submit
                      as ScanSubmitFailure)
                  .message,
              style: const TextStyle(
                color: Colors.red,
              ),
            ),
          ),

        // ─────────────────────────────────────────
        // 저장 버튼
        // ─────────────────────────────────────────
        //
        // 저장 버튼을 누르면
        //
        // controller.submit()
        // → validate()
        // → Gifticon 생성
        // → Repository 저장
        //
        // 순서로 진행된다.
        FilledButton(
          // 저장 중에는 버튼을 비활성화한다.
          //
          // 중복 저장 요청을 방지하기 위한 처리다.
          onPressed:
              form.submit
                      is ScanSubmitInProgress
                  ? null
                  : () async {
                      // Controller에서 검증 및 저장을 수행한다.
                      final saved =
                          await controller
                              .submit();

                      // 저장 성공 시 saved가 반환된다.
                      if (saved != null &&
                          context.mounted) {
                        // 사용자에게 저장 성공 메시지를 표시한다.
                        ScaffoldMessenger
                                .of(context)
                            .showSnackBar(
                          SnackBar(
                            content: Text(
                              '저장됨: '
                              '${saved.brand} '
                              '${saved.productName}',
                            ),
                          ),
                        );

                        // 저장 완료 후 폼 화면을 닫는다.
                        //
                        // maybePop(saved)를 사용하면
                        // 이전 화면에서 저장된 Gifticon을
                        // 결과값으로 받을 수도 있다.
                        Navigator.of(context)
                            .maybePop(saved);
                      }
                    },

          // 저장 중에는 로딩 인디케이터를 표시한다.
          child: form.submit
                  is ScanSubmitInProgress
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text('저장'),
        ),
      ],
    );
  }

  /// 공통 입력 필드.
  ///
  /// 기존 initialValue 방식 대신
  /// [TextEditingController]를 사용한다.
  ///
  /// 따라서 화면이 이미 열린 상태에서도
  /// OCR/바코드 인식 결과를 입력창에 반영할 수 있다.
  ///
  /// 입력 흐름:
  ///
  /// 사용자가 입력
  ///      ↓
  /// onChanged
  ///      ↓
  /// GifticonFormController
  ///      ↓
  /// GifticonFormState 변경
  ///
  /// 반대로 OCR 결과가 들어오는 경우:
  ///
  /// OCR
  ///      ↓
  /// GifticonFormState 변경
  ///      ↓
  /// _syncController()
  ///      ↓
  /// TextField에 표시
  Widget _labeledField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required ValueChanged<String>
        onChanged,
    TextInputType? keyboardType,
    List<TextInputFormatter>?
        inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: TextFormField(
        // 입력창의 현재 텍스트를 관리한다.
        controller: controller,

        // 숫자 키패드 등 입력 타입을 지정한다.
        keyboardType: keyboardType,

        // 숫자만 입력 허용 등의 입력 제한.
        inputFormatters:
            inputFormatters,

        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border:
              const OutlineInputBorder(),
        ),

        // 사용자가 입력할 때마다
        // Riverpod 폼 상태도 업데이트한다.
        onChanged: onChanged,
      ),
    );
  }
}

/// 유효기간(만료일) 선택 필드.
///
/// 일반 TextField 대신 날짜 선택기를 사용한다.
///
/// 사용자가 날짜를 선택하면
///
/// DatePicker
///   ↓
/// onPicked(DateTime)
///   ↓
/// GifticonFormController.setExpiryDate()
///   ↓
/// GifticonFormState.expiryDate
///
/// 로 저장된다.
class _ExpiryDateField
    extends StatelessWidget {
  const _ExpiryDateField({
    required this.value,
    required this.onPicked,
  });

  /// 현재 선택된 유효기간.
  final DateTime? value;

  /// 날짜를 선택했을 때 호출할 콜백.
  final ValueChanged<DateTime>
      onPicked;

  @override
  Widget build(BuildContext context) {
    // 날짜가 아직 선택되지 않았다면
    // "유효기간 선택 *"을 표시한다.
    //
    // 날짜가 선택되었다면
    // YYYY-MM-DD 형태로 표시한다.
    final label = value == null
        ? '유효기간 선택 *'
        : '유효기간: '
            '${value!.year}-'
            '${value!.month.toString().padLeft(2, '0')}-'
            '${value!.day.toString().padLeft(2, '0')}';

    return OutlinedButton.icon(
      icon: const Icon(
        Icons.calendar_today,
      ),
      label: Text(label),

      // 버튼을 누르면 날짜 선택기를 연다.
      onPressed: () async {
        final now = DateTime.now();

        // 현재 선택된 날짜가 있다면
        // 해당 날짜를 DatePicker의 초기 날짜로 사용한다.
        //
        // 아직 선택하지 않았다면 오늘 날짜를 사용한다.
        final picked =
            await showDatePicker(
          context: context,
          initialDate:
              value ?? now,

          // 현재 날짜보다 1년 이전 날짜까지 선택 가능.
          //
          // 필요하면 계약 정책에 맞게 변경할 수 있다.
          firstDate:
              DateTime(now.year - 1),

          // 현재 날짜 기준 5년 뒤까지 선택 가능.
          lastDate:
              DateTime(now.year + 5),
        );

        // 사용자가 날짜를 선택하지 않고 취소한 경우
        // null이 반환된다.
        //
        // null이면 상태를 변경하지 않는다.
        if (picked != null) {
          // 선택한 날짜를 부모 Controller에 전달한다.
          onPicked(picked);
        }
      },
    );
  }
}