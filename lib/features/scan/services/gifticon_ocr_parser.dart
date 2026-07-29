/// ML Kit OCR로 인식한 텍스트에서
/// 기프티콘 폼에 넣을 데이터를 추출하는 파서.
class GifticonOcrParser {
  const GifticonOcrParser();

  /// OCR 전체 텍스트를 분석한다.
  GifticonOcrResult parse(String text) {
    final List<String> lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    return GifticonOcrResult(
      brand: _extractBrand(lines),
      productName: _extractProductName(lines),
      price: _extractPrice(text),
      expiryDate: _extractExpiryDate(text),
    );
  }

  /// 브랜드명 추출.
  ///
  /// 현재는 명확한 브랜드 사전이 없기 때문에
  /// 추후 브랜드 목록/DB와 연결할 수 있도록 기본적인 후보를 반환한다.
  String? _extractBrand(List<String> lines) {
    if (lines.isEmpty) {
      return null;
    }

    // 가격/날짜/바코드처럼 보이는 줄은 제외한다.
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
  ///
  /// 현재는 브랜드명으로 사용된 첫 번째 후보 다음 줄을
  /// 상품명 후보로 사용한다.
  String? _extractProductName(List<String> lines) {
    final String? brand = _extractBrand(lines);

    if (brand == null) {
      return null;
    }

    final int brandIndex = lines.indexOf(brand);

    if (brandIndex == -1) {
      return null;
    }

    for (int i = brandIndex + 1; i < lines.length; i++) {
      final String line = lines[i];

      if (_isPriceLine(line)) continue;
      if (_containsDate(line)) continue;
      if (_looksLikeBarcode(line)) continue;
      if (_isExpiryRelatedText(line)) continue;

      return line;
    }

    return null;
  }

  /// 금액 추출.
  ///
  /// 예:
  /// 4,500원
  /// 4500원
  /// ₩4,500
  /// 4500
  String? _extractPrice(String text) {
    final RegExp pricePattern = RegExp(
      r'(?:₩\s*)?(\d{1,3}(?:,\d{3})+|\d{3,6})\s*원?',
    );

    final Match? match = pricePattern.firstMatch(text);

    if (match == null) {
      return null;
    }

    final String value = match.group(1)!.replaceAll(',', '');

    return value;
  }

  /// 유효기간 추출.
  ///
  /// 지원 예:
  /// 2026.12.31
  /// 2026-12-31
  /// 2026/12/31
  /// 2026년 12월 31일
  /// 26.12.31
  DateTime? _extractExpiryDate(String text) {
    // YYYY.MM.DD
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

    // YY.MM.DD
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

      // 잘못된 날짜가 자동 보정되는 것을 방지한다.
      if (date.year != year || date.month != month || date.day != day) {
        return null;
      }

      return date;
    } catch (_) {
      return null;
    }
  }

  bool _isPriceLine(String line) {
    return RegExp(
      r'(?:₩\s*)?\d{1,3}(?:,\d{3})+\s*원?',
    ).hasMatch(line);
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

/// OCR에서 추출한 기프티콘 정보.
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
