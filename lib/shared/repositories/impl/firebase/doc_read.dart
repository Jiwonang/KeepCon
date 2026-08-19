/// Firestore 문서 필드 읽기 — **타입 안전** 리더.
///
/// `data['brand'] as String?` 같은 캐스팅은 필드 타입이 어긋나면 [TypeError]를 던진다.
/// 그런데 [TypeError]는 [Exception]이 아니라 **[Error]** 라서 두 겹으로 샌다:
///
/// - 계약이 "가드 위반은 [StateError]"로 규정한 그물에 안 걸린다.
/// - 목록 매핑(`snap.docs.map(_fromDoc)`)에서 터지면 **문서 하나가 사용자의 목록 스트림
///   전체를 죽인다** — 손상된 문서 한 건 때문에 화면이 통째로 비거나 에러가 된다.
///
/// 그래서 읽기는 캐스팅이 아니라 `is` 검사로 통일하고, 손상 값은 예외가 아니라 **기본값**
/// 으로 흡수한다. 이 파일이 그 단일 정본이며 같은 폴더의 Firestore 리포지토리 셋
/// (`FirebaseShareRepository`·`FirebaseGifticonRepository`·`FirebaseAuthRepository`)이
/// 함께 소비한다 — 한쪽만 방어되면 다음 사람이 어느 쪽이 정본인지 알 수 없다.
///
/// **폴백 방향은 호출부가 정한다.** 값이 없는 것(레거시 문서)과 값이 손상된 것은 다른
/// 사건이므로, 방향이 갈리는 [docBool]은 둘을 따로 받는다.
///
/// ⚠️ 이 관용은 **읽기 경로 전용**이다. 쓰기 트랜잭션이 같은 매퍼를 쓰면 폴백이 곧 판정이
/// 되어 불변식이 뚫린다 — 쓰기용 매퍼는 관대 매퍼의 결과가 아니라 **원본 문서**를 다시 보고
/// 필수 필드를 검증해야 한다(`FirebaseShareRepository.requireSharedFromData` 참조).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// 문서 필드 → [String]. 문자열이 아니면(없음 포함) [fallback].
String docString(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

/// 문서 필드 → [String]?. 문자열이 아니면 `null`(= 값 없음).
String? docStringOrNull(Object? value) => value is String ? value : null;

/// 문서 필드 → [bool].
///
/// 값이 **없으면** [ifAbsent], 값은 있는데 **타입이 어긋나면** [ifCorrupt]를 쓴다. 둘을
/// 나누는 이유: 레거시 문서의 결측은 "그 필드가 생기기 전에 만들어졌다"는 뜻이라 기본
/// 정책을 따라야 하지만, 손상은 원래 값이 무엇이었는지 알 수 없으므로 **안전한 쪽으로
/// 닫아야** 한다. 한 값으로 뭉치면 잠가 둔 정책이 손상 하나로 조용히 풀린다.
bool docBool(Object? value, {required bool ifAbsent, required bool ifCorrupt}) {
  if (value is bool) return value;
  return value == null ? ifAbsent : ifCorrupt;
}

/// 문서 필드 → 리스트. 리스트가 아니면 `null` — 호출부가 "필드 없음(레거시)"과
/// "손상 값"을 같게 다룰 수 있게 한다.
List<dynamic>? docListOrNull(Object? value) =>
    value is List<dynamic> ? value : null;

/// 문서 필드 → [int]. 정수로 **정확히** 읽을 수 없으면 `null`.
///
/// [int]는 그대로 통과시키고, [double]은 두 관문을 통과해야 한다:
///
/// 1. **유한할 것.** [num.toInt]는 `NaN`·`±Infinity`에 [UnsupportedError]를 던진다 —
///    이 역시 [Error]라 캐스팅과 똑같이 목록 스트림을 죽인다. Firestore는 IEEE 754 double을
///    그대로 저장하므로 `NaN`이 문서에 실제로 들어올 수 있다.
/// 2. **정수로 정확히 표현되는 범위(±2^53)일 것.** `1e300`은 유한하지만 `toInt()`가 int64
///    최대값으로 **포화**한다. 그 값이 정원 같은 필드에 들어가면 `isFull`이 영원히 false가
///    되어 가드가 통째로 사라진다. 포화는 "큰 수"가 아니라 **읽기 실패**이므로, 정책 상한을
///    씌워 값을 조이는 대신 여기서 `null`(= 기본값 사용)로 떨어뜨린다 — 상한은 계약이 정할
///    일이지 리더가 정할 일이 아니다.
int? docInt(Object? value) {
  if (value is int) return value;
  if (value is! double || !value.isFinite) return null;
  // 2^53 — 이보다 크면 double이 정수를 정확히 담지 못해 toInt()가 포화·반올림된다.
  const double exactIntLimit = 9007199254740992.0;
  return value.abs() <= exactIntLimit ? value.toInt() : null;
}

/// 문서 필드 → [DateTime]. [Timestamp]·[DateTime]이 아니면 epoch.
///
/// epoch는 "아주 오래된 시각"이라 만료·정렬 판정에서 **닫히는 쪽**으로 떨어진다.
DateTime docDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

/// 문서 필드 → [DateTime]?. [Timestamp]·[DateTime]이 아니면 `null`.
DateTime? docDateOrNull(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

/// 문서 id로 쓸 수 있는 값인가.
///
/// Firestore의 `doc('')`은 [ArgumentError]를 던진다(`A document path must be a non-empty
/// string`). 손상 문서에서 뽑은 빈 id를 그대로 넘기면 참조를 만드는 순간 터져, 그 문서를
/// 포함한 **일괄 삭제·트랜잭션 전체가 영구히 실패**한다(재시도해도 문서가 그대로다).
bool isUsableDocId(String? value) => value != null && value.isNotEmpty;
