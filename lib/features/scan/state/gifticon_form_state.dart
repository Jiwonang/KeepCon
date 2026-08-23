/// scan 폼 상태 및 컨트롤러.
///
/// 카메라/갤러리/수동 입력 세 경로가 모두 이 폼 상태로 수렴한다.
///
/// 전체 데이터 흐름은 다음과 같다.
///
/// 카메라/갤러리/수동 입력
///        ↓
/// GifticonFormState
///        ↓
/// GifticonFormController
///        ↓
/// 사용자가 입력값 확인/수정
///        ↓
/// validate()
///        ↓
/// Gifticon 객체 생성
///        ↓
/// GifticonRepository.addGifticon()
///        ↓
/// (targetGroupId가 있는 경우) ShareRepository.shareGifticon()
///        ↓
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

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/repositories.dart';

/// scan 입력 경로 구분.
enum ScanSource {
  camera,
  gallery,
  manual,
}

const String kDefaultCategory = '기타';

/// 폼 제출 결과.
sealed class ScanSubmitState {
  const ScanSubmitState();
}

class ScanSubmitIdle extends ScanSubmitState {
  const ScanSubmitIdle();
}

class ScanSubmitInProgress extends ScanSubmitState {
  const ScanSubmitInProgress();
}

/// 무료 플랜 저장 한도에 걸려 저장을 거부한 상태.
///
/// 중복([ScanSubmitDuplicate])과 달리 **폼에서 고칠 수 있는 것이 없다** — 입력을
/// 어떻게 바꿔도 한도는 그대로다. 그래서 안내도 필드 문구가 아니라 화면 단위로 한다.
class ScanSubmitLimitReached extends ScanSubmitState {
  const ScanSubmitLimitReached({required this.saved, required this.limit});

  /// 현재 저장돼 있는 기프티콘 개수.
  final int saved;

  /// 무료 플랜 상한([UserPlan.freeGifticonLimit]).
  final int limit;
}

/// 같은 바코드가 이미 등록돼 있어 저장을 거부한 상태.
class ScanSubmitDuplicate extends ScanSubmitState {
  const ScanSubmitDuplicate(this.existing);

  /// 바코드가 겹치는 **기존** 기프티콘.
  ///
  /// 안내에 브랜드·상품명을 함께 보여주기 위해 싣는다 — 같은 브랜드 기프티콘이
  /// 여러 개인 목록에서 "무엇과 겹쳤는지"를 사용자가 목록을 뒤지지 않고 알 수 있다.
  final Gifticon existing;
}

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

class ScanSubmitFailure extends ScanSubmitState {
  const ScanSubmitFailure(this.message);

