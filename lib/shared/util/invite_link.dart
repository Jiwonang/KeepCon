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

/// 현재 플랫폼의 진입 URL([Uri.base])에서 대기 중 초대코드를 추출한다.
///
/// 웹에서 초대 링크로 앱을 열면 [Uri.base]에 경로/쿼리가 실려 있어 코드를 얻는다.
/// 진입 URL이 초대 링크가 아니면(대부분의 일반 실행) `null`.
String? pendingInviteCodeFromPlatform() => parseInviteCode(Uri.base);
