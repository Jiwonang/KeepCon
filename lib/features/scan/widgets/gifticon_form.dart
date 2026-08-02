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

import '../../../shared/models/gifticon.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../../../shared/util/date_format.dart' show formatYmdDot;
import '../state/gifticon_form_state.dart';
import '../util/expiry_quick_pick.dart';
import '../util/price_input_formatter.dart';

/// 카테고리 빠른 선택 프리셋 (scan 페이지 로컬 상수).
///
/// 계약상 `Gifticon.category`는 **자유 문자열**이다(기본값 [kDefaultCategory]).
/// 따라서 이 목록은 "자주 쓰는 값을 한 번에 넣어 주는 입력 편의"일 뿐,
/// 계약이 허용하는 값의 집합이 아니다 — 사용자는 아래 입력창에 원하는
/// 카테고리를 직접 적을 수 있다.
///
/// 왜 lib/shared로 승격하지 않나 (CLAUDE.md '늦게 승격'):
/// 메인 페이지의 카테고리 필터는 저장된 데이터에서 카테고리를 **동적으로 도출**하므로
/// 이 프리셋 목록을 소비하지 않는다. 즉 두 번째 소비자가 없다.
/// (`_workspace/00_project_standards.md` — 카테고리 프리셋은 페이지 로컬)
///
/// 마지막 항목은 계약 기본값 [kDefaultCategory]와 같은 값이라
/// "미입력과 동일한 선택"을 명시적으로 할 수 있게 한다.
const List<String> kScanCategoryPresets = <String>[
  '카페',
  '치킨',
  '버거',
  '편의점',
  '상품권',
  kDefaultCategory,
];

/// 저장 완료 스낵바에 덧붙일 그룹 공유 결과 문구.
///
/// 세 가지 경우를 구분한다.
///
/// - '내 지갑' 저장(대상 그룹 없음) → 빈 문자열(추가 안내 없음)
/// - 그룹 공유 성공 → ' — 가족 그룹에 공유됨'(그룹명 미확인 시 ' — 그룹에 공유됨')
/// - 그룹 공유 실패 → ' — <shareError 완결 문장>'
///   (shareError가 이미 사용자용 완결 문장이므로 별도 라벨로 감싸지 않는다 —
///    "(그룹 공유 실패: 그룹에 공유하지 못했어요…)"처럼 실패가 이중 서술되는 것 방지)
///
/// 공유 실패는 **저장 실패가 아니다** — 기프티콘은 이미 내 목록에 저장돼 있고
/// 그룹 공유만 안 된 상태다(부분 실패 정책 — [GifticonFormController.submit] 참조).
String _shareNote(ScanSubmitSuccess success) {
  final String? error = success.shareError;

  if (error != null) {
    return ' — $error';
  }

  if (!success.sharedToGroup) {
    return '';
  }

  final String? name = success.sharedGroupName;

  return name == null ? ' — 그룹에 공유됨' : ' — $name 그룹에 공유됨';
}

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
class GifticonForm extends ConsumerStatefulWidget {
  const GifticonForm({super.key});

  @override
  ConsumerState<GifticonForm> createState() => _GifticonFormState();
}

class _GifticonFormState extends ConsumerState<GifticonForm> {
  // ─────────────────────────────────────────
  // TextEditingController
  // ─────────────────────────────────────────
  //
  // 각각의 입력창을 직접 관리한다.
  //
  // OCR 결과가 나중에 들어왔을 때
  // controller.text를 변경해 화면에 반영할 수 있다.

  late final TextEditingController _brandController;

  late final TextEditingController _productNameController;

  late final TextEditingController _priceController;

  late final TextEditingController _categoryController;

  late final TextEditingController _barcodeController;

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

    _brandController = TextEditingController(
      text: form.brand,
    );

    _productNameController = TextEditingController(
      text: form.productName,
    );

    _priceController = TextEditingController(
      text: form.price,
    );

    _categoryController = TextEditingController(
      text: form.category,
    );

