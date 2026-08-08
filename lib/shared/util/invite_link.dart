/// KeepCon 공유 계약 — 초대 링크 파싱 유틸.
///
/// `Group.inviteUrl`(`https://keepcon.app/invite/<code>`)과 쿼리형(`?invite=<code>`)에서
/// 초대코드를 **역으로** 추출한다. 초대 링크로 앱에 진입했을 때(딥링크) 참여 흐름을 자동
/// 연결하는 데 쓴다. 순수 함수라 플랫폼·위젯 의존 없이 단위 테스트할 수 있다.
library;

/// [uri]에서 초대코드를 추출한다. 초대 링크가 아니면 `null`.
///
/// 지원 형태:
///  - 경로: `.../invite/<code>` (예: `https://keepcon.app/invite/482913`)
///  - 쿼리: `...?invite=<code>`
///
/// 코드는 앞뒤 공백을 제거해 반환하며, 빈 값은 `null`로 취급한다.
/// 쿼리형이 경로형보다 우선한다.
String? parseInviteCode(Uri uri) {
  final String? query = uri.queryParameters['invite'];
  if (query != null && query.trim().isNotEmpty) return query.trim();

  final List<String> segments = uri.pathSegments;
  final int idx = segments.indexOf('invite');
  if (idx >= 0 && idx + 1 < segments.length) {
    final String code = segments[idx + 1].trim();
    if (code.isNotEmpty) return code;
  }
  return null;
}

// `pendingInviteCodeFromPlatform()`은 제거됐다 — 진입 URL에서 목적지를 뽑는 일은
// `shared/deeplink/deep_link_parser.dart`의 `destinationFromPlatformUrl()`이 맡는다.
// 초대는 이제 여러 목적지 중 하나이고, 진입 URL 해석을 두 곳에 두면 새 목적지를
// 추가할 때 한쪽만 고쳐 갈라진다.
