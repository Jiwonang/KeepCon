/// scan 폼 상태 및 컨트롤러.
///
/// 카메라/갤러리/수동 입력 세 경로가 모두 이 폼 상태로 수렴한다. 폼은 사용자가
/// 편집한 원시 입력(문자열 등)을 담고, 제출 시 계약 [Gifticon]으로 변환한다.
///
/// 계약 준수 포인트:
/// - 필수 필드(brand, productName, category, expiryDate)는 제출 전 검증한다.
/// - category 미분류 시 계약 기본값 "기타"를 넣는다(빈 문자열 금지).
/// - status는 항상 [GifticonStatus.available]로 시작한다(계약).
/// - ownerId는 현재 사용자 id로 채운다.
/// - id/registeredAt은 Repository 발급에 위임(빈 id/생성시각 채워 전달)한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/providers/repositories.dart';

/// scan 입력 경로 구분. 실제 데이터 생성은 세 경로 모두 동일한 폼→[Gifticon] 흐름이다.
enum ScanSource {
  /// 카메라 촬영 후 인식(OCR/바코드) → 폼 프리필. (플러그인 연동은 후속 TODO)
  camera,

  /// 갤러리 이미지 선택 후 인식 → 폼 프리필. (플러그인 연동은 후속 TODO)
  gallery,

  /// 사용자가 직접 입력.
  manual,
}

/// 카테고리 미분류 시 채우는 계약 기본값.
/// (매트릭스 §1: category 빈 문자열 금지 → "기타")
const String kDefaultCategory = '기타';

/// 폼 제출 결과.
sealed class ScanSubmitState {
  const ScanSubmitState();
}

/// 초기/미제출 상태.
class ScanSubmitIdle extends ScanSubmitState {
  const ScanSubmitIdle();
}

/// 제출 진행 중.
class ScanSubmitInProgress extends ScanSubmitState {
  const ScanSubmitInProgress();
}

/// 제출 성공 — 저장 후 확정된 [Gifticon](Repository 발급 id/registeredAt 포함).
class ScanSubmitSuccess extends ScanSubmitState {
  const ScanSubmitSuccess(this.saved);
  final Gifticon saved;
}

/// 제출 실패(검증 실패 또는 저장 오류).
class ScanSubmitFailure extends ScanSubmitState {
  const ScanSubmitFailure(this.message);
  final String message;
}

/// 폼의 편집 가능한 원시 상태. 불변 값 객체.
class GifticonFormState {
  const GifticonFormState({
    this.source = ScanSource.manual,
    this.brand = '',
    this.productName = '',
    this.price = '',
    this.barcode = '',
    this.category = '',
    this.expiryDate,
    this.imagePath,
    this.submit = const ScanSubmitIdle(),
  });

  final ScanSource source;
  final String brand;
  final String productName;

  /// 금액(원, KRW)의 원시 입력. 사용자가 편집하는 문자열(콤마 포함 가능).
  /// 제출 시 콤마 제거 후 [int]로 파싱해 계약 [Gifticon.price]에 채운다.
  /// 계약상 price는 필수(required int)이므로 빈 값은 검증 실패, 0은 허용(무료/사은품).
  final String price;
  final String barcode;
  final String category;
  final DateTime? expiryDate;
  final String? imagePath;
  final ScanSubmitState submit;

  GifticonFormState copyWith({
    ScanSource? source,
    String? brand,
    String? productName,
    String? price,
    String? barcode,
    String? category,
    DateTime? expiryDate,
    String? imagePath,
    ScanSubmitState? submit,
  }) {
    return GifticonFormState(
      source: source ?? this.source,
      brand: brand ?? this.brand,
      productName: productName ?? this.productName,
      price: price ?? this.price,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      expiryDate: expiryDate ?? this.expiryDate,
      imagePath: imagePath ?? this.imagePath,
      submit: submit ?? this.submit,
    );
  }

  /// 금액 원시 입력을 계약 [Gifticon.price]용 정수로 파싱한다.
  ///
  /// 콤마·공백을 제거한 뒤 [int]로 변환한다. 빈 값이거나 숫자로 파싱 불가하면
  /// null을 반환한다(검증에서 필수 위반으로 처리). 0은 유효(무료/사은품).
  int? get parsedPrice {
    final String digits = price.replaceAll(',', '').trim();
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  /// 필수 필드 검증. 통과 시 null, 실패 시 사용자용 메시지.
  ///
  /// 계약 필수 필드: brand, productName, price, expiryDate.
  /// category는 비어 있어도 기본값("기타")으로 보정되므로 검증 대상이 아니다.
  String? validate() {
    if (brand.trim().isEmpty) {
      return '브랜드명을 입력하세요.';
    }
    if (productName.trim().isEmpty) {
      return '상품명을 입력하세요.';
    }
    // 계약: price는 required int. 미입력/파싱 불가는 실패, 0(무료/사은품)은 허용.
    final int? parsed = parsedPrice;
    if (parsed == null) {
      return '금액(원)을 입력하세요.';
    }
    if (parsed < 0) {
      return '금액(원)은 0 이상이어야 합니다.';
    }
    if (expiryDate == null) {
      return '유효기간을 입력하세요.';
    }
    return null;
  }
}

/// 폼 상태를 관리하고 제출 시 계약 Repository로 저장하는 컨트롤러.
class GifticonFormController extends StateNotifier<GifticonFormState> {
  GifticonFormController(this._ref) : super(const GifticonFormState());

