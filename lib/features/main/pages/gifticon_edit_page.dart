/// main 페이지 — 내 기프티콘 내용 수정.
///
/// 상세 화면의 수정 버튼에서 열린다. 고칠 수 있는 것은 계약 [GifticonDetails]의 다섯
/// 필드(브랜드·상품명·바코드·금액·카테고리)뿐이다. 만료일은 연장 정책을 따르는 별도
/// 경로이고, 이미지는 범위 밖이다(사용자 결정).
///
/// ## 등록 폼을 재사용하지 않는 이유
/// scan의 `GifticonFormScreen`은 스캔 출처·무료 한도 게이트·공유 대상 그룹·저장 뒤 공유를
/// 한 컨트롤러([GifticonFormController])에 묶고 있고, 이미 등록한 기프티콘에는 그 전부가
/// 해당하지 않는다. 그 분기를 수정 모드로 다시 가르는 비용이 이 화면보다 크다. 대신
/// 입력 규칙이 갈라지지 않도록 금액 포매터와 카테고리 선택지는 `lib/shared`로 승격해
/// 같은 것을 쓰고, 저장 판정은 계약 [GifticonDetails.normalized]에 맡긴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/diagnostics/error_reporter.dart';
import '../../../shared/diagnostics/report_handled_failure.dart';
import '../../../shared/models/gifticon.dart';
import '../../../shared/models/gifticon_category.dart';
import '../../../shared/models/share.dart';
import '../../../shared/providers/error_reporter_provider.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/providers/shared_gifticons_provider.dart';
import '../../../shared/repositories/gifticon_repository.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../../../shared/util/money_format.dart' show parseWonInput;
import '../../../shared/util/price_input_formatter.dart';
import '../state/gifticon_list_providers.dart';

/// 수정 화면이 닫힌 이유. 상세 화면이 안내와 후속 처리를 고른다.
enum GifticonEditResult {
  /// 저장했다.
  saved,

  /// 저장하려고 보니 기프티콘이 이미 없다(다른 기기가 지웠다).
  gone,
}

/// 기프티콘 수정 화면. 저장에 성공하면 [GifticonEditResult]를 돌려주며 닫힌다.
class GifticonEditPage extends ConsumerStatefulWidget {
  const GifticonEditPage({super.key, required this.gifticon});

  /// 수정할 기프티콘. 입력칸의 초기값이다.
  final Gifticon gifticon;

  @override
  ConsumerState<GifticonEditPage> createState() => _GifticonEditPageState();
}

