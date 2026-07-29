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
/// 저장 완료
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
///
/// 실제 [Gifticon] 생성 방식은 세 경로 모두 동일하다.
///
/// 차이점은 "폼을 어떤 방식으로 처음 채우는가"뿐이다.
///
/// - camera: 카메라 인식 결과로 프리필
/// - gallery: 이미지 인식 결과로 프리필
/// - manual: 빈 폼에서 직접 입력
enum ScanSource {
  /// 카메라 촬영 후 인식(OCR/바코드) → 폼 프리필.
  ///
  /// TODO(scan):
  /// 실제 카메라 플러그인 연동 후
  /// 인식 결과를 [prefillFromRecognition]으로 전달한다.
  camera,

  /// 갤러리 이미지 선택 후 인식 → 폼 프리필.
  ///
  /// 현재 [ScanPage]에서 실제로 연결된 경로다.
  gallery,

  /// 사용자가 직접 입력.
  ///
  /// 별도의 OCR/바코드 인식 없이
  /// 빈 폼에서 시작한다.
  manual,
}

/// 카테고리 미분류 시 채우는 계약 기본값.
///
/// 계약상 category는 빈 문자열을 허용하지 않으므로
/// 사용자가 입력하지 않은 경우 "기타"로 저장한다.
///
/// (매트릭스 §1: category 빈 문자열 금지 → "기타")
const String kDefaultCategory = '기타';

/// 폼 제출 결과.
///
/// 저장 버튼을 눌렀을 때 현재 저장 상태를 표현한다.
sealed class ScanSubmitState {
  const ScanSubmitState();
}

/// 초기/미제출 상태.
///
/// 아직 저장을 시도하지 않았거나
/// 이전 저장 상태를 초기화한 상태다.
class ScanSubmitIdle extends ScanSubmitState {
  const ScanSubmitIdle();
}

/// 제출 진행 중.
///
/// Repository에 저장 요청을 보내고
/// 응답을 기다리는 동안 사용한다.
///
/// UI에서는 이 상태일 때 저장 버튼을 비활성화하거나
/// 로딩 인디케이터를 표시할 수 있다.
class ScanSubmitInProgress extends ScanSubmitState {
  const ScanSubmitInProgress();
}

/// 제출 성공.
///
/// Repository 저장이 완료되고
/// 최종적으로 확정된 [Gifticon]을 보관한다.
///
/// Repository가 id/registeredAt 등을 발급한다면
/// 그 결과가 [saved]에 들어온다.
class ScanSubmitSuccess extends ScanSubmitState {
  const ScanSubmitSuccess(this.saved);

  final Gifticon saved;
}

/// 제출 실패.
///
/// 검증 실패 또는 Repository 저장 중 오류가 발생한 경우 사용한다.
///
/// [message]는 사용자에게 표시할 오류 메시지다.
class ScanSubmitFailure extends ScanSubmitState {
  const ScanSubmitFailure(this.message);

  final String message;
}

