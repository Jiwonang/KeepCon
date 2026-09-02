/// scan — 세 경로(스캔·갤러리·수동 입력)가 **공통으로 도착하는** 저장 폼 화면.
///
/// `scan_page.dart`에서 떼어냈다(그 파일이 1,455줄이라 화면 둘이 한곳에 있었다).
///
/// ℹ️ 옮기면서 `_GifticonFormScreen` → [GifticonFormScreen]으로 공개됐다. 그래도
/// 테스트는 **원칙적으로 `ScanPage`에서 내비게이션을 타고 도달**한다 — 이 폼은 폼 상태
/// 컨트롤러의 세션(`startWith`)을 전제하므로, 직접 pump하면 실제 경로가 만들지 않는
/// 상태에서 검증하게 된다.
///
/// 예외는 **갤러리 도착 상태** 하나다 — `ScanPage._openForm`이 `ImagePicker()`를
/// 안에서 직접 만들어 주입점이 없으므로, 갤러리 경로 테스트는 그 경로가 컨트롤러에
/// 하는 일(`startWith` → `prefillFromRecognition`)을 그대로 재현한 뒤 직접 pump한다
/// (`scan_form_screen_test.dart`의 `openGalleryForm` 참조 — 세션 재현 없는 직접
/// pump의 근거가 아니다).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/features/scan/util/expiry_date_range.dart';
import 'package:keepcon/features/scan/util/keep_all_ko.dart';
import 'package:keepcon/features/scan/util/price_input_formatter.dart';
import 'package:keepcon/features/scan/util/save_result_message.dart';
import 'package:keepcon/features/scan/widgets/result_dialog.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/providers/now_provider.dart';
import 'package:keepcon/shared/util/expiry_policy.dart';
import 'package:keepcon/shared/theme/theme_tokens.dart';
import 'package:keepcon/shared/util/date_format.dart';

class GifticonFormScreen extends ConsumerStatefulWidget {
  const GifticonFormScreen({super.key});

  @override
  ConsumerState<GifticonFormScreen> createState() => _GifticonFormScreenState();
}

class _GifticonFormScreenState extends ConsumerState<GifticonFormScreen> {
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

  /// 갤러리 이미지에서 바코드를 읽지 못한 채 폼이 열렸는지.
  ///
  /// 이 상태로 도착할 수 있는 경로는 갤러리뿐이다 — 카메라는 바코드를 인식해야만
  /// 폼이 열리고, 직접 입력은 애초에 이미지가 없다. 그런데 바코드는 계약상
  /// nullable이라 빈 채로도 검증을 통과해 그대로 저장되고, 사용자는 매장에서
  /// 제시할 것이 없다는 사실을 그때야 안다. 그래서 이 경우만 필드에 안내를 단다.
  ///
  /// 판정은 열리는 시점에 한 번 고정한다 — "이미지에서 못 읽었다"는 과거의
  /// 사실이라 이후 입력으로 변하지 않는다. 표시 여부만 입력에 따라 갈린다
  /// (직접 채우면 안내가 할 일을 다한 것이므로 숨긴다 — 바코드 필드를 감싼
  /// [ValueListenableBuilder]가 그 전환을 필드 범위에서만 다시 그린다).
  late final bool _barcodeUnreadFromImage;

  @override
  void initState() {
    super.initState();
    final initialState = ref.read(gifticonFormControllerProvider);

    // trim으로 판정한다 — 표시 조건(바코드 필드의 helperText)과 같은 기준이어야
    // 한다. 판정만 trim 없이 보면, 공백뿐인 값이 프리필됐을 때(현재 갤러리
    // 프리필은 trim된 값이지만 그 계약은 이 파일 밖의 구현 사정이다) 안내 없이
    // 저장 단계에서 null로 접혀 침묵 저장된다 — 이 안내가 막으려는 바로 그 결과다.
    _barcodeUnreadFromImage = initialState.source == ScanSource.gallery &&
        initialState.barcode.trim().isEmpty;

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

    // 폼이 들고 있는 값이 피커가 받아들이는 범위 밖일 수 있다 — 그 값은 사용자가
    // 고른 것이 아니라 **OCR이 프리필한 것**이기 때문이다. 파서는 이미지에 적힌
    // 것을 그대로 읽으므로 2020년 이전도 낸다(픽스처 테스트가
    // `DateTime(2016, 2, 12)`로 못박고 있다).
    //
    // `showDatePicker`는 `initialDate`가 범위 밖이면 **assert로 죽는다.** 그래서
    // 여기서 좁혀 넣는다 — 값 자체는 폼에 그대로 두고, 피커를 여는 시작 위치만
    // 조정한다(클램프한 값을 저장하지 않는다. 사용자가 고르지 않은 날짜를
    // 조용히 바꿔 넣는 셈이 된다).
    final DateTime initialDate = _clampToSelectableRange(
      currentState.expiryDate ?? ref.read(nowProvider),
    );

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: expirySelectableFrom,
      lastDate: expirySelectableTo,
    );

