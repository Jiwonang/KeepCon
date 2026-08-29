/// GifticonOcrParser 실제 기프티콘 픽스처 테스트.
///
/// 아래 세 상수는 **손으로 지어낸 텍스트가 아니라** 실제 기프티콘 이미지를
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
/// ## 사전 밖 브랜드 — 폴백 경로는 실제로 동작했다
/// 앞의 두 픽스처는 브랜드가 모두 `스타벅스`라 `_extractBrand`가 1단계 **사전
/// 매칭에서 끝났다.** 그래서 2단계 "유효한 첫 번째 줄" 폴백이 미검증이었고,
/// 픽스처의 브랜드 단어만 사전 밖 값으로 바꿔 보면 기프티쇼는
/// `기프티쇼 선물이 도착했어요!`를, 카카오톡은 보낸이 인사말을 브랜드로 냈다.
///
/// 그래서 세 번째 픽스처(`_kakaoBarcodeCardOcr`, `노랑통닭` — 사전 밖)를
/// 수집했는데, **폴백이 정확히 동작했다.** ML Kit이 브랜드를 첫 줄에 놓았기
/// 때문이다. 위험이 없다는 뜻은 아니고 **크기가 다르다**는 뜻이다 — "사전 밖이면
/// 망가진다"가 아니라 "ML Kit이 브랜드를 앞에 놓지 않으면 망가진다"이다.
/// 텍스트만 바꿔 예측했다면 이 결과를 얻지 못했다.
///
/// ⚠️ 다만 첫 픽스처가 통과하는 것은 여전히 브랜드가 사전에 있어서다.
/// `_isNoiseLine`의 `noiseKeywords`에는 **UI 크롬이 아닌** 문자열이 넷 섞여
/// 있다 — `응원합니다`는 보낸 사람의 자유 입력이고, `사용`·`완료`·`기프티콘`은
/// 상품명·안내 문구에 흔한 부분문자열이다(`~2026년 07월 06일까지 사용`이 통째로
/// 노이즈로 걸리는 것을 아래 '유효기간' 테스트가 보여준다). 사전을 끄고
/// `응원합니다`를 빼면 첫 픽스처의 브랜드는 `"응원합니다!"`가 된다 — 실측이다.
///
/// ## ⚠️ 알려진 결함 — 상품명 잘림 (일부러 고정하지 않는다)
/// 세 번째 픽스처에서 상품명이 두 줄로 쪼개졌는데(`…콜라1.` / `25L`) 파서는
/// **첫 줄만** 쓴다. 사용자에게는 문장 중간에서 끊긴 값이 저장된다.
///
/// 고치면 프리필 표시가 바뀌므로 제품 결정이고, 이어붙이는 규칙을 샘플 한 장으로
/// 설계하면 그 한 장에 과적합된다 — 끊긴 자리가 `1.25L`의 **숫자 한가운데**라
/// 여기서는 "마침표로 끝나면 이어붙인다"가 정답을 낸다(`콜라1.` + `25L`).
/// 그런데 그건 마침표가 소수점이라서지 문장이 이어져서가 아니다. 같은 규칙을
/// 마침표로 끝나는 정상 문장에 적용하면 전부 틀린다 — 이 한 장은 **틀린 규칙을
/// 옳아 보이게 만든다.** 그래서 이 파일은
/// 잘린 값을 **계약으로 승격시키지 않고**, 수정 여부와 무관하게 참인 것만
/// 고정한다(상품명이 `(오리지널/순살)`로 시작한다 · 라벨이나 로고가 아니다).
///
/// ## 이 파일의 테스트 개수를 회귀 커버리지로 읽지 말 것
/// 같은 입력에 대한 단언이라 **단독으로 실패할 수 없는** 테스트가 섞여 있다.
/// 파서를 망가뜨리는 뮤테이션은 종합 테스트를 먼저 죽이므로 이들은 항상 같이
/// 죽는다. 그래도 남겨 둔 이유는 각자 `expect(_kakaoGiftOcr.contains(...))` 류의
/// **픽스처 무결성 트립와이어**를 갖고 있어, 누가 상수를 조용히 편집하면 그쪽이
/// 먼저 울기 때문이다.
///
///   - 독립 회귀 가드 7건: 종합 3건(카카오 상세·기프티쇼·바코드 카드) ·
///     금액 인과 1건 · 상품명 시작 1건 · 무결성 2건
///   - 종합 테스트에 종속(문서 + 트립와이어) 7건: 도장 · 시계 · 유효기간 ·
///     사전 · 라벨분리 · 로고 · 주문번호
///
/// 뮤테이션 8종으로 확인한 분류다. 예컨대 `pepsi`·주문번호 테스트는 어떤
/// 뮤테이션에서도 죽지 않는다 — 이 픽스처는 브랜드가 첫 줄이라 로고나 숫자열이
/// 이길 수 없기 때문이다. 그 둘이 이기는 배치의 원문을 아직 수집하지 못했다.
///
/// ## 익명화
/// 저장소가 Public이므로 **값만** 바꾸고 **모양은 그대로 뒀다** — 파서가 보는
/// 것은 값이 아니라 형태(`.+의 선물$`, 8~30자리 숫자)이기 때문에 검증 범위는
/// 줄지 않는다. 바꾼 것은 세 가지뿐이다.
///   - 보낸 사람 실명 → `민서` (카카오톡 선물 상세. 나머지 둘에는 실명이 없다)
///   - 바코드 숫자 → 자릿수·구분자가 같은 다른 숫자
///     (카카오톡 선물 상세 13자리 · 기프티쇼 12자리 · 바코드 카드 12자리)
///   - 주문번호 → 자릿수가 같은 다른 숫자 (바코드 카드 10자리)
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