/// 폼의 편집 가능한 원시 상태.
///
/// 아직 [Gifticon] 객체로 저장하기 전 단계의 데이터다.
///
/// 예를 들어 금액은 계약 모델에서는 int지만
/// 사용자가 입력하는 동안에는 "4,500" 같은 문자열로 보관한다.
///
/// 이렇게 하면 TextField와 자연스럽게 연결할 수 있고,
/// 제출 시 [parsedPrice]를 통해 int로 변환할 수 있다.
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

  /// 사용자가 어떤 입력 경로로 폼에 들어왔는지.
  final ScanSource source;

  /// 브랜드명.
  final String brand;

  /// 상품명.
  final String productName;

  /// 금액(원, KRW)의 원시 입력.
  ///
  /// 사용자가 편집하는 문자열이므로
  /// "4500", "4,500" 등의 형태가 들어올 수 있다.
  ///
  /// 제출 시 [parsedPrice]에서 콤마를 제거하고
  /// int로 변환한다.
  ///
  /// 계약상 price는 required int이므로
  /// 빈 값은 검증 실패다.
  ///
  /// 단, 0은 허용한다.
  /// 예: 무료 쿠폰 / 사은품.
  final String price;

  /// 바코드 번호.
  ///
  /// 인식되지 않았거나 사용자가 입력하지 않은 경우
  /// 빈 문자열로 유지될 수 있다.
  ///
  /// 저장 시 빈 문자열은 null로 변환한다.
  final String barcode;

  /// 카테고리.
  ///
  /// 사용자가 입력하지 않으면 제출 시
  /// [kDefaultCategory]인 "기타"로 보정한다.
  final String category;

  /// 유효기간.
  ///
  /// 계약상 필수 값이므로 제출 전에 null 여부를 검증한다.
  final DateTime? expiryDate;

  /// 원본 기프티콘 이미지 경로.
  ///
  /// 갤러리/카메라 인식 경로에서는 이미지 경로가 들어갈 수 있고,
  /// 직접 입력에서는 null일 수 있다.
  final String? imagePath;

  /// 현재 제출 상태.
  ///
  /// Idle / InProgress / Success / Failure 중 하나다.
  final ScanSubmitState submit;

  /// 현재 상태를 기반으로 일부 값만 변경한 새 상태를 만든다.
  ///
  /// [GifticonFormState]는 불변 객체이기 때문에
  /// 기존 객체의 값을 직접 수정하지 않고
  /// 새로운 객체를 생성한다.
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
  /// 예:
  ///
  /// "4500"  → 4500
  /// "4,500" → 4500
  /// " 4500 " → 4500
  /// ""      → null
  /// "abc"   → null
  ///
  /// 빈 값이나 숫자로 변환할 수 없는 값은 null을 반환한다.
  ///
  /// 0은 정상적인 값으로 취급한다.
  int? get parsedPrice {
    // 사용자가 입력한 콤마와 앞뒤 공백을 제거한다.
    final String digits = price.replaceAll(',', '').trim();

    // 빈 문자열이면 숫자로 변환할 수 없으므로 null.
    if (digits.isEmpty) {
      return null;
    }

    // 변환 실패 시 null을 반환한다.
    return int.tryParse(digits);
  }

  /// 폼 필수 필드를 검증한다.
  ///
  /// 검증 성공:
  ///   null 반환
  ///
  /// 검증 실패:
  ///   사용자에게 보여줄 오류 메시지 반환
  ///
  /// 계약 필수 필드:
  /// - brand
  /// - productName
  /// - price
  /// - expiryDate
  ///
  /// category는 비어 있어도 제출 시 "기타"로 보정하므로
  /// 여기서는 검증하지 않는다.
  String? validate() {
    // 브랜드명은 반드시 입력해야 한다.
    if (brand.trim().isEmpty) {
      return '브랜드명을 입력하세요.';
    }

    // 상품명은 반드시 입력해야 한다.
    if (productName.trim().isEmpty) {
      return '상품명을 입력하세요.';
    }

    // 계약상 price는 required int다.
    //
    // 따라서:
    // - 빈 값 → 실패
    // - 숫자가 아닌 값 → 실패
    // - 음수 → 실패
    // - 0 → 허용
    final int? parsed = parsedPrice;

    if (parsed == null) {
      return '금액(원)을 입력하세요.';
    }

    if (parsed < 0) {
      return '금액(원)은 0 이상이어야 합니다.';
    }

    // 유효기간은 계약상 필수다.
    if (expiryDate == null) {
      return '유효기간을 입력하세요.';
    }

    // 모든 검증을 통과했다.
    return null;
  }
}

/// 폼 상태를 관리하고 제출 시 계약 Repository로 저장하는 컨트롤러.
///
/// UI에서는 이 컨트롤러를 통해
///
/// - 입력값 변경
/// - OCR 결과 프리필
/// - 폼 초기화
/// - 저장
///
/// 를 수행한다.
///
/// 실제 저장 책임은 Repository에 있고,
/// 이 컨트롤러는 "폼 데이터 → Gifticon 변환"을 담당한다.
class GifticonFormController extends StateNotifier<GifticonFormState> {
  GifticonFormController(this._ref) : super(const GifticonFormState());

  final Ref _ref;

