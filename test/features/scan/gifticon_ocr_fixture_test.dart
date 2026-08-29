/// GifticonOcrParser 실제 기프티콘 픽스처 테스트.
///
/// 아래 두 상수는 **손으로 지어낸 텍스트가 아니라** 실제 기프티콘 이미지를
/// ML Kit(`TextRecognitionScript.korean`)에 돌려 나온 원문이다. 안드로이드
/// 기기에서 `MlKitService.scan(InputImage.fromFilePath(...))`으로 수집했다 —
/// 스캔 페이지의 카메라·갤러리 두 경로가 타는 바로 그 호출이다.
///
/// ## 지어낸 입력으로는 안 되는 이유
/// ML Kit이 돌려주는 **줄 순서는 사람이 보는 순서가 아니다.** 카카오톡 쪽
/// 원문을 보면 이미지 위에 도장처럼 찍힌 "사용완료"가 `사용` / `완료` 두 줄로
/// 쪼개진 뒤, 그 **사이에 `스타벅스`가 끼어 들어온다.** 화면을 눈으로 옮겨
/// 적었다면 절대 나오지 않을 배치다. 상단 시계도 `9:27`이 아니라 `9:274`로
/// 읽힌다(파서 `_isNoiseLine` 주석이 예로 든 그 오인식이 실제로 재현됐다).
///
/// ## ⚠️ 이 픽스처가 덮지 **않는** 것
/// 두 기프티콘의 브랜드가 모두 `스타벅스`라 `_extractBrand`는 1단계 **사전
/// 매칭에서 끝난다.** 2단계 "유효한 첫 번째 줄" 폴백은 실제 원문으로 한 번도
/// 실행되지 않는다 — 그런데 바로 위에 적은 사실(줄 순서가 시각 순서가 아니다)의
/// 파괴력은 정확히 그 폴백에 있다. 폴백은 읽는 순서를 전제하기 때문이다.
///
/// 실측: 픽스처에서 브랜드 이름 한 곳만 사전 밖 값으로 바꾸면 기프티쇼는
/// `기프티쇼 선물이 도착했어요!`를, 카카오톡은 보낸이 인사말을 브랜드로 낸다.
/// 카카오톡이 지금 통과하는 것은 ①브랜드가 사전에 있고 ②보낸이가 하필
/// `응원합니다!`를 썼는데 그 문구가 `_isNoiseLine`에 하드코딩돼 있어서다 —
/// 그 줄은 UI 크롬이 아니라 **보낸 사람의 자유 입력**이다.
///
/// 고치면 프리필 표시가 바뀌므로 제품 결정이 필요하다. 이 파일은 그 결정 전까지
/// **현재 동작을 계약으로 승격시키지 않기 위해** 폴백 경로를 고정하지 않는다.
///
/// ## 이 파일의 테스트 개수를 회귀 커버리지로 읽지 말 것
/// 같은 입력에 대한 단언이라 **단독으로 실패할 수 없는** 테스트가 섞여 있다.
/// 파서를 망가뜨리는 뮤테이션은 종합 테스트를 먼저 죽이므로 이들은 항상 같이
/// 죽는다. 그래도 남겨 둔 이유는 각자 `expect(_kakaoGiftOcr.contains(...))` 류의
/// **픽스처 무결성 트립와이어**를 갖고 있어, 누가 상수를 조용히 편집하면 그쪽이
/// 먼저 울기 때문이다.
///
///   - 독립 회귀 가드: 카카오/기프티쇼 종합 2건 · 금액 인과 1건 · 무결성 2건
///   - 종합 테스트에 종속(문서 + 트립와이어): 도장 · 시계 · 유효기간 · 사전 4건
///
/// ## 익명화
/// 저장소가 Public이므로 **값만** 바꾸고 **모양은 그대로 뒀다** — 파서가 보는
/// 것은 값이 아니라 형태(`.+의 선물$`, 8~30자리 숫자)이기 때문에 검증 범위는
/// 줄지 않는다. 바꾼 것은 두 가지뿐이다.
///   - 보낸 사람 실명 → `민서`
///   - 바코드 숫자 → 자릿수·구분자가 같은 다른 숫자(13자리 / 12자리)
///
/// ⚠️ 중립성 근거는 **현재 파서에 한정**된다 — `_looksLikeBarcode`가 자릿수만
/// 보고, `_extractPrice`는 `₩`/`원`/콤마를, `_extractExpiryDate`는 `[.\-/년월]`을
/// 요구하므로 숫자 '값'은 어떤 판정에도 닿지 않는다. 판정이 값을 읽도록 바뀌면
/// (GS1 접두·체크디지트 등) 이 근거가 무효가 되므로, 아래 형태 불변식 테스트가
/// 그때 먼저 운다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/services/gifticon_ocr_parser.dart';

