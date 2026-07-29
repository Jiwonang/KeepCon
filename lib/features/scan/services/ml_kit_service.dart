import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// ML Kit을 이용해 기프티콘 이미지에서
/// OCR 텍스트와 바코드 정보를 추출하는 서비스.
class MlKitService {
  MlKitService()
      // 기프티콘 텍스트는 대부분 한국어이므로 korean 스크립트를 사용한다.
      //
      // latin 스크립트는 "스타벅스", "유효기간" 같은 한글을 인식하지 못해
      // OCR 결과가 비어 나오는 원인이 된다.
      // (korean 인식기는 한글과 라틴 문자를 모두 인식한다)
      : _textRecognizer = TextRecognizer(
          script: TextRecognitionScript.korean,
        ),
        _barcodeScanner = BarcodeScanner();

  final TextRecognizer _textRecognizer;
  final BarcodeScanner _barcodeScanner;

  /// 이미지에서 텍스트를 인식한다.
  Future<String> recognizeText(InputImage image) async {
    final RecognizedText recognizedText =
        await _textRecognizer.processImage(image);

    return recognizedText.text;
  }

  /// 이미지에서 바코드/QR 코드를 인식한다.
  Future<List<Barcode>> scanBarcodes(InputImage image) async {
    return _barcodeScanner.processImage(image);
  }

  /// 이미지에서 OCR과 바코드를 한 번에 인식한다.
  Future<MlKitScanResult> scan(InputImage image) async {
    final results = await Future.wait([
      recognizeText(image),
      scanBarcodes(image),
    ]);

    return MlKitScanResult(
      text: results[0] as String,
      barcodes: results[1] as List<Barcode>,
    );
  }

  /// 리소스를 정리한다.
  Future<void> dispose() async {
    await _textRecognizer.close();
    await _barcodeScanner.close();
  }
}

/// ML Kit 스캔 결과.
class MlKitScanResult {
  const MlKitScanResult({
    required this.text,
    required this.barcodes,
  });

  final String text;
  final List<Barcode> barcodes;

  /// 인식된 바코드의 rawValue 중 첫 번째 값.
  String? get firstBarcodeValue {
    for (final barcode in barcodes) {
      final value = barcode.rawValue?.trim();

      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }
}
