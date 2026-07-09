/// share 페이지 — 한글 조사 자동 선택 유틸 (프로토타입).
///
/// 알림·스낵바 등 동적으로 조립하는 문구에서 `을(를)` 같은 fallback 표기 대신
/// 앞 단어의 받침 유무로 조사를 골라 자연스러운 한국어를 만든다.
///
/// 판별: 마지막 글자가 한글 음절(가~힣)이면 `(코드 - 0xAC00) % 28 != 0`일 때 받침 있음.
/// 한글이 아닌 문자(영문·숫자·기호)로 끝나면 발음 관례가 제각각이라 **받침 없음**으로
/// 간주한다(예: "아메리카노 T" → "T를"). 정밀한 영문/숫자 발음 처리는 계약 이관 시
/// 공용 util로 승격하며 확장한다.
library;

/// [word] 뒤에 붙일 조사를 고른다. 받침이 있으면 [withBatchim], 없으면 [withoutBatchim].
String josa(String word, String withBatchim, String withoutBatchim) {
  if (word.isEmpty) return withoutBatchim;
  final int code = word.codeUnitAt(word.length - 1);
  // 한글 음절 영역(가~힣) 밖이면 받침 없음으로 간주.
  if (code < 0xAC00 || code > 0xD7A3) return withoutBatchim;
  final bool hasBatchim = (code - 0xAC00) % 28 != 0;
  return hasBatchim ? withBatchim : withoutBatchim;
}

/// 문자열 뒤 조사를 편하게 붙이는 확장.
///
/// ```dart
/// '아메리카노 T'.eulReul // '를'  → "아메리카노 T를"
/// '금액권'.eulReul       // '을'  → "금액권을"
/// ```
extension KoreanJosa on String {
  /// 목적격 조사 을/를.
  String get eulReul => josa(this, '을', '를');

  /// 주격 조사 이/가.
  String get iGa => josa(this, '이', '가');

  /// 보조사 은/는.
  String get eunNeun => josa(this, '은', '는');

  /// 접속 조사 와/과. (을/를과 반대 — 받침 있으면 '과', 없으면 '와')
  String get waGwa => josa(this, '과', '와');
}