class _GifticonEditPageState extends ConsumerState<GifticonEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _brandController;
  late final TextEditingController _productNameController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _priceController;
  late String _category;
  bool _saving = false;

  /// 다른 기프티콘이 이미 쓰는 것으로 확인된 번호. 번호를 고치는 즉시 안내가 사라진다.
  String? _duplicateBarcode;

  @override
  void initState() {
    super.initState();
    final Gifticon g = widget.gifticon;
    _brandController = TextEditingController(text: g.brand);
    _productNameController = TextEditingController(text: g.productName);
    _barcodeController = TextEditingController(text: g.barcode ?? '');
    _priceController =
        TextEditingController(text: formatThousands(g.price.toString()));
    // 카테고리는 계약상 비어 있으면 안 되지만, 손상 문서는 빈 값으로 읽힌다. 그대로 두면
    // 사용자가 고를 수 없는 값 때문에 저장이 막힌다.
    _category =
        g.category.trim().isEmpty ? GifticonCategory.etc.label : g.category;
  }

  @override
  void dispose() {
    _brandController.dispose();
    _productNameController.dispose();
    _barcodeController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  /// 입력칸의 금액. 비우면 0원이고(등록 폼과 같다), 해석할 수 없으면 `null`.
  int? get _parsedPrice => parseWonInput(_priceController.text);

  /// 선택지. 저장된 값이 목록에 없으면(레거시 `카페` 등) 함께 보여 준다 — 빼면 수정 화면을
  /// 열고 저장하는 것만으로 값이 바뀌고, 그 값으로 걸어 둔 홈 필터에서 사라진다.
  List<String> get _categoryOptions {
    final List<String> labels = <String>[
      for (final GifticonCategory c in GifticonCategory.values) c.label,
    ];
    final String original = widget.gifticon.category;
    return original.trim().isEmpty || labels.contains(original)
        ? labels
        : <String>[original, ...labels];
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 기다리는 사이 사용자가 이미 뒤로 갔으면 닫지 않는다 — 그대로 pop하면 아래 화면을
  /// 닫는다(상세 화면의 삭제 경로와 같은 이유).
  void _closeWith(GifticonEditResult result) {
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop(result);
    }
  }

  /// [barcode]를 **다른** 기프티콘이 쓰고 있는지 확인한다. 확인하지 못하면 `null`.
  ///
  /// 등록 폼의 중복 검사(모든 상태 대상)와 같은 조건이다 — 여기가 없으면 "다른 번호로
  /// 등록 → 수정으로 같은 번호"가 그 검사를 우회한다. 자기 자신은 뺀다.
  Future<bool?> _isBarcodeTaken(String barcode, ErrorReporter reporter) async {
    try {
      final List<Gifticon> mine = await ref
          .read(gifticonRepositoryProvider)
          .getGifticons(widget.gifticon.ownerId);
      return mine.any(
        (Gifticon g) => g.id != widget.gifticon.id && g.barcode == barcode,
      );
    } catch (e, st) {
      reportHandledFailureTo(reporter, e, st,
          context: 'GifticonEditPage.duplicateCheck');
      return null;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    // 지난번 중복 판정은 그때의 사실이다 — 그 사이 상대 기프티콘이 지워졌을 수 있으므로
    // 저장할 때마다 다시 확인한다(아래 [_isBarcodeTaken]).
    _duplicateBarcode = null;
    if (!_formKey.currentState!.validate()) return;
    final Gifticon g = widget.gifticon;
    final GifticonDetails details = GifticonDetails(
      brand: _brandController.text,
      productName: _productNameController.text,
      price: _parsedPrice!,
      barcode: _barcodeController.text,
      category: _category,
    ).normalized();

    // 바뀐 것이 없으면 쓰지 않는다. 공유 중이 아닌지 묻거나 서버를 다녀올 이유가 없다.
    if (details.brand == g.brand &&
        details.productName == g.productName &&
        details.price == g.price &&
        details.barcode == g.barcode &&
        details.category == g.category) {
      Navigator.of(context).pop();
      return;
    }

    // 공유 판정을 저장 시점에 **다시 읽는다** — 이 화면이 열려 있는 사이(몇 분일 수 있다)
    // 다른 기기가 그룹에 공유했을 수 있다.
    final AsyncValue<SharedGifticon?> shareState =
        ref.read(sharedItemForGifticonProvider(g.id));
    final String? blocked = shareBlockMessage(shareState, action: '수정');
    if (blocked != null) {
      // 스트림 provider는 스스로 재구독하지 않는다 — 다음 시도가 되살아나게 해 둔다.
      if (shareState.hasError) retrySharedGifticonIds(ref);
      _showSnack(blocked);
      return;
    }

    // 저장을 기다리는 사이 사용자가 뒤로 갈 수 있다. 화면이 없어도 결과를 남기고 알리도록
    // await 전에 잡는다(`report_handled_failure.dart`의 선택 기준).
    final ErrorReporter reporter = ref.read(errorReporterProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    void notify(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    setState(() => _saving = true);
    try {
      final String? barcode = details.barcode;
      // 그대로인 번호는 검사하지 않는다 — 이미 겹쳐 있는 옛 데이터가 다른 필드의 수정까지
      // 막으면 고칠 길이 없다.
      if (barcode != null && barcode != g.barcode) {
        final bool? taken = await _isBarcodeTaken(barcode, reporter);
        if (!mounted) return;
        if (taken == null) {
          _showSnack('바코드 중복을 확인하지 못했어요. 연결을 확인하고 다시 시도해 주세요.');
          return;
        }
        if (taken) {
          setState(() => _duplicateBarcode = barcode);
          _formKey.currentState!.validate();
          return;
        }
      }

      await ref.read(gifticonRepositoryProvider).updateDetails(g.id, details);
      if (!mounted) notify('수정했어요.');
      _closeWith(GifticonEditResult.saved);
    } on GifticonShareBlockedException catch (e, st) {
      // 화면 가드가 못 보는 공유(전에 나간 그룹)·경합을 백엔드가 막았다. 입력은 살려 둔다.
      reportHandledFailureTo(reporter, e, st,
          context: 'GifticonEditPage.updateDetails(share)');
      notify('공유 중인 그룹이 있어 수정할 수 없어요. '
          '전에 나간 그룹에 공유해 둔 것일 수 있어요.');
    } on StateError catch (e, st) {
      // 입력은 위 validate와 normalized()를 이미 통과했으므로 남는 것은 "문서 없음"이다.
      reportHandledFailureTo(reporter, e, st,
          context: 'GifticonEditPage.updateDetails(guard)');
      _closeWith(GifticonEditResult.gone);
    } catch (e, st) {
      // 수정도 트랜잭션이라 오프라인 큐잉이 되지 않는다. 입력을 살려 두고 재시도를 권한다.
      reportHandledFailureTo(reporter, e, st,
          context: 'GifticonEditPage.updateDetails');
      notify('저장하지 못했어요. 연결을 확인하고 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value, String message) =>
      (value == null || value.trim().isEmpty) ? message : null;

  @override
  Widget build(BuildContext context) {
    // 저장 시점의 `ref.read`가 살아 있는 값을 보도록 구독을 붙들어 둔다(autoDispose).
    ref.watch(sharedItemForGifticonProvider(widget.gifticon.id));

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('기프티콘 수정', style: context.navTitleStyle),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            children: <Widget>[
              TextFormField(
                controller: _brandController,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: '브랜드 / 사용처',
                  border: OutlineInputBorder(),
                ),
                validator: (String? v) => _required(v, '브랜드를 입력해 주세요.'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _productNameController,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: '상품명',
                  border: OutlineInputBorder(),
                ),
                validator: (String? v) => _required(v, '상품명을 입력해 주세요.'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _barcodeController,
                keyboardType: TextInputType.number,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: '바코드 번호',
                  border: OutlineInputBorder(),
                ),
                validator: (String? v) =>
                    v != null && v.trim() == _duplicateBarcode
                        ? '이미 등록된 바코드 번호입니다.'
                        : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                inputFormatters: const <TextInputFormatter>[
                  ThousandsSeparatorInputFormatter(),
                ],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: '금액 / 금액권 잔액 (선택)',
                  border: OutlineInputBorder(),
                ),
                validator: (_) => _parsedPrice == null ? '금액을 확인해 주세요.' : null,
              ),
              const SizedBox(height: 16),
              // `DropdownButtonFormField`를 쓰지 않는다 — 초기값 인자가 Flutter 버전에 따라
              // 다르다(`initialValue`는 pubspec 하한 3.29에 없고 `value`는 CI 버전에서
              // deprecated다). 값은 항상 유효해 폼 검증도 필요 없다.
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: '카테고리',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _category,
                    isDense: true,
                    isExpanded: true,
                    items: <DropdownMenuItem<String>>[
                      for (final String label in _categoryOptions)
                        DropdownMenuItem<String>(
                            value: label, child: Text(label)),
                    ],
                    onChanged: (String? v) {
                      if (v != null) setState(() => _category = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '저장 중…' : '저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
