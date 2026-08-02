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
      if (_isPriceLine(line)) continue;
      if (_containsDate(line)) continue;
      if (_looksLikeBarcode(line)) continue;
      if (_isExpiryRelatedText(line)) continue;

      return line;
    }

    return null;
  }

  /// 상품명 추출.
  String? _extractProductName(List<String> lines, String? brand) {
    if (lines.isEmpty) return null;

    int startIndex = 0;
    if (brand != null) {
      final int foundIndex = lines.indexWhere((line) => line.contains(brand));
      if (foundIndex != -1) {
        startIndex = foundIndex + 1;
      }
    }

    for (int i = startIndex; i < lines.length; i++) {
      final String line = lines[i];

      if (_isPriceLine(line)) continue;
      if (_containsDate(line)) continue;
      if (_looksLikeBarcode(line)) continue;
      if (_isExpiryRelatedText(line)) continue;

      return line;
    }

    return null;
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
