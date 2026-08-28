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
///
/// [_widestLine]과 같은 Ahem 전제 위에 있다(그 dartdoc 참조). 다만 이쪽은 폭이
/// 아니라 줄의 **내용**을 보므로 글자 폭이 결과를 바꾸지 않는다.
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
/// 엔진이 내놓는 줄 메트릭을 그대로 읽는다. [_layoutLines]로 나눈 줄을 **떼어내
/// 다시 재는** 방식으로는 안 된다 — 줄 나눔 자체는 정확하지만(줄 수·내용이 메트릭과
/// 일치한다), 떼어낸 부분문자열에는 **줄 끝 공백이 되살아난다.** 접힌 레이아웃은 그
/// 공백을 줄 상자 밖으로 흘려보내므로(`'AAAAA '` 단독 84px, 같은 줄의 메트릭 70px),
/// 다시 재면 없는 초과분이 생긴다. 폭 80px에서 `'tion] '` 줄이 84로 읽혀 정반대
/// 결론을 낼 뻔했다.
///
/// ⚠️ `flutter test`의 기본 폰트는 모든 글리프가 1em 정사각(Ahem)이다
/// (`'AB'` @14px = 28.0). 그래서 여기서 나오는 수치는 표본과 무관하게
/// `floor(폭 / fontSize) × fontSize`다 — 재는 것은 **엔진의 줄 나눔 동작**이지 실제
/// 폰트의 글자 폭이 아니다. 강제 끊김은 폰트가 아니라 엔진 속성이므로 결론은
/// 실기기에도 옮겨 간다.
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
      // ⚠️ 이것이 고정하는 것은 **엔진 속성**이지 [keepAllKo]가 아니다. 강제
      // 끊김은 원문에도 성립하므로 어절 보호를 빼도 통과한다 — 그래서 아래에서
      // 원문·보호본을 나란히 재고, 요지를 "어절 보호가 이 성질을 깨지 않는다"로
      // 둔다. [keepAllKo] 고유의 성질은 다음 테스트가 본다.
      //
      // 표본은 실제로 사용자에게 나갈 수 있는 모양이다(Firestore 예외 + 인덱스
      // 생성 URL). 공백이 없는 토큰이 줄 폭보다 훨씬 길다.
      const String withLongToken =
          '저장에 실패했습니다: [cloud_firestore/failed-precondition] '
          'https://console.firebase.google.com/v1/r/project/keepcon-dev/firestore/indexes?create_composite=ClFwcm9qZWN0cy9rZWVwY29u';

      // 전제: 가장 긴 토큰이 최대 시험 폭보다 넓어야 '강제로 끊는다'가 시험된다.
      // 이것이 없으면 표본이 짧아지는 순간 이 테스트는 공허하게 초록이 된다
      // (뮤테이션으로 확인 — 표본을 짧게 바꿔도 통과했다).
      final String longestToken = withLongToken
          .split(' ')
          .reduce((String a, String b) => a.length >= b.length ? a : b);

      expect(
        _widestLine(longestToken, double.infinity),
        greaterThan(320),
        reason: '가장 긴 토큰이 시험 폭보다 좁으면 강제 끊김이 일어나지 않는다',
      );

      // 272px는 320dp 기기의 스낵바 콘텐츠 폭, 40px는 그보다 한참 좁은 하한 표본이다.
      //
      // ⚠️ "좁을수록 어렵다"가 아니다 — 엔진은 자소 클러스터 하나보다 좁게 끊지
      // 못하므로 폭 < 14px(=fontSize)에서는 원문도 보호본도 14px를 낸다. 여기서
      // 재는 것은 "글자 하나는 들어가는 폭에서 강제 끊김이 동작한다"까지다.
      // 미확인: textScaler(접근성 글자 확대)를 켜면 그 하한도 함께 올라간다 —
      //         이 테스트는 배율 1.0만 잰다.
      for (final double width in <double>[40, 80, 272, 320]) {
        expect(
          _widestLine(withLongToken, width),
          lessThanOrEqualTo(width),
          reason: '전제: 원문부터 폭 ${width}px에서 넘치지 않아야 한다',
        );
        expect(
          _widestLine(keepAllKo(withLongToken), width),
          lessThanOrEqualTo(width),
          reason: '폭 ${width}px에서 넘쳤다',
        );
      }
    });

    test('긴 URL·식별자에서는 있던 끊김 자리를 잃는다', () {
      // dartdoc이 "걸어도 얻는 것이 없다"에 더해 **잃는 것이 있다**고 적은 근거다.
      // 원문은 UAX #14대로 `/`·`-` 뒤에서 끊기는데, 어절 보호가 그 기회를 없앤다.
      // 앞 테스트와 달리 이것은 [keepAllKo] 고유의 성질이라 함수를 빼면 죽는다
      // (뮤테이션으로 확인).
      const String withUrl =
          '저장에 실패했습니다: [cloud_firestore/failed-precondition] '
          'https://console.firebase.google.com/v1/r/project/keepcon-dev/firestore/indexes';
      const double width = 272; // 320dp 기기의 스낵바 콘텐츠 폭

      final List<String> plain = _layoutLines(withUrl, width);
      final List<String> kept = _layoutLines(keepAllKo(withUrl), width)
          .map((String line) => line.replaceAll(_wordJoiner, ''))
          .toList();

      // 끊는 자리가 실제로 달라진다.
      expect(kept, isNot(equals(plain)));

      // 그리고 그 차이는 **자연스러운 자리를 잃는** 쪽이다. `/`·`-`로 끝나는 줄이
      // 곧 UAX #14가 준 끊김 기회를 쓴 자리다.
      int naturalBreaks(List<String> lines) =>
          lines.where((String l) => l.endsWith('/') || l.endsWith('-')).length;

      expect(
        naturalBreaks(kept),
        lessThan(naturalBreaks(plain)),
        reason: '어절 보호가 URL의 끊김 자리를 없애지 못했다면 dartdoc이 과장이다',
      );
    });

    test('폭이 달라져도 어절 단위가 유지된다', () {
      const String sentence = '무료 플랜은 10개까지 보관할 수 있어, 이번 기프티콘은 저장하지 않았어요.';

      for (final double width in <double>[110, 160, 220, 300]) {
        // 전제: 이 폭에서 실제로 접혀야 어절 보존을 검증하게 된다. 문장이
        // 짧아지면 한 줄에 들어가 공허하게 초록이 된다(형제 테스트가 같은
        // 전제를 못박아 두었는데 여기만 빠져 있었다).
        expect(
          _layoutLines(sentence, width).length,
          greaterThan(1),
          reason: '폭 ${width}px에서 한 줄에 들어가면 줄바꿈 규칙을 검증하지 못한다',
        );

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