    if (picked != null) {
      formNotifier.setExpiryDate(picked);
    }
  }

  /// [date]를 피커가 받아들이는 범위로 좁힌다.
  DateTime _clampToSelectableRange(DateTime date) {
    if (date.isBefore(expirySelectableFrom)) return expirySelectableFrom;
    if (date.isAfter(expirySelectableTo)) return expirySelectableTo;
    return date;
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
      // 저장은 성공했다. 다만 **그룹 공유는 별개의 결과**라 함께 알린다.
      //
      // 예전에는 세 경우가 모두 같은 문구였다 — 지갑에 넣었을 때도, 그룹에
      // 공유됐을 때도, **공유만 실패했을 때도.** 그래서 사용자는 자기가 고른
      // 그룹에 실제로 들어갔는지 알 수 없었고, 부분 실패는 조용히 묻혔다
      // (상태에는 `sharedGroupName`·`shareError`가 담겨 있는데 화면이 안 썼다).
      case ScanSubmitSuccess(
          :final String? shareError,
          :final String? sharedGroupName,
          :final bool sharedToGroup,
        ):
        messenger.showSnackBar(
          SnackBar(
            content: KeepAllText(
              saveResultMessage(
                shareError: shareError,
                sharedGroupName: sharedGroupName,
                // 이름을 못 읽어도 공유됐다는 사실은 알려야 한다 — 안 그러면
                // 지갑 저장과 같은 문구가 되어 이 화면이 고치려던 상태로 돌아간다.
                sharedToGroup: sharedToGroup,
              ),
            ),
            // 공유 실패는 저장 성공과 함께 오므로 놓치기 쉽다. 읽을 시간을 준다.
            duration: shareError == null
                ? const Duration(seconds: 4)
                : const Duration(seconds: 6),
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
            final TextStyle? mutedStyle =
                ScanResultDialog.mutedStyle(dialogTheme);

            return AlertDialog(
              insetPadding: ScanResultDialog.insetPadding(dialogContext),
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
        // 사용자가 그 자리에서 번호를 고칠 수 있는 도착이면 화면에 머무르며
        // 바코드 필드 아래에 빨간 문구로 알린다. 직접 입력만이 아니라
        // **갤러리-미인식 도착도 여기다** — 그 바코드는 위 안내를 보고 사용자가
        // 손으로 친 값이라, 홈으로 내쫓으면 함께 채운 입력이 통째로 사라지고
        // 정작 고칠 수 있는 번호는 고칠 기회를 잃는다.
        if (formState.source == ScanSource.manual || _barcodeUnreadFromImage) {
          setState(() {
            _duplicateBarcode = _barcodeController.text.trim();
          });
          _formKey.currentState?.validate();
          return;
        }

        // 카메라/갤러리-인식은 인식된 이미지·바코드가 이미 화면에 떠 있어 필드
        // 문구로 고칠 것이 없다. 홈으로 돌려보낸 뒤 팝업으로 알린다.
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
            // 배치 규약은 한도 다이얼로그와 **공유한다**([ScanResultDialog]) — 형제인데
            // 여백·행간이 어긋나면 같은 화면군에서 폭이 들쭉날쭉해 보인다.
            final TextStyle? mutedStyle =
                ScanResultDialog.mutedStyle(dialogTheme);

            return AlertDialog(
              insetPadding: ScanResultDialog.insetPadding(dialogContext),
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
        // 가리키는 지점이 여기인데 정작 빠져 있었다 — 형제 스낵바 셋(이 파일의
        // 필수항목 안내·저장 결과 안내와 `scan_page.dart`의 이미지 처리 실패)은
        // 모두 [KeepAllText]다. 그래서 문구가 길어질수록 이 스낵바만 어절이
        // 갈라졌다('네트'/'워크').
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

    // 날짜 표기는 공유 정본([formatYmdDot])을 쓴다 — 손으로 조립하면 여기만
    // 갈라진다. 실제로 그랬다: 이 라벨이 `lib/` 전체에서 유일하게 `2026-09-30`
    // 이었고, **같은 화면의 중복 등록 다이얼로그**(위 `_DuplicateDialog`)조차
    // `2026.09.30`을 쓰고 있었다. 같은 유효기간이 한 화면에서 두 모양으로 보였다.
    final String expiryDateText = formState.expiryDate != null
        ? formatYmdDot(formState.expiryDate!)
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
              // [ValueListenableBuilder]로 감싸는 이유: helperText가 컨트롤러의
              // 현재 입력에 달려 있는데, 필드 내부의 재검증 rebuild는 부모가
              // 만들어 둔 decoration 인스턴스를 다시 쓰므로 부모 쪽 rebuild가
              // 없으면 안내가 영영 안 지워진다. setState 리스너 대신 이 빌더인
              // 이유는 범위다 — 컨트롤러는 글자 변경만이 아니라 커서 이동·한글
              // 조합에도 notify하므로, setState로 받으면 가장 긴 필드를 손으로
              // 치는 바로 그 흐름에서 키 입력마다 폼 전체가 다시 그려진다.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _barcodeController,
                builder: (BuildContext context, TextEditingValue value, _) =>
                    TextFormField(
                  controller: _barcodeController,
                  keyboardType: TextInputType.number,
                  // 번호를 고치는 즉시 재검증돼 중복 안내가 사라진다.
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    labelText: '바코드 번호',
                    hintText: '숫자만 입력',
                    border: const OutlineInputBorder(),
                    // 갤러리에서 바코드를 못 읽고 왔을 때만. 사용자가 채우기
                    // 시작하면 숨긴다 — "직접 입력해 주세요"는 입력 전에만 맞는
                    // 안내다. 지난 날짜 안내(아래 유효기간 필드)와 달리 기본색으로
                    // 둔다 — 바코드는 계약상 선택 항목이라 경고가 아니라 상황
                    // 설명이다.
                    helperText:
                        _barcodeUnreadFromImage && value.text.trim().isEmpty
                            ? '이미지에서 바코드를 읽지 못했어요. 직접 입력해 주세요.'
                            : null,
                    helperMaxLines: 2,
                  ),
                  validator: (String? input) {
                    final String trimmed = input?.trim() ?? '';

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
                  // 지난 날짜는 **막지 않고 알린다.** `GifticonStatus.expired`가
                  // 계약상 정상 상태라(`available → expired` 전이가 정의돼 있다)
                  // 이미 만료된 것을 기록해 두는 것도 정당한 사용이다. 진짜
                  // 위험은 OCR이 잘못 읽은 날짜를 사용자가 모르고 저장하는 쪽이라,
                  // 저장을 막는 대신 눈에 띄게 해 준다.
                  //
                  // 시각은 계약 정본 [nowProvider]에서 받는다 — 여기서
                  // `DateTime.now()`를 직접 읽으면 자정 경계에서 화면과 다른
                  // 소비자의 판정이 갈린다(main이 같은 이유로 그렇게 한다).
                  // 판정 대상은 `field.value`가 아니라 **폼 상태의 날짜**다.
                  // [FormField]는 자기 내부 값을 들고 있어서 `initialValue` 이후
                  // 컨트롤러가 바뀌어도 따라오지 않는다 — OCR 프리필은 폼이 열리기
                  // 전에 상태에 들어가므로 둘이 갈라질 수 있다.
                  final DateTime? expiry = formState.expiryDate;
                  final String? pastNotice = expiry != null &&
                          isExpiredByDate(expiry, now: ref.watch(nowProvider))
                      ? '이미 지난 날짜예요. 맞는지 확인해 주세요.'
                      : null;

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
                        // `errorText`가 있으면 Material이 helper를 감춘다 — 값이
                        // 아예 없을 때(필수 항목 안내)와 값은 있는데 지난 날짜일
                        // 때가 겹치지 않으므로 그대로 둔다.
                        helperText: pastNotice,
                        helperMaxLines: 2,
                        // 경고용 색이 팔레트에 따로 없다. 테두리는 정상으로 두고
                        // 글자만 danger로 칠해 "막힌 것이 아니라 확인하라"는
                        // 뜻이 되게 한다.
                        helperStyle: TextStyle(color: theme.colorScheme.error),
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
                child: Text(
                  // 진행 중에는 문구로 알린다. 저장은 목록 조회 + (한도 상황이면)
                  // 플랜 서버 확인 + (그룹 공유면) 이름 조회까지 물려 수십 초가
                  // 걸릴 수 있는데, 버튼 비활성만으로는 죽은 화면과 구분되지
                  // 않아 사용자가 뒤로가기로 이탈한다.
                  //
                  // ⚠️ 앱의 다른 제출 버튼들(auth 3곳·share 1곳)은 버튼 안
                  // 스피너(22×22)를 쓴다 — 여기가 문구인 것은 **의도된 이탈**이다.
                  // 이 버튼의 대기는 저쪽(1~2초 왕복)과 달리 수십 초까지 갈 수
                  // 있어, 회전만 보여주는 것보다 무엇을 하는 중인지 말로 알리는
                  // 쪽을 골랐다(문구는 소유자 확정). 스피너로 통일하려면 형제들의
                  // 22×22 리터럴 관례를 그대로 따르면 된다 — 크기 토큰 부재가
                  // 장벽인 것은 아니다.
                  formState.submit is ScanSubmitInProgress ? '저장 중…' : '저장하기',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