  final String message;
}

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

  /// 계약([Gifticon.price])으로 넘길 금액.
  ///
  /// 금액은 선택 입력이므로 **비워 두면 0원**으로 본다. 계약상 [Gifticon.price]는
  /// non-nullable이지만 0(무료/사은품)은 허용하므로, 빈 값을 0으로 채워도 계약을
  /// 어기지 않는다. 숫자로 해석할 수 없는 값이면 `null`(검증 실패).
  int? get parsedPrice {
    final String digits = price.replaceAll(',', '').trim();
    if (digits.isEmpty) {
      return 0;
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
      return '금액(원)은 숫자로 입력하세요.';
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

  /// 현재 사용자의 플랜을 한 번만 읽는다.
  ///
  /// 스캔은 "저장을 누른 그 순간의 플랜" 하나만 필요하므로 스트림을 계속 붙들지
  /// 않는다(그래서 provider 인스턴스가 갈리는 문제도 생기지 않는다).
  ///
  /// **읽지 못하면 [UserPlan.free]로 본다.** 계약이 정한 기본값이 free이고
  /// (`필드 부재 = free`), 여기까지 왔다는 것은 바로 위 [GifticonRepository.getGifticons]
  /// 가 성공했다는 뜻이라 연결 문제일 가능성이 낮다. 대신 프리미엄 사용자가 일시적
  /// 오류로 막힐 수 있는데, 다시 시도하면 풀린다.
  ///
  /// 타임아웃을 두는 이유: 스트림이 영영 방출하지 않으면 `first`가 걸려 submit이
  /// 끝나지 않고, 저장 버튼이 비활성인 채로 화면이 멈춘다.
  Future<UserPlan> _readPlan() async {
    try {
      return await _ref
          .read(authRepositoryProvider)
          .watchPlan()
          .first
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('KeepCon: 플랜 조회 실패 — free로 간주: $e');
      return UserPlan.free;
    }
  }

  Future<Gifticon?> submit() async {
    // 이미 진행 중이면 무시한다.
    //
    // 버튼 비활성화만으로는 부족하다 — 그건 다음 프레임에야 반영되므로 "상태가
    // 문지기"여야 중복 호출이 확실히 막힌다. 아래 모든 경로가 Success/Failure/
    // Duplicate 중 하나로 반드시 빠져나가므로 여기서 갇히지 않는다.
    if (state.submit is ScanSubmitInProgress) {
      return null;
    }

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
        submit: const ScanSubmitFailure('로그인이 필요합니다.'),
      );
      return null;
    }

    // **중복 조회를 시작하기 전에** 진행 중으로 표시한다.
    //
    // 조회 뒤에 세우면 네트워크 왕복 동안 상태가 Idle로 남아 저장 버튼이 계속
    // 눌리는 상태가 된다. 연타하면 두 호출이 나란히 조회를 돌고, **둘 다 아직
    // 아무것도 저장되지 않은 목록을 보므로 둘 다 "중복 없음"으로 통과**해
    // 같은 바코드가 두 번 저장된다 — 이 함수가 막으려는 바로 그 상태다.
    state = state.copyWith(
      submit: const ScanSubmitInProgress(),
    );

    // 저장 목록을 **한 번만** 읽어 한도 검사와 중복 검사가 함께 쓴다.
    //
    // 조회가 던지면 submit()이 통째로 예외로 빠져나가 호출자가 아무 안내도
    // 못 띄운다 — 실패도 결과 상태로 돌려준다.
    final List<Gifticon> allGifticons;

    try {
      allGifticons = await _ref
          .read(gifticonRepositoryProvider)
          .getGifticons(currentUser.id);
    } catch (e) {
      state = state.copyWith(
        submit: ScanSubmitFailure('저장 목록을 확인하지 못했습니다: $e'),
      );
      return null;
    }

    // ── 무료 플랜 저장 한도 ──
    //
    // 중복 검사보다 **먼저** 본다. 한도에 걸린 사람에게 "중복입니다"는 틀린 정보다 —
    // 바코드를 고쳐도 어차피 저장되지 않는다.
    //
    // ⚠️ 이 검사는 **UX이지 강제가 아니다.** firestore.rules의 gifticons create는
    // 소유자만 확인하고 개수는 세지 않으므로(규칙은 문서 수를 셀 수 없다), API로
    // 직접 쏘면 11개째도 그대로 저장된다. 진짜 강제는 서버 쪽 카운터 스키마가
    // 필요하고 그건 계약 소유자 영역이다.
    final UserPlan plan = await _readPlan();

    if (plan == UserPlan.free &&
        allGifticons.length >= UserPlan.freeGifticonLimit) {
      state = state.copyWith(
        submit: ScanSubmitLimitReached(
          saved: allGifticons.length,
          limit: UserPlan.freeGifticonLimit,
        ),
      );
      return null;
    }

    // 바코드 중복 검증
    final String? trimmedBarcode =
        state.barcode.trim().isEmpty ? null : state.barcode.trim();

    if (trimmedBarcode != null) {
      Gifticon? duplicate;

      for (final Gifticon g in allGifticons) {
        if (g.barcode == trimmedBarcode) {
          duplicate = g;
          break;
        }
      }

      if (duplicate != null) {
        state = state.copyWith(
          submit: ScanSubmitDuplicate(duplicate),
        );
        return null;
      }
    }

    final String category = state.category.trim().isEmpty
        ? kDefaultCategory
        : state.category.trim();

    final Gifticon draft = Gifticon(
      id: '',
      ownerId: currentUser.id,
      brand: state.brand.trim(),
      productName: state.productName.trim(),
      price: state.parsedPrice!,
      barcode: trimmedBarcode,
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
        submit: ScanSubmitFailure('저장에 실패했습니다: $e'),
      );
      return null;
    }
  }
}

final gifticonFormControllerProvider =
    StateNotifierProvider<GifticonFormController, GifticonFormState>(
  (ref) => GifticonFormController(ref),
);