    _barcodeController = TextEditingController(
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

        // 금액은 동기화할 때도 콤마 포맷을 거친다.
        //
        // 프로그래밍 방식 대입(controller.value =)은 inputFormatters를
        // 거치지 않으므로, OCR 프리필 값("12500")을 그대로 넣으면
        // 직접 입력("12,500")과 표시가 어긋난다.
        //
        // formatThousands는 비숫자를 먼저 제거하므로
        // 이미 포맷된 값("12,500")에도 안전하다(멱등).
        _syncController(
          controller: _priceController,
          value: formatThousands(next.price),
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
    controller.value = controller.value.copyWith(
      text: value,

      // 값이 변경된 뒤 커서를 텍스트 마지막으로 이동한다.
      selection: TextSelection.collapsed(
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

    // 저장 진행 중 여부.
    //
    // 저장/연속등록 두 버튼을 동시에 비활성화해
    // 중복 저장 요청을 막는다.
    final bool inProgress = form.submit is ScanSubmitInProgress;

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
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '* 표시된 항목은 필수 입력 항목입니다.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
          controller: _productNameController,
          onChanged: controller.setProductName,
        ),

        // ─────────────────────────────────────────
        // 금액
        // ─────────────────────────────────────────
        //
        // 입력 중 천 단위 콤마를 자동으로 붙인다("4500" → "4,500").
        //
        // ThousandsSeparatorInputFormatter가 비숫자 제거까지 담당하므로
        // 별도의 digitsOnly 포매터는 두지 않는다(동작이 완전히 중복된다).
        //
        // 상태에는 콤마가 포함된 문자열이 저장되지만,
        // 저장 시 GifticonFormState.parsedPrice가 콤마를 제거하고
        // int로 변환하므로 계약(price: int)에는 영향이 없다.
        _labeledField(
          label: '금액(원) *',
          hint: '예: 4,500 (무료/사은품은 0)',
          controller: _priceController,
          keyboardType: TextInputType.number,
          inputFormatters: const [
            ThousandsSeparatorInputFormatter(),
          ],
          onChanged: controller.setPrice,
        ),

        // ─────────────────────────────────────────
        // 카테고리
        // ─────────────────────────────────────────
        //
        // 프리셋 칩 + 자유 입력창을 함께 제공한다.
        //
        // - 칩을 누르면 입력창에도 그 값이 반영된다
        //   (setCategory → Riverpod 상태 → _syncController)
        // - 프리셋에 없는 카테고리는 입력창에 직접 적을 수 있다
        //
        // 입력하지 않아도 저장은 가능하다.
        // submit()에서 빈 값이면 "기타"로 자동 보정한다.
        _CategoryPresetChips(
          selected: form.category,
          onSelected: controller.setCategory,
        ),

        _labeledField(
          label: '카테고리',
          hint: '미입력 시 "$kDefaultCategory"로 저장',
          controller: _categoryController,
          onChanged: controller.setCategory,
        ),

        // ─────────────────────────────────────────
        // 바코드
        // ─────────────────────────────────────────
        //
        // ML Kit이 바코드를 인식하면 자동으로 채워진다.
        // 인식되지 않은 경우 사용자가 직접 입력할 수도 있다.
        //
        // 숫자 제한(digitsOnly)을 두지 않는다:
        // QR/CODE128 등은 URL·영문이 포함된 rawValue를 반환할 수 있어,
        // 숫자만 허용하면 사용자가 값을 수정하는 순간
        // 비숫자 문자가 전부 사라져 값이 손상된다.
        _labeledField(
          label: '바코드',
          hint: '바코드 번호가 자동으로 입력됩니다.',
          controller: _barcodeController,
          onChanged: controller.setBarcode,
        ),

        const SizedBox(height: 8),

        // ─────────────────────────────────────────
        // 유효기간
        // ─────────────────────────────────────────
        //
        // TextField 대신 날짜 선택기 + 빠른 선택 버튼을 사용한다.
        //
        // 선택한 날짜는 Riverpod 상태의
        // expiryDate에 저장된다.
        _ExpiryDateField(
          value: form.expiryDate,
          onPicked: controller.setExpiryDate,
        ),

        const SizedBox(height: 24),

        // ─────────────────────────────────────────
        // 저장 오류 메시지
        // ─────────────────────────────────────────
        //
        // submit 상태가 Failure인 경우에만 표시한다.
        if (form.submit is ScanSubmitFailure)
          Padding(
            padding: const EdgeInsets.only(
              bottom: 12,
            ),
            child: Text(
              (form.submit as ScanSubmitFailure).message,
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
          onPressed: inProgress ? null : () => _submitAndClose(controller),

          // 저장 중에는 로딩 인디케이터를 표시한다.
          child: inProgress
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text('저장'),
        ),

        const SizedBox(height: 8),

        // ─────────────────────────────────────────
        // 저장 후 연속 등록 (보조 버튼)
        // ─────────────────────────────────────────
        //
        // 기프티콘은 보통 여러 장을 한 번에 정리하므로,
        // 저장할 때마다 스캔 화면으로 돌아갔다 다시 들어오는 왕복을 없앤다.
        //
        // 저장 성공 후 화면을 닫지 않고 폼만 비운다.
        // 다음 세션은 직접 입력(manual)로 시작한다 — 이유는
        // _submitAndContinue doc 참조.
        //
        // 중복 저장 방지는 기본 저장 버튼과 동일하게
        // ScanSubmitInProgress 비활성화 패턴을 재사용한다
        // (같은 프레임 연타는 submit() 자체의 재진입 가드가 막는다).
        OutlinedButton(
          onPressed: inProgress ? null : () => _submitAndContinue(controller),
          child: const Text('저장 후 계속 등록'),
        ),
      ],
    );
  }

  /// 저장 공통 처리: submit → (성공 시) 저장 완료 스낵바.
  ///
  /// 반환:
  ///
  /// - 저장 성공 + 이 폼 세션이 아직 유효 → 저장된 [Gifticon]
  /// - 검증 실패 / 저장 실패 / 세션 무효(사용자가 폼을 떠남) → null
  ///
  /// [GifticonFormController.submit]은 세션이 무효화된 경우
  /// (await 중 startWith/reset이 실행된 경우) null을 반환하므로,
  /// 여기서 null이면 어떤 후속 동작(닫기/폼 비우기)도 하면 안 된다.
  ///
  /// 두 저장 버튼([_submitAndClose]/[_submitAndContinue])이 이 공통
  /// 프리픽스를 공유해, 가드·성공 메시지가 한 곳에서만 관리된다.
  Future<Gifticon?> _submitWithFeedback(
    GifticonFormController controller, {
    String suffix = '',
  }) async {
    // Controller에서 검증 및 저장을 수행한다.
    final Gifticon? saved = await controller.submit();

    // 저장 실패 시에는 폼에 오류 메시지가 표시되므로 화면을 유지한다.
    // 세션 무효 시에는 사용자가 이미 폼을 떠났으므로 아무것도 하지 않는다.
    if (saved == null || !mounted) return null;

    // 그룹 공유 결과는 제출 성공 상태에 담겨 온다.
    //
    // saved가 non-null이면 이 세션의 제출이 성공했다는 뜻이므로,
    // 여기서 읽는 submit 상태는 방금 그 제출의 ScanSubmitSuccess다.
    final ScanSubmitState submitState =
        ref.read(gifticonFormControllerProvider).submit;

    final String shareNote =
        submitState is ScanSubmitSuccess ? _shareNote(submitState) : '';

    // 사용자에게 저장 성공 메시지를 표시한다.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '저장됨: '
          '${saved.brand} '
          '${saved.productName}'
          '$shareNote'
          '$suffix',
        ),
      ),
    );

    return saved;
  }

  /// 저장 후 폼 화면을 닫는다(기본 흐름).
  ///
  /// 저장에 성공하면 이전 화면(ScanPage)에 저장된 [Gifticon]을 결과로 넘긴다.
  Future<void> _submitAndClose(GifticonFormController controller) async {
    final Gifticon? saved = await _submitWithFeedback(controller);

    if (saved == null || !mounted) return;

    // 심층 방어: 이 라우트가 아직 최상단일 때만 닫는다.
    //
    // 사용자가 저장 대기 중 뒤로가기로 이미 pop을 시작한 경우,
    // 라우트는 exit 애니메이션 동안 mounted로 남아 있어
    // 여기서 또 pop하면 아래 화면(ScanPage)까지 닫힌다.
    // (submit()의 세션 가드가 보통 먼저 거르지만, 이중으로 막는다)
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;

    // 저장 완료 후 폼 화면을 닫는다.
    //
    // maybePop(saved)를 사용하면
    // 이전 화면에서 저장된 Gifticon을
    // 결과값으로 받을 수도 있다.
    Navigator.of(context).maybePop(saved);
  }

  /// 저장 후 화면을 닫지 않고 다음 기프티콘 입력을 바로 시작한다.
  ///
  /// 흐름:
  ///
  /// submit()
  ///   ↓ 성공(세션 유효)
  /// 저장 완료 스낵바
  ///   ↓
  /// startWith(ScanSource.manual, targetGroupId: 이전 대상 그룹)
  ///   — 폼 상태 초기화(세션도 갱신), 저장 대상 그룹은 유지
  ///   ↓
  /// _syncController가 입력창을 비움
  ///
  /// 다음 세션의 source를 **manual로 고정**하는 이유:
  ///
  /// 연속 등록은 카메라 재스캔/갤러리 재선택 없이 곧바로 손으로
  /// 입력하는 흐름이다. 이전 source(camera/gallery)를 유지하면
  ///
  /// - 바코드/이미지 없는 저장이 "카메라/갤러리 출처"로 위장되고
  ///   (source의 의미 = 이 기프티콘 데이터가 어떻게 들어왔는가)
  /// - await 후 상태에서 source를 다시 읽어야 해서, 저장 대기 중
  ///   사용자가 이탈한 경우 stale 값을 읽는 레이스가 생긴다
  ///
  /// 화면 제목도 "기프티콘 직접 입력"으로 바뀌어 실제 입력 방식과 일치한다.
  /// 카메라로 다시 스캔하려면 폼을 닫고 카메라 카드를 다시 누르면 된다.
  ///
  /// 화면을 닫지 않으므로 ScanPage의 finally(reset)는
  /// 사용자가 최종적으로 폼을 나갈 때 한 번만 실행된다.
  Future<void> _submitAndContinue(GifticonFormController controller) async {
    // 저장 대상 그룹은 제출 **전에** 읽어 둔다.
    //
    // 연속 등록은 여러 장을 같은 그룹에 몰아 넣는 흐름이므로 대상 그룹을 그대로
    // 물려준다(source만 manual로 고정 — 아래 doc 참조). await 뒤에 상태를 다시
    // 읽으면 그 사이 세션이 바뀐 경우 stale 값을 읽게 되므로 미리 캡처한다.
    final String? targetGroupId =
        ref.read(gifticonFormControllerProvider).targetGroupId;

    final Gifticon? saved = await _submitWithFeedback(
      controller,
      suffix: ' — 이어서 등록할 수 있어요.',
    );

    if (saved == null || !mounted) return;

    // 이번 저장에서 그룹 공유가 실패했으면 다음 세션에 그 그룹을 물려주지 않는다.
    //
    // 실패 원인(그룹 소멸/비멤버)은 대부분 다음 저장에서도 반복되므로,
    // 그대로 상속하면 연속 등록 내내 저장마다 공유 실패가 반복된다 —
    // '내 지갑'으로 폴백해 저장 흐름은 끊기지 않게 한다.
    //
    // saved != null이므로 세션이 유효했고, startWith 전이라 아직 안 바뀌었다 —
    // 이 시점의 submit 상태는 이번 제출의 ScanSubmitSuccess다.
    final ScanSubmitState submit =
        ref.read(gifticonFormControllerProvider).submit;
    final bool shareFailed =
        submit is ScanSubmitSuccess && submit.shareError != null;

    // 다음 입력을 직접 입력 세션으로 시작한다(위 doc 참조).
    // 저장 대상 그룹은 공유가 성공했을 때만 유지한다.
    controller.startWith(
      ScanSource.manual,
      targetGroupId: shareFailed ? null : targetGroupId,
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
    required ValueChanged<String> onChanged,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
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
        inputFormatters: inputFormatters,

        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),

        // 사용자가 입력할 때마다
        // Riverpod 폼 상태도 업데이트한다.
        onChanged: onChanged,
      ),
    );
  }
}

