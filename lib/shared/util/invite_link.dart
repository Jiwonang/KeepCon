/// KeepCon 공유 계약 — 초대 링크 파싱 유틸.
///
/// 초대 링크를 **조립**하고([inviteUrlFrom]), 경로형/쿼리형 링크에서 초대 토큰을
/// **역으로 추출**한다([parseInviteToken]). 초대 링크로 앱에 진입했을 때(딥링크) 참여
/// 흐름을 자동 연결하는 데 쓴다. 순수 함수라 플랫폼·위젯 의존 없이 단위 테스트할 수 있다.
///
/// origin은 여기서 정하지 않는다 — 백엔드마다 다르므로 `inviteOriginProvider`가 정본이다.
library;

/// `<origin>/invite/<token>` 형태의 초대 링크.
///
/// [origin]은 스킴을 포함한 origin이다(`https://keepcon-dev.web.app`,
/// `http://localhost:5000`). 끝의 `/`는 있어도 되게 정리한다 — `Uri.base.origin`은 붙이지
/// 않지만 손으로 넣은 값은 붙어 있을 수 있고, 그대로 두면 `//invite/…`가 되어 경로
/// 세그먼트가 하나 밀린다([parseInviteToken]이 못 찾는다).
String inviteUrlFrom({required String origin, required String inviteToken}) {
  final String base =
      origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
  return '$base/invite/$inviteToken';
}

/// [origin]이 **다른 기기에서도 열리는지**. 로컬 개발 서버 주소는 아니다.
///
/// emulator + 웹은 진입 origin(`http://localhost:<포트>`)을 쓰는데, 그 링크는 발급한 PC
/// 안에서만 통한다. 받은 사람이 누르면 연결 거부이거나, 더 나쁘게는 자기 로컬 앱이 열려
/// "링크가 잘못됐거나 만료됐을 수 있어요"가 뜬다 — 링크는 멀쩡한데 원인을 정반대로 말한다.
///
/// 그 갈래를 없애지 않는 이유는 **웹에서 딥링크를 손으로 확인할 유일한 경로**여서다.
/// 대신 화면이 사실을 적을 수 있도록 판정을 여기 둔다 — 화면이 매직 스트링으로 재구현하면
/// 판정이 두 벌이 된다(계약 규약: 공유 판정은 `lib/shared` 정본).
bool isSharableOrigin(String origin) {
  final String host = Uri.tryParse(origin)?.host ?? '';
  return host.isNotEmpty &&
      host != 'localhost' &&
      host != '127.0.0.1' &&
      host != '::1' &&
      !host.endsWith('.localhost');
}

/// [uri]에서 초대 토큰을 추출한다. 초대 링크가 아니면 `null`.
///
/// 지원 형태:
///  - 경로: `.../invite/<token>` (예: `https://keepcon-dev.web.app/invite/9Xk2…`)
///  - 쿼리: `...?invite=<token>`
///
/// 코드는 앞뒤 공백을 제거해 반환하며, 빈 값은 `null`로 취급한다.
/// 쿼리형이 경로형보다 우선한다.
String? parseInviteToken(Uri uri) {
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

// `pendingInviteTokenFromPlatform()`은 제거됐다 — 진입 URL에서 목적지를 뽑는 일은
// `shared/deeplink/deep_link_parser.dart`의 `destinationFromPlatformUrl()`이 맡는다.
// 초대는 이제 여러 목적지 중 하나이고, 진입 URL 해석을 두 곳에 두면 새 목적지를
// 추가할 때 한쪽만 고쳐 갈라진다.