  final Ref _ref;

  /// 입력 경로를 지정하고 폼을 초기화한다.
  ///
  /// 카메라/갤러리 경로는 이후 인식 결과가 오면 [prefillFromRecognition]으로
  /// 필드를 채운다(현재는 플러그인 미연동 → 사용자가 수동 편집으로 폴백).
  void startWith(ScanSource source) {
    state = GifticonFormState(source: source);
  }

  /// 인식(OCR/바코드) 결과로 폼을 프리필한다. 인식 실패 필드는 그대로 두어
  /// 사용자가 수동으로 채우도록 폴백한다.
  ///
  /// TODO(scan): 카메라/갤러리 플러그인 연동 시, 추출 결과를 이 메서드로 전달한다.
  void prefillFromRecognition({
    String? brand,
    String? productName,
    String? price,
    String? barcode,
    String? category,
    DateTime? expiryDate,
    String? imagePath,
  }) {
    state = state.copyWith(
      brand: brand,
      productName: productName,
      price: price,
      barcode: barcode,
      category: category,
      expiryDate: expiryDate,
      imagePath: imagePath,
    );
  }

  void setBrand(String v) => state = state.copyWith(brand: v);
  void setProductName(String v) => state = state.copyWith(productName: v);
  void setPrice(String v) => state = state.copyWith(price: v);
  void setBarcode(String v) => state = state.copyWith(barcode: v);
  void setCategory(String v) => state = state.copyWith(category: v);
  void setExpiryDate(DateTime v) => state = state.copyWith(expiryDate: v);
  void setImagePath(String v) => state = state.copyWith(imagePath: v);

  /// 폼을 검증하고 계약 [Gifticon]으로 변환해 저장한다.
  ///
  /// 계약 메서드 [GifticonRepository.addGifticon](Gifticon) → Future<Gifticon> 호출.
  /// 성공 시 [ScanSubmitSuccess](저장 후 확정 인스턴스)로 상태를 갱신한다.
  Future<Gifticon?> submit() async {
    final String? error = state.validate();
    if (error != null) {
      state = state.copyWith(submit: ScanSubmitFailure(error));
      return null;
    }

    final currentUser = _ref.read(authRepositoryProvider).currentUser;
    if (currentUser == null) {
      state = state.copyWith(
        submit: const ScanSubmitFailure('로그인이 필요합니다.'),
      );
      return null;
    }

    state = state.copyWith(submit: const ScanSubmitInProgress());

    // 폼 원시 입력 → 계약 Gifticon 매핑. 필수 필드를 빠짐없이 채운다.
    final String category =
        state.category.trim().isEmpty ? kDefaultCategory : state.category.trim();
    final String? barcode =
        state.barcode.trim().isEmpty ? null : state.barcode.trim();

    final Gifticon draft = Gifticon(
      id: '', // Repository 발급에 위임(InMemoryGifticonRepository가 채움).
      ownerId: currentUser.id, // 현재 로그인 사용자 id.
      brand: state.brand.trim(),
      productName: state.productName.trim(),
      price: state.parsedPrice!, // validate로 non-null(>=0) 보장. 계약 required int.
      barcode: barcode, // nullable — 미입력 시 null.
      category: category, // 미분류 시 "기타".
      expiryDate: state.expiryDate!, // validate로 non-null 보장.
      registeredAt: DateTime.now(), // Repo가 발급하지 않으면 이 값 사용.
      status: GifticonStatus.available, // 계약: 신규는 항상 available.
      imagePath: state.imagePath, // nullable — 수동 입력은 이미지 없이 가능.
    );

    try {
      final Gifticon saved =
          await _ref.read(gifticonRepositoryProvider).addGifticon(draft);
      state = state.copyWith(submit: ScanSubmitSuccess(saved));
      return saved;
    } catch (e) {
      state = state.copyWith(
        submit: ScanSubmitFailure('저장에 실패했습니다: $e'),
      );
      return null;
    }
  }
}

/// 폼 컨트롤러 provider. 화면 진입마다 초기화되도록 autoDispose.
final gifticonFormControllerProvider = StateNotifierProvider.autoDispose<
    GifticonFormController, GifticonFormState>(
  (ref) => GifticonFormController(ref),
);