  /// 폼 세션 번호.
  ///
  /// [startWith]/[reset]이 호출될 때마다 증가한다.
  ///
  /// 컨트롤러가 앱 수명 동안 살아 있기 때문에,
  /// 비동기 작업([submit] 등)이 끝났을 때
  /// "그 사이 폼이 다른 세션으로 바뀌지 않았는지"를
  /// 이 번호로 확인한다.
  ///
  /// 예: 저장이 느린 상태에서 사용자가 폼을 떠나
  /// 새 폼을 시작하면, 뒤늦게 완료된 이전 저장 결과가
  /// 새 폼 상태를 덮어쓰지 못하게 막는다.
  int _session = 0;

  /// 입력 경로를 지정하고 폼을 초기화한다.
  ///
  /// 예:
  ///
  /// 사용자가 갤러리 버튼을 누르면
  ///
  /// startWith(ScanSource.gallery)
  ///
  /// 가 호출되어 새로운 폼 상태가 시작된다.
  ///
  /// 카메라/갤러리 경로는 이후 인식 결과가 나오면
  /// [prefillFromRecognition]으로 필드를 채운다.
  ///
  /// 현재 카메라는 플러그인 미연동 상태이므로
  /// 이후 직접 입력으로 폴백할 수 있다.
  void startWith(ScanSource source) {
    // 새 폼 세션 시작 — 진행 중이던 이전 세션의
    // 비동기 결과(submit 등)는 무효화된다.
    _session++;

    state = GifticonFormState(
      source: source,
    );
  }

  /// 폼 상태를 초기 상태로 비운다.
  ///
  /// 추가 흐름이 끝났을 때(폼 화면이 닫혔을 때) 호출한다.
  ///
  /// provider가 autoDispose가 아니므로,
  /// 여기서 비워 주어야 바코드/이미지 경로 등 민감한 값이
  /// 앱 수명 동안 전역 상태에 잔존하지 않는다.
  ///
  /// 세션 번호도 증가하므로, 아직 완료되지 않은 이전
  /// [submit]의 결과가 새 폼 상태를 덮어쓰지 못한다.
  void reset() {
    _session++;

    state = const GifticonFormState();
  }

  /// 인식(OCR/바코드) 결과로 폼을 프리필한다.
  ///
  /// 인식에 성공한 필드만 폼에 넣고,
  /// 인식하지 못한 필드는 기존 상태를 유지한다.
  ///
  /// 따라서 OCR 결과가 불완전해도
  /// 사용자가 GifticonForm에서 직접 수정할 수 있다.
  ///
  /// 예:
  ///
  /// OCR:
  /// brand = "스타벅스"
  /// productName = "아메리카노"
  /// price = "4500"
  ///
  /// → 화면의 입력창에 자동으로 표시
  /// → 사용자가 필요하면 수정
  /// → 저장
  ///
  /// TODO(scan):
  /// 카메라/갤러리 플러그인 연동 시
  /// 추출 결과를 이 메서드로 전달한다.
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

