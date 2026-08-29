/// ML Kit OCR로 인식한 텍스트에서
/// 기프티콘 폼에 넣을 데이터를 추출하는 파서.
class GifticonOcrParser {
  const GifticonOcrParser();

  /// 알려진 주요 브랜드 사전 목록 (우선순위 매칭용)
  static const List<String> _knownBrands = [
    '스타벅스',
    '투썸플레이스',
    '이디야',
    '메가커피',
    '컴포즈커피',
    '할리스',
    '탐앤탐스',
    '파스쿠찌',
    '폴바셋',
    '배스킨라빈스',
    '던킨',
    '설빙',
    'GS25',
    'CU',
    '세븐일레븐',
    '이마트24',
    'BHC',
    '교촌치킨',
    '굽네치킨',
    'BBQ',
    'Dominos',
    '도미노피자',
    '맥도날드',
    '버거킹',
    '롯데리아',
    'CGV',
    '메가박스',
    '롯데시네마',
  ];

  /// OCR 전체 텍스트를 분석한다.
  GifticonOcrResult parse(String text) {
    final List<String> lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !_isNoiseLine(line)) // 상단 시계, 카카오톡 UI 등 노이즈 제거
        .toList();

    final String? brand = _extractBrand(lines);

    return GifticonOcrResult(
      brand: brand,
      productName: _extractProductName(lines, brand),
      price: _extractPrice(text),
      expiryDate: _extractExpiryDate(text),
    );
  }

  /// 브랜드명 추출.
  String? _extractBrand(List<String> lines) {
    if (lines.isEmpty) return null;

    // 1. 알려진 브랜드 사전 매칭 (최우선)
    for (final line in lines) {
      for (final knownBrand in _knownBrands) {
        if (line.contains(knownBrand)) {
          return knownBrand;
        }
      }
    }

    // 2. 사전에 없을 경우 유효한 첫 번째 줄 사용
    for (final line in lines) {
      if (_isContentLine(line)) return line;
    }

    return null;
  }

  /// 값이 아니라 **메타데이터**(금액·날짜·바코드·유효기간)로 보이는 줄을 뺀 것.
  /// 브랜드 후보와 상품명 후보가 공유하는 하한이다.
  ///
  /// ⚠️ 라벨 가드([_isFieldLabelLine])는 **여기 없다** — 상품명에만 얹는다.
  /// 브랜드는 이어붙이지 않아 흡수 위험이 없고, 라벨 칸이 브랜드보다 앞서는
  /// 배치를 아직 수집하지 못해 근거 없이 동작을 바꾸지 않는다. 그 결과
  /// `parse('교환처\n아메리카노\n4,500원')`은 brand=`교환처`다(실측).
  bool _isContentLine(String line) {
    return !_isPriceLine(line) &&
        !_containsDate(line) &&
        !_looksLikeBarcode(line) &&
        !_isExpiryRelatedText(line);
  }

  /// 상품명 추출.
  ///
  /// 첫 후보 줄 하나만 쓰지 않고 **연속된 후보 줄을 이어붙인다.** 긴 상품명은
  /// 화면에서 줄바꿈되고, ML Kit은 그 시각적 줄을 그대로 별개 줄로 돌려주기
  /// 때문이다. 첫 줄만 쓰면 사용자에게 문장 중간에서 끊긴 이름이 저장된다
  /// (`슈퍼슈프림(오리지` · `(오리지널/순살) 3종세트+콜라1.`).
  ///
  /// **구분자 없이 붙인다.** 실측한 두 원문 모두 그래야 복원된다 —
  /// `슈퍼슈프림(오리지`+`널)L+…`는 **단어 한가운데**서, `…콜라1.`+`25L`은
  /// `1.25L`의 **소수점 한가운데**서 끊겼다. 한글은 어느 글자에서든 줄바꿈되므로
  /// 이 편이 일반적이다. 공백 경계에서 줄바꿈된 이름은 공백 하나를 잃겠지만
  /// (그런 원문은 아직 수집하지 못했다), 그 손실은 지금의 **잘림보다 작다.**
  ///
  /// ## ⚠️ 알려진 한계 — 가드 밖의 줄은 흡수된다
  /// 축적은 위 5종 가드 중 하나를 만날 때까지 무제한이라, 상품명 뒤에 수량
  /// (`1잔`)·사진 로고(`pepsi`)·안내문구·목록 밖 라벨(`발행처`)이 오면 이름에
  /// 딸려 붙는다. 구분자가 없어 **잘림보다 알아보기 어렵다.**
  ///
  /// ⚠️ **ML Kit의 블록 구조로는 풀리지 않는다** — 그럴듯한 해법처럼 보여서
  /// 실측했고, 전제가 **반대**였다. `RecognizedText.blocks`를 찍어 보면
  /// 줄바꿈된 상품명이 **서로 다른 블록**이고(도미노 `슈퍼슈프림(오리지`=블록1 /
  /// `널)L+…`=블록2, 노랑통닭 `…콜라1.`=블록1 / `25L`=블록2), 오히려 무관한 필드
  /// 둘이 한 블록에 묶인다(도미노 블록8 = `교환처 :…` + `유효기간 :…`).
  /// "같은 블록이면 이어진 상품명"은 **거짓**이다.
  ///
  /// 신호가 있다면 **좌표**다 — 이어진 조각은 왼쪽 정렬이 같고 세로로 인접하다
  /// (도미노 둘 다 `x=64`, y 간격 47 ≈ 줄높이 48. 다음 필드는 y 간격 364).
  /// 다만 "얼마나 가까우면 이어진 것인가"라는 임계값이 필요하고, 가운데 정렬인
  /// 기프티쇼는 x가 84px 벌어지는 반면 노랑통닭은 14px이라 **샘플 4장으로 그
  /// 숫자를 정하면 과적합**이다. 원문이 더 모이면 그때 다룬다.
  String? _extractProductName(List<String> lines, String? brand) {
    if (lines.isEmpty) return null;

    int startIndex = 0;
    if (brand != null) {
      final int foundIndex = lines.indexWhere((line) => line.contains(brand));
      if (foundIndex != -1) {
        startIndex = foundIndex + 1;
      }
    }

    final StringBuffer name = StringBuffer();

    for (int i = startIndex; i < lines.length; i++) {
      final String line = lines[i];

      if (!_isProductNameCandidate(line)) {
        // 아직 이름이 시작되지 않았으면 계속 건너뛴다. 이미 시작됐다면 여기가
        // 끝이다 — 상품명 뒤의 첫 비후보 줄이 경계다.
        if (name.isEmpty) continue;
        break;
      }

      name.write(line);
    }

    if (name.isNotEmpty) return name.toString();

    // 라벨 구조 규칙이 **유일한 후보**를 삼킨 경우(`아메리카노 : 라지`).
    // 상품명은 폼의 필수 필드라 빈 값이 잘린 값보다 나쁘다 — 라벨 가드를 뺀
    // 하한으로 한 번 더 훑어 옛 동작으로 되돌아간다.
    //
    // ⚠️ 이 폴백은 한 줄만 돌려준다(이어붙이지 않는다). 라벨 오탐과 줄바꿈이
    // 겹친 원문은 여전히 앞부분만 남는다 — 그런 원문은 아직 수집하지 못했다.
    for (int i = startIndex; i < lines.length; i++) {
      if (_isContentLine(lines[i])) return lines[i];
    }

    return null;
  }

  /// 상품명 후보가 될 수 있는 줄인지.
  bool _isProductNameCandidate(String line) {
    return _isContentLine(line) && !_isFieldLabelLine(line);
  }

  /// 기프티콘 카드의 **필드 라벨** 줄인지.
  ///
  /// 상품명을 이어붙일 때 여기서 멈추지 않으면 라벨이 이름에 딸려 들어간다
  /// (`…콜라1.25L교환처`). 실측한 원문에서 두 형태로 나타난다.
  ///
  ///   - `교환처 :도미노파자 웹사이트` — 라벨과 값이 한 줄
  ///   - `교환처` — 라벨 칸만 따로. ML Kit이 왼쪽 라벨 칸 셋을 먼저 묶고 오른쪽
  ///     값 칸 셋을 나중에 뱉는 배치에서 이렇게 나온다
  ///
  /// 앞의 형태는 **이름을 열거하지 않고 구조로** 잡는다 — 짧은 한글 낱말 뒤에
  /// 콜론이 오는 줄. 목록으로 두면 처음 보는 라벨에서 그대로 뚫린다. 뒤의 형태는
  /// 구조 신호가 없어 목록이 필요하고, **실제로 관측한 것만** 넣는다
  /// (`유효기간`·`사용기한`은 [_isExpiryRelatedText]가 이미 막는다).
  static const List<String> _bareFieldLabels = <String>['교환처', '주문번호'];

  bool _isFieldLabelLine(String line) {
    if (RegExp(r'^[가-힣]{2,5}\s*:').hasMatch(line)) return true;

    return _bareFieldLabels.contains(line);
  }

  /// 상단 노이즈 및 카카오톡 UI 텍스트 필터링
  bool _isNoiseLine(String line) {
    // 1. 시간 형태 (예: 9:27, 09:27, 9:274 등 상단 상태바 오인식)
    if (RegExp(r'^\d{1,2}:\d{2,3}$').hasMatch(line)) return true;

    // 2. 카카오톡 선물하기 UI 문구 및 메타데이터
    final List<String> noiseKeywords = [
      '선물하기',
      '선물추억',
      '응원합니다',
      '나도 선물하기',
      '후기 작성',
      '사용완료',
      '사용',
      '완료',
      '삭제',
      '상세보기',
      '기프티콘',
    ];

    for (final keyword in noiseKeywords) {
      if (line.contains(keyword)) return true;
    }

    // 3. "~의 선물" 형태의 보낸 사람 문구
    if (RegExp(r'.+의\s*선물$').hasMatch(line)) return true;

    return false;
  }

  static final RegExp _pricePattern = RegExp(
    r'₩[ \t]*(\d{1,3}(?:,\d{3})+|\d+)'
    r'|(\d{1,3}(?:,\d{3})+|\d+)[ \t]*원'
    r'|(\d{1,3}(?:,\d{3})+)',
  );

  String? _extractPrice(String text) {
    final Match? match = _pricePattern.firstMatch(text);
    if (match == null) return null;

    final String value = (match.group(1) ?? match.group(2) ?? match.group(3))!
        .replaceAll(',', '');

    return value;
  }

  DateTime? _extractExpiryDate(String text) {
    final RegExp fullDatePattern = RegExp(
      r'(20\d{2})[.\-/년]\s*(\d{1,2})[.\-/월]\s*(\d{1,2})일?',
    );

    final Match? fullMatch = fullDatePattern.firstMatch(text);
    if (fullMatch != null) {
      return _createDate(
        year: int.parse(fullMatch.group(1)!),
        month: int.parse(fullMatch.group(2)!),
        day: int.parse(fullMatch.group(3)!),
      );
    }

    final RegExp shortDatePattern = RegExp(
      r'(\d{2})[.\-/]\s*(\d{1,2})[.\-/]\s*(\d{1,2})',
    );

    final Match? shortMatch = shortDatePattern.firstMatch(text);
    if (shortMatch != null) {
      return _createDate(
        year: 2000 + int.parse(shortMatch.group(1)!),
        month: int.parse(shortMatch.group(2)!),
        day: int.parse(shortMatch.group(3)!),
      );
    }

    return null;
  }

  DateTime? _createDate({
    required int year,
    required int month,
    required int day,
  }) {
    try {
      final DateTime date = DateTime(year, month, day);
      if (date.year != year || date.month != month || date.day != day) {
        return null;
      }
      return date;
    } catch (_) {
      return null;
    }
  }

  bool _isPriceLine(String line) {
    return _pricePattern.hasMatch(line);
  }

  bool _containsDate(String line) {
    return RegExp(
      r'(20\d{2}|\d{2})[.\-/년]\s*\d{1,2}[.\-/월]\s*\d{1,2}',
    ).hasMatch(line);
  }

  bool _looksLikeBarcode(String line) {
    final String digitsOnly = line.replaceAll(RegExp(r'\D'), '');
    return digitsOnly.length >= 8 && digitsOnly.length <= 30;
  }

  bool _isExpiryRelatedText(String line) {
    final String normalized = line.toLowerCase();
    return normalized.contains('유효기간') ||
        normalized.contains('사용기한') ||
        normalized.contains('만료') ||
        normalized.contains('valid') ||
        normalized.contains('expiry');
  }
}

class GifticonOcrResult {
  const GifticonOcrResult({
    this.brand,
    this.productName,
    this.price,
    this.expiryDate,
  });

  final String? brand;
  final String? productName;
  final String? price;
  final DateTime? expiryDate;
}