// ─────────────────────── 카테고리 프리셋 칩 ───────────────────────

/// 카테고리 빠른 선택 칩 행.
///
/// [kScanCategoryPresets]의 값을 [ChoiceChip]으로 보여준다.
///
/// 흐름:
///
/// 칩 탭
///   ↓
/// onSelected(카테고리 문자열)
///   ↓
/// GifticonFormController.setCategory()
///   ↓
/// GifticonFormState.category 변경
///   ↓
/// _syncController → 아래 카테고리 입력창에도 반영
///
/// 이미 선택된 칩을 다시 누르면 빈 문자열로 되돌린다
/// (선택 해제 = 미입력 = 저장 시 [kDefaultCategory]로 보정).
class _CategoryPresetChips extends StatelessWidget {
  const _CategoryPresetChips({
    required this.selected,
    required this.onSelected,
  });

  /// 현재 폼 상태의 카테고리 값.
  ///
  /// 사용자가 입력창에 직접 적은 값일 수도 있으므로
  /// 프리셋과 일치하지 않으면 어떤 칩도 선택되지 않는다.
  final String selected;

  /// 칩을 눌렀을 때 호출할 콜백.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    // 입력창의 앞뒤 공백은 무시하고 비교한다
    // (submit()의 trim 보정과 판정 기준을 맞춘다).
    final String current = selected.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '카테고리 빠른 선택',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),

          // 화면 폭이 좁아도 줄바꿈되도록 Wrap을 사용한다.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String preset in kScanCategoryPresets)
                ChoiceChip(
                  label: Text(preset),
                  selected: current == preset,

                  // 선택 → 그 값, 선택 해제 → 빈 문자열(미입력).
                  onSelected: (bool isSelected) {
                    onSelected(isSelected ? preset : '');
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── 유효기간 선택 ───────────────────────

/// 유효기간(만료일) 선택 필드.
///
/// 일반 TextField 대신 날짜 선택기 + 빠른 선택 버튼을 사용한다.
///
/// 사용자가 날짜를 선택하면
///
/// DatePicker 또는 빠른 선택(+30일/+90일/+1년)
///   ↓
/// onPicked(DateTime)
///   ↓
/// GifticonFormController.setExpiryDate()
///   ↓
/// GifticonFormState.expiryDate
///
/// 로 저장된다.
class _ExpiryDateField extends StatelessWidget {
  const _ExpiryDateField({
    required this.value,
    required this.onPicked,
  });

  /// 현재 선택된 유효기간.
  final DateTime? value;

  /// 날짜를 선택했을 때 호출할 콜백.
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _datePickerButton(context),

        const SizedBox(height: 8),

        // ─────────────────────────────────────────
        // 유효기간 빠른 선택
        // ─────────────────────────────────────────
        //
        // 기프티콘 유효기간은 "오늘부터 N일/N년"으로 적혀 있는 경우가 많다.
        // DatePicker에서 날짜를 찾는 대신 버튼 하나로 계산한다.
        //
        // 계산 규칙(달력 기준·자정 정규화)은 ExpiryQuickPick.resolve가 소유한다.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final ExpiryQuickPick pick in ExpiryQuickPick.values)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.action),
                  ),
                ),

                // 기준일은 항상 "오늘"이다(이미 선택된 날짜에 누적하지 않는다 —
                // 버튼을 두 번 누르면 +60일이 되는 혼동을 막는다).
                onPressed: () => onPicked(pick.resolve(DateTime.now())),
                child: Text(pick.label),
              ),
          ],
        ),
      ],
    );
  }

  /// 날짜 선택기를 여는 버튼.
  Widget _datePickerButton(BuildContext context) {
    // 날짜가 아직 선택되지 않았다면
    // "유효기간 선택 *"을 표시한다.
    //
    // 날짜가 선택되었다면 공유 정본 formatYmdDot으로 YYYY.MM.DD 형태로 표시한다.
    // (구현이 이 파일에 인라인돼 있던 시절엔 구분자가 '-'여서, 같은 유효기간이
    //  등록 화면과 목록/공유 화면에서 다르게 보였다 — v2.4에서 다수 표기로 통일)
    final label = value == null ? '유효기간 선택 *' : '유효기간: ${formatYmdDot(value!)}';

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
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,

          // 현재 날짜보다 1년 이전 날짜까지 선택 가능.
          //
          // 필요하면 계약 정책에 맞게 변경할 수 있다.
          firstDate: DateTime(now.year - 1),

          // 현재 날짜 기준 5년 뒤까지 선택 가능.
          lastDate: DateTime(now.year + 5),
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