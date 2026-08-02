/// scan 폼 상태 및 컨트롤러.
///
/// 카메라/갤러리/수동 입력 세 경로가 모두 이 폼 상태로 수렴한다.
///
/// 전체 데이터 흐름은 다음과 같다.
///
/// 카메라/갤러리/수동 입력
///         ↓
/// GifticonFormState
///         ↓
/// GifticonFormController
///         ↓
/// 사용자가 입력값 확인/수정
///         ↓
/// validate()
///         ↓
/// Gifticon 객체 생성
///         ↓
/// GifticonRepository.addGifticon()
///         ↓
/// (targetGroupId가 있는 경우) ShareRepository.shareGifticon()
///         ↓
/// 저장 완료 (공유 부분 실패 여부 포함)
///
/// 폼에서는 아직 저장 전이므로 사용자가 편집할 수 있는
/// 원시 데이터(String 등)를 보관한다.
///
/// 제출 시에는 이 원시 데이터를 계약 모델인 [Gifticon]으로 변환한다.
///
/// 계약 준수 포인트:
/// - 필수 필드(brand, productName, category, expiryDate)는 제출 전 검증한다.
/// - category 미분류 시 계약 기본값 "기타"를 넣는다(빈 문자열 금지).
/// - status는 항상 [GifticonStatus.available]로 시작한다(계약).
/// - ownerId는 현재 사용자 id로 채운다.
/// - id/registeredAt은 Repository 발급에 위임(빈 id/생성시각 채워 전달)한다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/providers/repositories.dart';

/// scan 입력 경로 구분.
enum ScanSource {
  camera,
  gallery,
  manual,
}

/// 카테고리 미분류 시 채우는 계약 기본값.
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

/// 제출 성공.
class ScanSubmitSuccess extends ScanSubmitState {
  const ScanSubmitSuccess(
    this.saved, {
    this.shareError,
    this.sharedGroupName,
  });

  final Gifticon saved;
  final String? shareError;
  final String? sharedGroupName;

  bool get sharedToGroup => saved.targetGroupId != null && shareError == null;
  String? get sharedGroupId => saved.targetGroupId;
}

/// 제출 실패.
class ScanSubmitFailure extends ScanSubmitState {
  const ScanSubmitFailure(this.message);

  final String message;
}

/// 폼의 편집 가능한 원시 상태.
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
    this.targetGroupId,
    this.submit = const ScanSubmitIdle(),
  });

  final ScanSource source;
  final String brand;
  final String productName;
  final String price;
  final String barcode;
  final String category;
  final DateTime? expiryDate;
  final String? imagePath;
  final String? targetGroupId;
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
    String? targetGroupId,
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
      targetGroupId: targetGroupId ?? this.targetGroupId,
      submit: submit ?? this.submit,
    );
  }

  int? get parsedPrice {
    final String digits = price.replaceAll(',', '').trim();
    if (digits.isEmpty) {
      return null;
    }
    return int.tryParse(digits);
  }

  String? validate() {
    if (brand.trim().isEmpty) {
      return '브랜드명을 입력하세요.';
    }
    if (productName.trim().isEmpty) {
      return '상품명을 입력하세요.';
    }
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

  void startWith(ScanSource source, {String? targetGroupId}) {
    state = GifticonFormState(
      source: source,
      targetGroupId: targetGroupId,
    );
  }

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

    debugPrint('===== GifticonForm 상태 변경 =====');
    debugPrint('source = ${state.source}');
    debugPrint('brand = ${state.brand}');
    debugPrint('productName = ${state.productName}');
    debugPrint('price = ${state.price}');
    debugPrint('barcode = ${state.barcode}');
    debugPrint('expiryDate = ${state.expiryDate}');
    debugPrint('imagePath = ${state.imagePath}');
    debugPrint('targetGroupId = ${state.targetGroupId}');
  }

  void setBrand(String v) => state = state.copyWith(brand: v);
  void setProductName(String v) => state = state.copyWith(productName: v);
  void setPrice(String v) => state = state.copyWith(price: v);
  void setBarcode(String v) => state = state.copyWith(barcode: v);
  void setCategory(String v) => state = state.copyWith(category: v);
  void setExpiryDate(DateTime v) => state = state.copyWith(expiryDate: v);
  void setImagePath(String v) => state = state.copyWith(imagePath: v);

  void reset() {
    state = const GifticonFormState();
  }

  Future<Gifticon?> submit() async {
    final String? error = state.validate();

    if (error != null) {
      state = state.copyWith(
        submit: ScanSubmitFailure(error),
      );
      return null;
    }

    final currentUser = _ref.read(authRepositoryProvider).currentUser;

    if (currentUser == null) {
      state = state.copyWith(
        submit: const ScanSubmitFailure(
          '로그인이 필요합니다.',
        ),
      );
      return null;
    }

    state = state.copyWith(
      submit: const ScanSubmitInProgress(),
    );

    final String category = state.category.trim().isEmpty
        ? kDefaultCategory
        : state.category.trim();

    final String? barcode =
        state.barcode.trim().isEmpty ? null : state.barcode.trim();

    final Gifticon draft = Gifticon(
      id: '',
      ownerId: currentUser.id,
      brand: state.brand.trim(),
      productName: state.productName.trim(),
      price: state.parsedPrice!,
      barcode: barcode,
      category: category,
      expiryDate: state.expiryDate!,
      registeredAt: DateTime.now(),
      status: GifticonStatus.available,
      imagePath: state.imagePath,
      targetGroupId: state.targetGroupId,
    );

    try {
      final Gifticon saved =
          await _ref.read(gifticonRepositoryProvider).addGifticon(draft);

      String? shareError;
      String? sharedGroupName;

      if (saved.targetGroupId != null) {
        try {
          final shareRepo = _ref.read(shareRepositoryProvider);
          
          // 계약 인터페이스 적용
          await shareRepo.shareGifticon(
            groupId: saved.targetGroupId!,
            gifticon: saved,
          );

          final groups = await shareRepo.watchGroups(currentUser.id).first;
          final targetGroup = groups.firstWhere(
            (g) => g.id == saved.targetGroupId,
            orElse: () => throw Exception('지정된 그룹을 찾을 수 없습니다.'),
          );
          sharedGroupName = targetGroup.name;
        } catch (e) {
          shareError = '그룹 공유 실패: $e';
        }
      }

      state = state.copyWith(
        submit: ScanSubmitSuccess(
          saved,
          shareError: shareError,
          sharedGroupName: sharedGroupName,
        ),
      );

      return saved;
    } catch (e) {
      state = state.copyWith(
        submit: ScanSubmitFailure(
          '저장에 실패했습니다: $e',
        ),
      );

      return null;
    }
  }
}

final gifticonFormControllerProvider =
    StateNotifierProvider<GifticonFormController, GifticonFormState>(
  (ref) => GifticonFormController(ref),
);