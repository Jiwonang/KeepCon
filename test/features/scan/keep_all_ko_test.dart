import 'dart:ui' as ui;

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

/// [text]를 [maxWidth]로 접었을 때 **가장 긴 줄의 실제 폭**.
///
/// 엔진이 내놓는 줄 메트릭을 그대로 읽는다. 위 [_layoutLines]로 나눈 줄을 다시
/// 재는 방식으로는 안 된다 — `getLineBoundary`는 **끊어도 되는 자리**를 기준으로
/// 순회하므로, 엔진이 어절 한가운데를 강제로 끊은 자리는 재현되지 않는다. 그러면
/// 긴 토큰이 한 줄로 돌아와 넘친 것처럼 보인다(이 함수를 그렇게 짰다가 정반대
/// 결론을 낼 뻔했다).
double _widestLine(String text, double maxWidth) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: 14)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);

  double widest = 0;
  for (final ui.LineMetrics metrics in painter.computeLineMetrics()) {
    if (metrics.width > widest) widest = metrics.width;
  }

  painter.dispose();
  return widest;
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

    test('눈에 하나로 보이는 글자를 쪼개지 않는다', () {
      // 코드 포인트(`runes`)로 쪼개면 여기서 글자가 깨진다 — 이모지와 뒤따르는
      // variation selector 사이, ZWJ로 이어진 조각 사이에 WORD JOINER가 끼기
      // 때문이다. 화면에는 흑백 이모지나 흩어진 낱개 글자로 나타난다.
      const String vs16 = '☕️'; // U+2615 + U+FE0F
      const String family = '👨‍👩‍👧'; // ZWJ 시퀀스
      const String flag = '🇰🇷'; // 지역 표시 기호 쌍

      for (final String glyph in <String>[vs16, family, flag]) {
        expect(
          keepAllKo(glyph),
          glyph,
          reason: '자소 클러스터 안에 WORD JOINER가 끼었다',
        );
      }

      // 어절 경계는 그대로 살아 있어야 한다 — 클러스터를 지키느라 본래 목적을
      // 잃으면 안 된다.
      expect(
        keepAllKo('$vs16 아메리카노'),
        '$vs16 ${<String>['아', '메', '리', '카', '노'].join(_wordJoiner)}',
      );
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

    test('줄보다 긴 어절도 넘치지 않는다 — 엔진이 강제로 끊는다', () {
      // 이 함수의 dartdoc은 오랫동안 "끊을 곳이 없어 넘친다"고 적어 두었고,
      // PR #123이 그 문장을 근거로 원시 예외를 품는 문구에는 어절 보호를 걸 수
      // 없다고 판단했다가 실측에서 뒤집혔다. 서술로만 남겨 두면 다시 갈라지므로
      // 재어서 못박는다 — 이 테스트가 그 dartdoc의 근거다.
      //
      // 표본은 실제로 사용자에게 나갈 수 있는 모양이다(Firestore 예외 + 인덱스
      // 생성 URL). 공백이 없는 토큰이 줄 폭보다 훨씬 길다.
      const String withLongToken =
          '저장에 실패했습니다: [cloud_firestore/failed-precondition] '
          'https://console.firebase.google.com/v1/r/project/keepcon-dev/firestore/indexes?create_composite=ClFwcm9qZWN0cy9rZWVwY29u';

      // 40px는 어떤 기기보다도 좁다 — 여기서도 안 넘치면 실제 폭에서는 안전하다.
      // 272px는 320dp 기기의 스낵바 콘텐츠 폭이다.
      for (final double width in <double>[40, 80, 272, 320]) {
        expect(
          _widestLine(keepAllKo(withLongToken), width),
          lessThanOrEqualTo(width),
          reason: '폭 ${width}px에서 넘쳤다',
        );
      }
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
