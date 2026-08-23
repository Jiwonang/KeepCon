import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/util/keep_all_ko.dart';

/// WORD JOINER — [keepAllKo]가 심는 문자. 검증할 때는 다시 걷어내고 본다.
const String _wordJoiner = '\u2060';

/// [text]를 [maxWidth]로 접었을 때 실제로 나오는 줄들.
///
/// 문자열 비교가 아니라 **실제 레이아웃 엔진의 줄바꿈 결과**를 본다 — U+2060이
/// 줄바꿈을 막는다는 것은 유니코드 규격의 주장이므로, Flutter가 그 규격을
/// 따르는지는 재어서 확인해야 한다.
List<String> _layoutLines(String text, double maxWidth) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: 14)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);

  final List<String> lines = <String>[];
  int offset = 0;
  while (offset < text.length) {
    final TextRange range = painter.getLineBoundary(
      TextPosition(offset: offset),
    );
    if (range.end <= offset) break; // 진행이 없으면 중단(무한 루프 방지)
    lines.add(text.substring(range.start, range.end));
    offset = range.end;
  }
  painter.dispose();
  return lines;
}

/// 접힌 줄들이 원문의 어절을 **쪼개지 않고** 담고 있는가.
///
/// 어절이 갈라졌다면 '납니다.'가 '납' + '니다.'로 나뉘어 목록이 달라진다.
bool _keepsWordsWhole(String original, List<String> lines) {
  final List<String> expected =
      original.split(' ').where((String w) => w.isNotEmpty).toList();
  final List<String> actual = lines
      .expand(
          (String line) => line.replaceAll(_wordJoiner, '').trim().split(' '))
      .where((String w) => w.isNotEmpty)
      .toList();
  return listEquals(expected, actual);
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('keepAllKo', () {
    test('보이는 문구를 바꾸지 않는다 (WORD JOINER만 걷어내면 원문)', () {
      const String sentence = '무료 플랜은 10개까지 보관할 수 있어, 이번 기프티콘은 저장하지 않았어요.';

      expect(keepAllKo(sentence).replaceAll(_wordJoiner, ''), sentence);
    });

    test('좁은 폭에서 어절 중간이 갈라지지 않는다', () {
      const String sentence = '다 쓴 기프티콘을 사용 완료 처리하면 자리가 납니다.';
      // 다이얼로그가 좁은 기기에서 갖는 폭보다 더 좁게 잡아 확실히 접히게 한다.
      const double narrow = 120;

      final List<String> plain = _layoutLines(sentence, narrow);
      final List<String> kept = _layoutLines(keepAllKo(sentence), narrow);

      // 전제: 이 폭에서 실제로 여러 줄로 접혀야 비교가 의미를 갖는다.
      expect(
        plain.length,
        greaterThan(1),
        reason: '한 줄에 들어가면 줄바꿈 규칙을 검증하지 못한다',
      );

      // 수정 전 동작 — 한글은 음절 사이 어디서나 끊겨 어절이 갈라진다.
      expect(
        _keepsWordsWhole(sentence, plain),
        isFalse,
        reason: '이것이 거짓이면 애초에 고칠 문제가 없었다는 뜻이다',
      );

      // 수정 후 — 끊기는 자리가 띄어쓰기로만 제한된다.
      expect(_keepsWordsWhole(sentence, kept), isTrue);
    });

    test('폭이 달라져도 어절 단위가 유지된다', () {
      const String sentence = '무료 플랜은 10개까지 보관할 수 있어, 이번 기프티콘은 저장하지 않았어요.';

      for (final double width in <double>[110, 160, 220, 300]) {
        final List<String> kept = _layoutLines(keepAllKo(sentence), width);
        expect(
          _keepsWordsWhole(sentence, kept),
          isTrue,
          reason: '폭 ${width}px에서 어절이 갈라졌다',
        );
      }
    });
  });
}
