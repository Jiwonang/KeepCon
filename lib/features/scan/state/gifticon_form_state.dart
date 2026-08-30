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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/error_reporter_provider.dart';
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

  /// 현재 사용자의 플랜을 한 번만 읽는다 — 서버 확인(`AuthRepository.getPlan`).
  ///
  /// 스캔은 "저장을 누른 그 순간의 플랜" 하나만 필요하므로 스트림을 붙들지 않는다.
  /// 예전에는 `watchPlan().first`로 읽었는데 그건 Firestore 로컬 캐시의 첫 방출이라,
  /// 다른 기기에서 프리미엄으로 올린 직후 낡은 free로 막을 수 있었다. 계약에
  /// 서버 확인 접근점이 생겨 그 한계는 사라졌다.
  ///
  /// **읽지 못하면 `null`을 돌려준다** — free로 간주하지 않는다. 그러면 결제한
  /// 사용자가 인프라 오류 하나로 저장을 막힌다. 한도는 과금 정책이지 보안 경계가
  /// 아니므로(서버가 강제하지도 않는다), 모르는 상태에서 사용자를 벌하는 것보다
  /// "확인하지 못했으니 다시 시도" 쪽이 옳다. 호출부가 그렇게 안내한다.
  ///
  /// 타임아웃을 두는 이유: 서버 왕복이 영영 안 돌아오면 submit이 끝나지 않아
  /// 저장 버튼이 비활성인 채로 화면이 멈춘다. **15초**로 잡은 건 이제 이 값이
  /// 캐시 방출이 아니라 서버 왕복(콜드 스타트면 gRPC 연결 + 토큰 갱신까지)에
  /// 걸리기 때문이다 — 짧게 잡으면 느린 회선에서 정작 이 경로가 구제하려던
  /// 프리미엄 사용자가 "확인하지 못했어요"로 막힌다.
  Future<UserPlan?> _readPlan() async {
    try {
      return await _ref
          .read(authRepositoryProvider)
          .getPlan()
          .timeout(const Duration(seconds: 15));
    } catch (e, s) {
      // **free로 간주하지 않는다.** 그러면 결제한 사용자가 인프라 오류 하나로
      // 저장을 막힌다 — 한도는 과금 정책이지 보안 경계가 아니므로, 모르는 상태에서
      // 사용자를 벌하는 쪽보다 "확인 못 했으니 다시" 쪽이 옳다. null로 알린다.
      //
      // 진단은 형제들과 같은 경로로 보낸다 — 여기만 손으로 debugPrint를 찍으면
      // 같은 클래스 안에 두 관용구가 남고, release에서 메시지를 가리는 방어도
      // 이 자리만 빠진다.
      _reportFailure('_readPlan', e, s);
      return null;
    }
  }

  Future<Gifticon?> submit() async {
    // 이미 진행 중이면 무시한다.
    //
    // 버튼 비활성화만으로는 부족하다 — 그건 다음 프레임에야 반영되므로 "상태가
    // 문지기"여야 중복 호출이 확실히 막힌다. 아래 모든 경로가 [ScanSubmitState]의
    // 종단 상태(Success/Failure/Duplicate/LimitReached) 중 하나로 반드시 빠져나가므로
    // 여기서 갇히지 않는다 — sealed라 종단 상태를 새로 추가하면 scan_page의 switch가
    // 컴파일 오류로 알려 준다.
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
    } catch (e, s) {
      // **원시 예외를 사용자 문구에 넣지 않는다.** `[cloud_firestore/unavailable]`
      // 같은 내부 식별자는 사용자가 읽을 것도, 할 수 있는 것도 없다. 원인은
      // 로그로 남기고 화면에는 다음 행동만 적는다.
      _reportFailure('getGifticons', e, s);
      state = state.copyWith(
        submit: const ScanSubmitFailure(
          '저장 목록을 확인하지 못했어요. 네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
        ),
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
    //
    // **보유 중([GifticonStatus.available])만 센다.** 전체 개수로 세면 무료
    // 사용자가 막다른 골목에 갇힌다 — 10개를 등록해 전부 사용 완료해도 개수는
    // 그대로인데, 계약에 삭제 API가 없고(전수 확인: 5개 메서드, delete 없음)
    // dev/prod에서는 보안 규칙이 plan 쓰기를 막아 프리미엄 전환도 되지 않는다.
    // 그러면 등록이 영구히 정지한다. available 기준이면 '사용 완료 처리'가 곧
    // 자리를 비우는 탈출구가 되고, "10개까지 **보관**"이라는 제품 의도에도 맞는다.
    final int activeCount = allGifticons
        .where((Gifticon g) => g.status == GifticonStatus.available)
        .length;

    // 한도 미만이면 플랜은 판정에 영향이 없다(free든 premium이든 통과) — 그때는
    // 읽지 않는다. 대부분의 저장에서 서버 왕복이 통째로 빠지고, 조회가 실패했을
    // 때의 재시도 안내도 "한도만큼 채운 사용자"로 좁혀진다.
    if (activeCount >= UserPlan.freeGifticonLimit) {
      final UserPlan? plan = await _readPlan();

      // 플랜을 확인하지 못했으면 **막지도 통과시키지도 않는다.** free로 간주하면
      // 프리미엄 사용자가 조회 장애로 저장을 잃고, premium으로 간주하면 한도가
      // 조용히 뚫린다. 판정을 보류하고 재시도를 안내하는 것이 정직하다.
      if (plan == null) {
        // **안내가 원인을 가리켜야 한다.** 여기 오는 가장 흔한 경우는 오프라인이다 —
        // 계약은 "서버에서 한 번 확인"까지만 못박고, Firebase 구현이 그것을
        // `GetOptions(source: Source.server)`로 실현해 캐시로 폴백하지 않는다.
        // 그래서 dev·prod에서 연결이 없으면 이 경로는 반드시 실패한다(in-memory·
        // 데모는 네트워크를 타지 않아 해당 없음). 그런데 "잠시 후"는 기다리면
        // 낫는다는 뜻이라 오프라인 사용자에게는 맞지 않는 안내다 — 연결을 되살리기
        // 전까지 몇 번을 다시 눌러도 같은 자리에서 막힌다.
        //
        // 그렇다고 원인을 오프라인으로 단정하지도 않는다 — 구현이 서버 오류를
        // 같은 `AuthErrorCode.unknown`으로 뭉치고, 위 15초 타임아웃은 아예 다른
        // 예외 타입이라 여기 도달할 때는 원인이 지워져 있다. 연결 확인을 앞세우되
        // "다시 시도"를 남겨 둘 다 덮는다.
        //
        // **어절 보호는 여기서 걸지 않는다.** 걸면 보이지 않는 문자가 섞인
        // 문자열이 상태에 실려 그대로 스낵바의 접근성 라벨이 되고, 위젯이 아니라
        // 상태가 표현을 들고 있어 `semanticsLabel`로 원문을 되살릴 수도 없다.
        // 어절 보호는 표시 지점에서만 건다(`KeepAllText`).
        state = state.copyWith(
          submit: const ScanSubmitFailure(
            '플랜 정보를 확인하지 못했어요. 네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
          ),
        );
        return null;
      }

      if (plan == UserPlan.free) {
        state = state.copyWith(
          submit: ScanSubmitLimitReached(
            saved: activeCount,
            limit: UserPlan.freeGifticonLimit,
          ),
        );
        return null;
      }
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

    // [Gifticon.imagePath]는 **일부러 채우지 않는다.**
    //
    // 여기 넣을 수 있는 값은 로컬 파일 경로뿐이다 — 갤러리는 image_picker의 임시
    // 파일이고, 카메라는 `Directory.systemTemp`에 떨군 프레임이다
    // (`scan_page.dart`의 `_writeTempFrame`). 그런데 그 경로는:
    //
    // - **어디에서도 표시되지 않는다.** 홈 카드는 `http://`·`https://`로 시작할
    //   때만 렌더하고 그 외는 placeholder로 떨어지며(`gifticon_card.dart`),
    //   상세 화면은 이미지를 아예 싣지 않는다(`gifticon_detail_page.dart` doc).
    // - **곧 무효가 된다.** OS가 임시 디렉터리를 청소하면 파일이 사라지고, 다른
    //   기기·재설치에서는 애초에 의미가 없다.
    //
    // 그런데도 [FirebaseGifticonRepository]는 이 값을 문서에 그대로 쓴다. 즉
    // 채우면 **표시되지도 않고 곧 깨지는 경로가 Firestore에 쌓인다.**
    //
    // 이미지를 Firebase Storage에 올리고 다운로드 URL을 넣는 안은 검토 후
    // **채택하지 않았다** — 매장 사용에 이미지가 필요 없다는 것이 확인됐기
    // 때문이다(바코드는 번호에서 심볼을 다시 그린다). 계약의 필드는 그대로
    // 두었으므로, 나중에 업로드를 붙이기로 하면 여기에 **URL을** 넣으면 된다.
    //
    // ⚠️ 폼 미리보기(`gifticon_form_page.dart`)가 쓰는 `state.imagePath`는 그대로
    // 둔다 — 그것은 **저장 전** 화면이라 로컬 경로가 유효하고 실제로 보인다.
    // 그 값을 넣는 곳은 `scan_page.dart`의 `prefillFromRecognition(imagePath:)`
    // 두 곳뿐이고 **어떤 테스트도 그것을 지키지 않는다** — 두 줄을 지우고 전체를
    // 돌려 652/652 통과를 확인했다. 이 주석을 읽고 그 줄을 '잔존'으로 읽지 마라.
    // 저장 경로에서만 뺀 것이지 미리보기에서 뺀 것이 아니다.
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
      targetGroupId: state.targetGroupId,
    );

    try {
      final Gifticon saved =
          await _ref.read(gifticonRepositoryProvider).addGifticon(draft);

      String? shareError;
      String? sharedGroupName;

      if (saved.targetGroupId != null) {
        final shareRepo = _ref.read(shareRepositoryProvider);

        // ① 공유 자체. **여기서 실패해야만 '공유 실패'다.**
        try {
          await shareRepo.shareGifticon(
            groupId: saved.targetGroupId!,
            gifticon: saved,
          );
        } catch (e, s) {
          // ⚠️ 이 문자열은 스낵바에 **그대로 표시된다**(`scan_page.dart`가
          // `saveResultMessage`로 읽는다). 그래서 원시 예외를 담으면 안 된다 —
          // 저장소 예외에는 그룹·기프티콘 id가 실려 사용자 화면으로 샌다.
          _reportFailure('shareGifticon', e, s);
          shareError = '그룹에 공유하지 못했어요.';
        }

        // ② 그룹 이름 조회. 공유가 **이미 끝난 뒤의 표시용 조회**라, 여기서
        // 실패한 것은 공유 실패가 아니다.
        //
        // 예전에는 ①과 한 try에 묶여 있어서 스트림이 5초를 넘기거나 첫 방출에
        // 그 그룹이 없기만 해도 "공유하지 못했어요"가 떴다 — 공유는 성공했는데.
        // 사용자는 그 말을 믿고 재공유해 같은 기프티콘을 두 번 넣게 된다.
        // 이름을 못 읽으면 `sharedGroupName`을 null로 남기고, 화면은 그룹 이름
        // 없는 일반 성공 문구로 떨어진다(`save_result_message.dart` doc 참조).
        if (shareError == null) {
          // 상한을 거는 이유: 이 지점은 addGifticon이 **이미 성공한 뒤**라,
          // 스트림이 방출하지 않으면 저장은 됐는데 화면만 ScanSubmitInProgress로
          // 영영 멈춘다(저장 버튼도 잠긴 채).
          try {
            final groups = await shareRepo
                .watchGroups(currentUser.id)
                .timeout(const Duration(seconds: 5))
                .first;
            final targetGroup = groups.firstWhere(
              (g) => g.id == saved.targetGroupId,
              orElse: () => throw Exception('지정된 그룹을 찾을 수 없습니다.'),
            );
            sharedGroupName = targetGroup.name;
          } catch (e, s) {
            // 공유는 성공했다. 이름만 비운 채 진행한다.
            _reportFailure('resolveSharedGroupName', e, s);
          }
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
    } catch (e, s) {
      _reportFailure('submit', e, s);
      state = state.copyWith(
        submit: const ScanSubmitFailure(
          '저장하지 못했어요. 네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
        ),
      );
      return null;
    }
  }

  /// 처리된 실패를 개발자에게 남긴다 — 사용자 문구에서 걷어낸 원인이 여기로 온다.
  ///
  /// ⚠️ 공유 계약의 `reportHandledFailure`는 [WidgetRef]를 받아 이 컨트롤러([Ref])가
  /// 쓰지 못한다. 그래서 **래퍼만** 지역에서 다시 쓰고, 리포터 자체는 SSOT provider에서
  /// 받는다. 손으로 [debugPrint]를 찍으면 안 된다 — `DebugPrintErrorReporter`는
  /// `includeMessage: kDebugMode`라 **release에서 예외 메시지를 일부러 가리는데**
  /// (저장소 예외에 그룹·기프티콘 id가 실린다), 직접 찍으면 그 방어를 우회해
  /// 원시 예외를 화면 대신 플랫폼 로그로 옮겨 놓게 된다.
  ///
  /// `try/catch`는 래퍼의 계약("진단은 원래 실패를 절대 가리지 않는다")을 옮긴 것이다.
  /// 계약에 [Ref] 오버로드가 생기면 이 래퍼를 지운다.
  void _reportFailure(String context, Object error, StackTrace stack) {
    try {
      _ref.read(errorReporterProvider).report(
            error,
            stack,
            context: 'GifticonFormController.$context',
          );
    } catch (_) {
      // 폐기된 컨테이너·리포터 자체 실패 — 여기서 새면 원래 실패의 안내가 사라진다.
    }
  }
}

final gifticonFormControllerProvider =
    StateNotifierProvider<GifticonFormController, GifticonFormState>(
  (ref) => GifticonFormController(ref),
);