/// 카카오톡 선물하기 **바코드 카드** 화면 — 노랑통닭(사전 밖 브랜드) 치킨 세트.
///
/// 앞의 둘과 화면 종류가 다르다. 화면에서는 `교환처 / 유효기간 / 주문번호`가
/// 각각 `라벨 — 값` 한 줄인데, ML Kit은 **왼쪽 라벨 칸 셋을 먼저 묶고 오른쪽 값
/// 칸 셋을 나중에** 뱉는다. 라벨↔값 연결이 통째로 사라진다.
///
/// 그리고 상품 사진의 콜라병 로고에서 `pepsi`가 텍스트로 읽혀 라벨 사이에
/// 끼어든다 — **사진이 브랜드 같은 토큰을 주입한다.**
///
/// 이 픽스처가 처음 들여온 성질이 하나 더 있다: **브랜드 문자열이 두 번 나온다**
/// (0번 줄 제목, 8번 줄 `교환처`의 값). `_extractProductName`이 `indexWhere`로
/// **첫 출현**을 쓰기 때문에 상품명이 바로 다음 줄에서 잡힌다 —
/// `lastIndexWhere`로 바꾸면 상품명이 null이 된다(뮤테이션 확인).
const String _kakaoBarcodeCardOcr = '노랑통닭\n'
    '(오리지널/순살) 3종세트+콜라1.\n'
    '25L\n'
    '교환처\n'
    '유효기간\n'
    'pepsi\n'
    '주문번호\n'
    '8803 1122 3344\n'
    '노랑통닭\n'
    '2024년 06월 08일\n'
    '1029384756\n'
    'kakaotalk선물하기';

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

  group('카카오톡 바코드 카드 원문 — 사전 밖 브랜드', () {
    test('사전에 없는 브랜드를 폴백으로 정확히 잡는다', () {
      final GifticonOcrResult result = parser.parse(_kakaoBarcodeCardOcr);

      // `노랑통닭`은 _knownBrands 27개에 없다. 1단계가 비고 2단계 "유효한 첫
      // 줄" 폴백이 답을 낸다 — ML Kit이 브랜드를 첫 줄에 놓았기 때문이다.
      expect(result.brand, '노랑통닭');

      expect(result.price, isNull);
      expect(result.expiryDate, DateTime(2024, 6, 8));
    });

    test('상품명이 라벨도 로고도 아니고 상품명 줄에서 시작한다', () {
      final GifticonOcrResult result = parser.parse(_kakaoBarcodeCardOcr);

      // ⚠️ 값 전체를 고정하지 않는다 — 현재는 `…콜라1.`로 잘려 있고 그것은
      // 결함이다(파일 상단 참조). 아래 단언은 잘림을 고치든 안 고치든 참이다.
      expect(result.productName, startsWith('(오리지널/순살)'));

      // ⚠️ 아래 셋은 이 픽스처에서 죽지 않는다 — 브랜드가 0번, 상품명이 1번
      // 줄이라 탐색이 라벨(3~6번)까지 내려오지 않는다. 남기는 것은 판정이 아니라
      // **비대칭 사실**이다: 셋 중 `유효기간`만 `_isExpiryRelatedText`가 막고
      // `교환처`·`주문번호`는 어떤 가드도 없다(실측 — 단독 파싱 시 각각
      // brand=`교환처` / null / brand=`주문번호`). 라벨 칸이 브랜드보다 앞서는
      // 배치에서는 brand=`교환처`, productName=`주문번호`가 된다. 그 가드를 지금
      // 넣으면 현재 동작을 계약으로 굳히므로, 프리필 표시 결정과 함께 다룬다.
      expect(result.productName, isNot('교환처'));
      expect(result.productName, isNot('유효기간'));
      expect(result.productName, isNot('주문번호'));

      // 상품 사진에서 읽힌 로고도 마찬가지다.
      expect(result.productName, isNot('pepsi'));
    });

    test('라벨 칸과 값 칸이 분리돼도 만료일은 뽑힌다', () {
      // 화면에서는 `유효기간 — 2024년 06월 08일`이 한 줄인데 OCR은 둘을 떼어
      // 놓는다. 날짜가 나오는 것은 _extractExpiryDate가 라벨과의 인접성이 아니라
      // **원문 전체의 날짜 모양**을 보기 때문이다.
      expect(_kakaoBarcodeCardOcr.contains('유효기간\npepsi'), isTrue);

      expect(
        parser.parse(_kakaoBarcodeCardOcr).expiryDate,
        DateTime(2024, 6, 8),
      );
    });

    test('상품 사진의 로고(pepsi)가 브랜드가 되지 않는다', () {
      // ⚠️ 이 단언은 **어떤 뮤테이션에서도 죽지 않는다.** 이 픽스처는 브랜드가
      // 첫 줄이라 로고가 이길 수 없기 때문이다. 여기서 남기는 것은 판정이 아니라
      // **사실**이다 — 상품 사진이 브랜드 같은 토큰을 주입한다는 것. 로고가
      // 브랜드보다 앞서는 배치의 원문을 아직 수집하지 못했다.
      expect(_kakaoBarcodeCardOcr.contains('pepsi'), isTrue);

      expect(parser.parse(_kakaoBarcodeCardOcr).brand, isNot('pepsi'));
    });

    test('주문번호 숫자열이 브랜드·상품명 후보에서 빠진다', () {
      // ⚠️ 위와 같다 — `_looksLikeBarcode`를 통째로 꺼도 이 단언은 통과한다
      // (뮤테이션 확인). 브랜드가 첫 줄이고 상품명이 그 다음 줄이라 주문번호까지
      // 순서가 내려오지 않는다. 바코드 배제 규칙 자체는 지어낸 입력으로
      // gifticon_ocr_brand_product_test.dart가 고정한다.
      final GifticonOcrResult result = parser.parse(_kakaoBarcodeCardOcr);

      expect(result.brand, isNot('1029384756'));
      expect(result.productName, isNot('1029384756'));
    });
  });

  group('픽스처 무결성', () {
    // 익명화가 지켜야 할 **형태 불변식**. 값이 아니라 이 모양이 파서 판정을
    // 결정하므로, 여기가 깨지면 파싱 결과가 그대로여도 픽스처가 실제 입력을
    // 대표하지 못한다. 수집 당시의 일회성 대조를 상시 가드로 옮긴 것이다.
    test('익명화된 숫자열이 원문의 형태 불변식을 유지한다', () {
      for (final String line in <String>[
        '8801 2345 6789 0', // 카카오톡 선물 상세 — 바코드
        '8809 8765 4321', // 기프티쇼 — 바코드
        '8803 1122 3344', // 카카오톡 바코드 카드 — 바코드
        '1029384756', // 카카오톡 바코드 카드 — 주문번호
      ]) {
        expect(
            _kakaoGiftOcr.contains(line) ||
                _giftishowOcr.contains(line) ||
                _kakaoBarcodeCardOcr.contains(line),
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

    test('픽스처마다 서로 다른 숫자열을 쓴다', () {
      // 같은 숫자를 공유하면 한쪽을 고칠 때 다른 쪽이 조용히 함께 바뀐다.
      const Map<String, String> owner = <String, String>{
        '8801 2345 6789 0': 'kakaoGift',
        '8809 8765 4321': 'giftishow',
        '8803 1122 3344': 'barcodeCard',
        '1029384756': 'barcodeCard',
      };

      final Map<String, String> fixtures = <String, String>{
        'kakaoGift': _kakaoGiftOcr,
        'giftishow': _giftishowOcr,
        'barcodeCard': _kakaoBarcodeCardOcr,
      };

      owner.forEach((String line, String ownerName) {
        fixtures.forEach((String name, String text) {
          if (name == ownerName) return;
          expect(text.contains(line), isFalse,
              reason: '$line 이(가) $ownerName 말고 $name 에도 있다');
        });
      });
    });
  });
}
