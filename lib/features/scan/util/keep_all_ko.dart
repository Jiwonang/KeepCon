import 'package:flutter/widgets.dart';

/// WORD JOINER(U+2060) — 폭 0, 앞뒤 줄바꿈을 금지하는 문자.
/// 소스에서 눈에 보이지 않으므로 raw 문자가 아니라 이스케이프로 적는다.
const String _wordJoiner = '\u2060';

/// 한글 어절이 줄 끝에서 갈라지지 않게 만든다.
///
/// 유니코드 줄바꿈 규칙(UAX #14)에서 한글 음절은 **서로 사이 어디서나** 끊을 수
/// 있다. 그래서 폭이 좁아지면 '자리가 납 / 니다.'나 '이 / 번 기프티콘은'처럼
/// 어절 한가운데가 갈라진다 — 폭에 따라 갈라지는 자리가 달라지므로 화면 크기마다
/// 문단 모양이 제각각이 된다.
///
/// CSS의 `word-break: keep-all`에 해당하는 속성이 Flutter에는 없으므로, 어절
/// 내부 글자 사이에 [_wordJoiner]를 끼워 **띄어쓰기에서만** 끊기게 만든다.
///
/// 왜 줄바꿈 문자를 손으로 넣어 끊지 않는가 — 그 방식은 특정 폭을 가정한다. 넓은
/// 화면에서는 문장이 이유 없이 일찍 끊기고, 더 좁은 화면에서는 여전히 어절이
/// 갈라진다. 이 함수는 **끊는 자리를 고정하지 않고 끊어도 되는 자리만 제한**하므로
/// 폭이 바뀌어도 어절 단위 정렬이 유지된다.
///
/// 쪼개는 단위는 **자소 클러스터**([Characters])다. 코드 포인트(`runes`)로
/// 쪼개면 눈에 하나로 보이는 글자가 여러 원소로 갈라져, 그 사이에 [_wordJoiner]가
/// 끼면서 글자가 깨진다 — 이모지 뒤의 variation selector가 분리돼 컬러 이모지가
/// 흑백으로 바뀌거나(`☕️`), ZWJ로 이어진 가족·국기 이모지가 낱개로 흩어진다.
/// 지금 호출부는 전부 한글 리터럴이라 드러나지 않지만, 사용자가 입력한 브랜드·
/// 상품명에 쓰는 순간 터진다.
///
/// ⚠️ 두 가지 제약:
/// - 어절 하나가 줄 폭보다 길면 끊을 곳이 없어 넘친다. 긴 URL·식별자에는 쓰지 않는다.
/// - 반환 문자열은 원문과 **같지 않다**(보이지 않는 문자가 섞인다). `find.text()`로
///   검증하는 문구에는 쓰지 않는다 — 그 검증이 조용히 깨진다.
String keepAllKo(String text) => text
    .split(' ')
    .map((String word) => word.characters.join(_wordJoiner))
    .join(' ');

/// 어절 보호를 적용한 [Text] — **표시는 보호본, 낭독·탐색은 원문.**
///
/// [keepAllKo]가 심는 [_wordJoiner]는 눈에 보이지 않지만 문자열에는 남는다.
/// 그대로 [Text]에 넣으면 그 문자열이 접근성 라벨로도 쓰여, 스크린 리더에 원문과
/// 다른 값이 전달되고 `find.text()`·`find.bySemanticsLabel()`로도 찾지 못한다.
/// [Text.semanticsLabel]이 정확히 이 분리를 위해 존재한다.
///
/// 호출부마다 `Text(keepAllKo('…'), semanticsLabel: '…')`로 적으면 **같은 문구가
/// 두 번 등장해** 하나만 고쳐지는 순간 화면과 낭독이 갈라진다(그리고 그것을 잡아
/// 줄 것이 없다). 이 위젯은 문구를 한 번만 받아 둘 다 만든다.
class KeepAllText extends StatelessWidget {
  const KeepAllText(this.data, {super.key, this.style, this.textAlign});

  /// 원문. 표시할 때만 [keepAllKo]를 통과한다.
  final String data;

  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
        keepAllKo(data),
        semanticsLabel: data,
        style: style,
        textAlign: textAlign,
      );
}