/// 카카오톡 선물하기 — 사용완료된 스타벅스 음료 교환권. 금액·유효기간 표기 없음.
const String _kakaoGiftOcr = '9:274\n'
    '민서의 선물\n'
    '"응원합니다!"\n'
    '선물하기\n'
    '삭제\n'
    '나도 선물하기\n'
    '사용\n'
    '스타벅스\n'
    '완료\n'
    '아이스 카페 아메리카노T\n'
    '8801 2345 6789 0\n'
    '후기 작성\n'
    '선물추억';

/// 기프티쇼 — 스타벅스 e카드 금액권. 금액·유효기간이 모두 찍혀 있다.
const String _giftishowOcr = '기프티쇼 선물이 도착했어요!\n'
    '감사합니다.\n'
    'BUCKS\n'
    'COFFEE CO.\n'
    '가드고환권 50,000원권\n'
    '스타벅스\n'
    '스타벅스 e카드 5만원 교환권\n'
    '~2026년 07월 06일까지 사용\n'
    '교환처 : 스타벅스\n'
    '8809 8765 4321\n'
    '기업용\n'
    '내 마음의 선물, 기프티쇼 qiftishOW';

void main() {
  const GifticonOcrParser parser = GifticonOcrParser();

  group('카카오톡 선물하기 원문', () {
    test('브랜드·상품명을 뽑고 없는 금액·유효기간은 비운다', () {
      final GifticonOcrResult result = parser.parse(_kakaoGiftOcr);

      expect(result.brand, '스타벅스');
      expect(result.productName, '아이스 카페 아메리카노T');

      // 이 기프티콘에는 금액도 유효기간도 찍혀 있지 않다. 없는 값을 그럴듯하게
      // 채우는 쪽이 비우는 쪽보다 나쁘다 — 사용자가 검토 없이 저장한다.
      expect(result.price, isNull);
      expect(result.expiryDate, isNull);
    });

    test('"사용완료" 도장이 브랜드를 사이에 두고 갈라져도 상품명이 정확하다', () {
      // ML Kit은 도장 텍스트를 `사용` / `완료`로 쪼개 브랜드 앞뒤에 흩어 놓는다.
      // 두 조각이 각각 노이즈로 걸리지 않으면 브랜드 **다음 줄**이 `완료`가 되어
      // 그것이 상품명으로 잡힌다(뮤테이션 확인: noiseKeywords에서 '사용완료'·
      // '사용'·'완료' 셋만 지우면 productName이 '완료'로 뒤집힌다).
      //
      // ⚠️ 브랜드는 여기서 노이즈 필터가 지키는 것이 **아니다** — `_extractBrand`의
      // 사전 매칭이 줄 순서와 무관하게 `스타벅스`를 고르므로, 노이즈 필터를 통째로
      // 꺼도 brand 단언은 통과한다(아래 시계 테스트의 ⚠️와 같은 사실).
      expect(_kakaoGiftOcr.contains('사용\n스타벅스\n완료'), isTrue);

      final GifticonOcrResult result = parser.parse(_kakaoGiftOcr);

      expect(result.brand, '스타벅스');
      expect(result.productName, '아이스 카페 아메리카노T');
    });

    test('상태바 시계가 9:274로 읽힌다 — 브랜드로도 상품명으로도 오지 않는다', () {
      // ⚠️ 이 픽스처에서 브랜드를 지키는 것은 노이즈 필터가 **아니라** 브랜드
      // 사전이다 — `_isNoiseLine`을 통째로 무력화해도 이 단언은 통과한다
      // (뮤테이션으로 확인). 이름이 인과를 주장하지 않도록 여기서 남기는 것은
      // "실제 OCR이 초 자리를 붙여 세 자리로 읽는다"는 **사실**뿐이다.
      //
      // 시계 노이즈 규칙 자체는 사전에 없는 브랜드로
      // gifticon_ocr_brand_product_test.dart가 세 자리까지 포함해 고정한다.
      expect(_kakaoGiftOcr.contains('9:274'), isTrue);

      final GifticonOcrResult result = parser.parse(_kakaoGiftOcr);

      expect(result.brand, isNot('9:274'));
      expect(result.productName, isNot('9:274'));
    });
  });

  group('기프티쇼 원문', () {
    test('브랜드·상품명·금액·유효기간을 모두 뽑는다', () {
      final GifticonOcrResult result = parser.parse(_giftishowOcr);

      expect(result.brand, '스타벅스');
      expect(result.productName, '스타벅스 e카드 5만원 교환권');
      expect(result.price, '50000');
      expect(result.expiryDate, DateTime(2026, 7, 6));
    });

    test('유효기간 줄이 노이즈로 걸러져도 만료일은 뽑힌다', () {
      // `~2026년 07월 06일까지 사용`은 '사용'을 담고 있어 _isNoiseLine에
      // 걸린다. 그런데도 날짜가 나오는 것은 _extractExpiryDate가 걸러진 줄이
      // 아니라 **원문 전체**를 보기 때문이다. 날짜 추출을 걸러진 줄 기준으로
      // 바꾸면 이 기프티콘의 유효기간이 통째로 사라진다.
      expect(_giftishowOcr.contains('~2026년 07월 06일까지 사용'), isTrue);

      expect(parser.parse(_giftishowOcr).expiryDate, DateTime(2026, 7, 6));
    });

    test('상품명 줄의 "5만원"은 금액이 아니고, 오인식된 줄이 금액을 준다', () {
      // 원문에서 금액이 붙은 줄은 "카드교환권"이 `가드고환권`으로 잘못 읽힌
      // 줄이다. 상품명 줄의 "5만원"은 숫자+단위 형태가 아니라 잡히지 않는다.
      //
      // 두 줄을 **따로** 파싱해야 이 인과가 고정된다 — 원문 전체만 보면
      // `price == '50000'`은 위 '모두 뽑는다'와 같은 단언이라 단독으로
      // 실패할 수 없다.
      expect(parser.parse('스타벅스 e카드 5만원 교환권').price, isNull);
      expect(parser.parse('가드고환권 50,000원권').price, '50000');

      expect(_giftishowOcr.contains('가드고환권 50,000원권'), isTrue);
      expect(parser.parse(_giftishowOcr).price, '50000');
    });

    test('브랜드 사전이 BUCKS·COFFEE CO.보다 뒤에 있는 스타벅스를 고른다', () {
      // 로고가 먼저 읽혀 `BUCKS`, `COFFEE CO.`가 앞줄에 온다. 사전 매칭이
      // 없으면 이 중 하나가 브랜드가 된다.
      final GifticonOcrResult result = parser.parse(_giftishowOcr);

      expect(result.brand, '스타벅스');
      expect(result.brand, isNot('BUCKS'));
    });
  });

  group('픽스처 무결성', () {
    // 익명화가 지켜야 할 **형태 불변식**. 값이 아니라 이 모양이 파서 판정을
    // 결정하므로, 여기가 깨지면 파싱 결과가 그대로여도 픽스처가 실제 입력을
    // 대표하지 못한다. 수집 당시의 일회성 대조를 상시 가드로 옮긴 것이다.
    test('익명화된 바코드가 원문의 형태 불변식을 유지한다', () {
      for (final String line in <String>[
        '8801 2345 6789 0',
        '8809 8765 4321'
      ]) {
        expect(_kakaoGiftOcr.contains(line) || _giftishowOcr.contains(line),
            isTrue,
            reason: '픽스처에 없는 줄: $line');

        // 콤마가 들어가면 금액으로, `.`/`-`/`/`가 들어가면 날짜로 새어
        // 브랜드·상품명 후보 배제 규칙이 달라진다.
        expect(line.contains(','), isFalse, reason: line);
        expect(RegExp(r'[.\-/]').hasMatch(line), isFalse, reason: line);

        // `_looksLikeBarcode`가 보는 것은 자릿수뿐이다(8~30).
        final int digits = line.replaceAll(RegExp(r'\D'), '').length;
        expect(digits, inInclusiveRange(8, 30), reason: line);
      }
    });

    test('두 픽스처가 서로 다른 바코드를 쓴다', () {
      // 같은 숫자를 공유하면 한쪽을 고칠 때 다른 쪽이 조용히 함께 바뀐다.
      expect(_kakaoGiftOcr.contains('8809 8765 4321'), isFalse);
      expect(_giftishowOcr.contains('8801 2345 6789 0'), isFalse);
    });
  });
}