    // ─────────────────────────────────────────
    // 디버깅용: 프리필 직후의 폼 상태 확인
    // ─────────────────────────────────────────
    //
    // 인식 결과가 Riverpod 상태에 실제로 반영되었는지
    // 로그로 확인할 수 있다.
    //
    // 주의: debugPrint는 release 빌드에서도 실행되므로
    // (컴파일 아웃되지 않음) 바코드처럼 민감한 값이
    // 프로덕션 기기 로그에 남지 않도록 반드시
    // kDebugMode로 가드한다.
    if (kDebugMode) {
      debugPrint('===== GifticonForm 상태 변경 =====');
      debugPrint('source = ${state.source}');
      debugPrint('brand = ${state.brand}');
      debugPrint('productName = ${state.productName}');
      debugPrint('price = ${state.price}');
      debugPrint('barcode = ${state.barcode}');
      debugPrint('category = ${state.category}');
      debugPrint('expiryDate = ${state.expiryDate}');
      debugPrint('imagePath = ${state.imagePath}');
    }
  }

  // ─────────────────────────────────────────
  // 개별 입력값 변경 메서드
  // ─────────────────────────────────────────
  //
  // GifticonForm의 TextField에서 사용자가 입력할 때마다
  // 현재 입력값을 Riverpod 상태에 저장한다.

  /// 브랜드명 변경.
  void setBrand(String v) {
    state = state.copyWith(
      brand: v,
    );
  }

  /// 상품명 변경.
  void setProductName(String v) {
    state = state.copyWith(
      productName: v,
    );
  }

  /// 금액 변경.
  void setPrice(String v) {
    state = state.copyWith(
      price: v,
    );
  }

  /// 바코드 변경.
  void setBarcode(String v) {
    state = state.copyWith(
      barcode: v,
    );
  }

  /// 카테고리 변경.
  void setCategory(String v) {
    state = state.copyWith(
      category: v,
    );
  }

  /// 유효기간 변경.
  void setExpiryDate(DateTime v) {
    state = state.copyWith(
      expiryDate: v,
    );
  }

  /// 이미지 경로 변경.
  void setImagePath(String v) {
    state = state.copyWith(
      imagePath: v,
    );
  }

  /// 폼을 검증하고 계약 [Gifticon]으로 변환해 저장한다.
  ///
  /// 전체 흐름:
  ///
  /// 1. 폼 검증
  /// 2. 현재 로그인 사용자 확인
  /// 3. 제출 상태 → InProgress
  /// 4. FormState → Gifticon 변환
  /// 5. Repository.addGifticon() 호출
  /// 6. 성공 → ScanSubmitSuccess
  /// 7. 실패 → ScanSubmitFailure
  ///
  /// 계약 메서드:
  ///
  /// [GifticonRepository.addGifticon](Gifticon)
  /// → Future<Gifticon>
  ///
  /// 성공하면 Repository가 반환한 최종 Gifticon을 반환한다.
  Future<Gifticon?> submit() async {
    // ─────────────────────────────────────────
    // 1단계: 입력값 검증
    // ─────────────────────────────────────────
    final String? error = state.validate();

    if (error != null) {
      // 검증 실패 내용을 상태에 저장한다.
      //
      // GifticonForm은 이 상태를 보고
      // 사용자에게 오류 메시지를 표시한다.
      state = state.copyWith(
        submit: ScanSubmitFailure(error),
      );

      return null;
    }

    // ─────────────────────────────────────────
    // 2단계: 로그인 사용자 확인
    // ─────────────────────────────────────────
    //
    // Gifticon.ownerId에 현재 로그인한 사용자 id가 필요하다.
    final currentUser = _ref.read(authRepositoryProvider).currentUser;

    if (currentUser == null) {
      state = state.copyWith(
        submit: const ScanSubmitFailure(
          '로그인이 필요합니다.',
        ),
      );

      return null;
    }

    // ─────────────────────────────────────────
    // 3단계: 저장 진행 상태로 변경
    // ─────────────────────────────────────────
    //
    // UI에서는 이 상태를 보고
    // 저장 버튼을 비활성화하고 로딩 인디케이터를 보여준다.
    state = state.copyWith(
      submit: const ScanSubmitInProgress(),
    );

    // 이 제출이 속한 폼 세션을 기억해 둔다.
    //
    // 아래 addGifticon await 중에 사용자가 폼을 떠나
    // 새 흐름을 시작하면(startWith/reset으로 세션이 바뀌면),
    // 이 제출의 결과는 새 폼 상태에 반영하지 않고 버린다.
    final int session = _session;

    // ─────────────────────────────────────────
    // 4단계: 폼 원시 입력 → 계약 Gifticon 변환
    // ─────────────────────────────────────────

    // category가 비어 있으면 계약 기본값 "기타"를 사용한다.
    final String category = state.category.trim().isEmpty
        ? kDefaultCategory
        : state.category.trim();

    // barcode는 nullable 필드다.
    //
    // 사용자가 입력하지 않은 경우
    // 빈 문자열 대신 null로 저장한다.
    final String? barcode =
        state.barcode.trim().isEmpty ? null : state.barcode.trim();

    final Gifticon draft = Gifticon(
      // Repository가 id를 발급하는 구조이므로
      // 여기서는 빈 문자열을 전달한다.
      id: '',

      // 현재 로그인한 사용자의 id를 저장한다.
      ownerId: currentUser.id,

      // 사용자가 입력한 브랜드명.
      brand: state.brand.trim(),

      // 사용자가 입력한 상품명.
      productName: state.productName.trim(),

      // validate()에서 non-null 및 >= 0을 보장했기 때문에
      // 여기서는 !를 사용할 수 있다.
      price: state.parsedPrice!,

      // 빈 문자열이면 null.
      barcode: barcode,

      // 비어 있으면 "기타".
      category: category,

      // validate()에서 non-null을 보장했다.
      expiryDate: state.expiryDate!,

      // Repository가 별도로 발급하지 않는 경우를 고려해
      // 현재 시각을 전달한다.
      registeredAt: DateTime.now(),

      // 계약상 신규 기프티콘은 항상 available 상태로 시작한다.
      status: GifticonStatus.available,

      // 갤러리/카메라 인식 시 이미지 경로가 들어오고
      // 직접 입력에서는 null일 수 있다.
      imagePath: state.imagePath,
    );

    try {
      // ─────────────────────────────────────────
      // 5단계: Repository에 실제 저장 요청
      // ─────────────────────────────────────────
      //
      // Controller는 저장 구현을 직접 담당하지 않는다.
      //
      // Repository에 Gifticon을 전달하고
      // 실제 저장은 Repository가 담당한다.
      final Gifticon saved =
          await _ref.read(gifticonRepositoryProvider).addGifticon(draft);

      // 저장 중에 폼 세션이 바뀌었으면(사용자가 폼을 떠나
      // 새 흐름을 시작했으면) 결과를 상태에 반영하지 않는다.
      //
      // 반영하면 사용자가 제출한 적 없는 새 폼에
      // 이전 제출의 성공/실패가 표시된다.
      if (!mounted || session != _session) {
        return saved;
      }

      // ─────────────────────────────────────────
      // 6단계: 저장 성공
      // ─────────────────────────────────────────
      //
      // Repository가 반환한 최종 Gifticon을 상태에 저장한다.
      state = state.copyWith(
        submit: ScanSubmitSuccess(saved),
      );

      return saved;
    } catch (e) {
      // 성공 경로와 마찬가지로, 세션이 바뀐 뒤 도착한
      // 실패 결과는 새 폼 상태에 반영하지 않는다.
      if (!mounted || session != _session) {
        return null;
      }

      // ─────────────────────────────────────────
      // 7단계: 저장 실패
      // ─────────────────────────────────────────
      //
      // Repository에서 발생한 예외를 사용자에게
      // 보여줄 수 있는 메시지로 변환한다.
      state = state.copyWith(
        submit: ScanSubmitFailure(
          '저장에 실패했습니다: $e',
        ),
      );

      return null;
    }
  }
}

