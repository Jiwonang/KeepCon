/// KeepCon 공유 계약 — 딥링크 URI → [AppDestination] 파싱(순수 함수, SSOT).
///
/// 앱으로 들어오는 링크는 경로가 셋이고 **전부 이 함수 하나를 지난다**:
/// - 웹: 진입 URL([Uri.base])
/// - 안드로이드: App Links 인텐트(`app_links` 스트림)
/// - 앱이 이미 떠 있을 때 도착한 링크(같은 스트림)
///
/// 경로마다 따로 파싱하면 "웹에서는 되는데 앱에서는 안 되는" 형태로 갈라진다 — 실제로
/// 승격 전에는 `Uri.base` 경로만 있어서 **안드로이드에서는 초대 링크가 아예 동작하지
/// 않았다**(플랫폼 수신부가 없었다).
library;

import '../util/invite_link.dart';
import 'app_destination.dart';

/// [uri]가 가리키는 앱 내 목적지. 앱이 다룰 링크가 아니면 `null`.
///
/// ## 호스트를 검사하지 않는 이유
/// 어느 도메인에서 왔는지는 **안드로이드 인텐트 필터가 이미 걸러 준다**(App Links는
/// 매니페스트에 적힌 host만 앱으로 온다). 여기서 호스트를 또 검사하면 로컬 웹 실행
/// (`localhost:*`)과 Firebase Hosting 미리보기 채널(`*--preview-*.web.app`) 링크가
/// 조용히 무시된다 — 개발 중에 가장 자주 쓰는 두 경로다.
///
/// 지원 형태(`parseInviteCode` 규약을 그대로 따른다):
/// - 경로: `.../invite/<code>`
/// - 쿼리: `...?invite=<code>`
AppDestination? parseDeepLink(Uri uri) {
  final String? code = parseInviteCode(uri);
  if (code != null) return InviteDestination(code);
  return null;
}

/// 현재 플랫폼의 진입 URL([Uri.base])에서 목적지를 뽑는다.
///
/// **웹 전용 경로다.** 웹에서 초대 링크로 앱을 열면 [Uri.base]에 경로/쿼리가 실려 있다.
/// 안드로이드에서 [Uri.base]는 앱의 작업 디렉터리라 초대 링크와 무관하며, 그쪽은
/// `app_links`가 인텐트에서 직접 받아 온다(`app/deep_link_listener.dart`).
AppDestination? destinationFromPlatformUrl() => parseDeepLink(Uri.base);