/// 폼 컨트롤러 provider.
///
/// 주의: autoDispose를 사용하지 않는다.
///
/// ScanPage의 인식 흐름은
///
/// startWith()
/// → (await 이미지 선택/OCR — 이 동안 listener가 없음)
/// → prefillFromRecognition()
/// → Navigator.push(폼 화면)
///
/// 처럼 "폼 화면이 열리기 전에" 상태를 채운다.
///
/// autoDispose였을 때는 listener가 아직 없는 이 구간에서
/// provider가 자동 폐기되어, 프리필한 인식 결과가
/// 폼 화면이 열리기 전에 사라지는 버그가 있었다.
/// (폼 화면의 첫 build보다 dispose가 먼저 실행됨)
///
/// 새 폼의 초기화는 autoDispose 대신 두 가지 장치가 보장한다.
///
/// 1. 모든 진입 경로가 반드시 [GifticonFormController.startWith]를
///    먼저 호출한다(흐름 시작 시 초기화).
/// 2. ScanPage가 흐름 종료 시(폼이 닫히면)
///    [GifticonFormController.reset]을 호출해 상태를 비운다
///    (바코드 등 민감한 값이 앱 수명 동안 잔존하지 않도록).
///
/// 따라서 재진입 시에도 이전 입력값이 남지 않는다.
final gifticonFormControllerProvider =
    StateNotifierProvider<GifticonFormController, GifticonFormState>(
  (ref) => GifticonFormController(ref),
);
