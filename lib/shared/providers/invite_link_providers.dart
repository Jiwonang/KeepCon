/// KeepCon 공유 계약 — 초대 링크의 **origin**(스킴 + 호스트 + 포트) SSOT.
///
/// 왜 모델이 아니라 provider인가:
///   [Group]은 순수 모델이라 "지금 어느 백엔드에 붙어 있는지"를 알 수 없다. 그런데 초대
///   링크가 걸릴 도메인은 백엔드마다 다르다 — prod 링크를 에뮬레이터에서 띄우면 **남의
///   실서비스 그룹으로 데려간다.** 그래서 origin은 조립부(main)가 정해 주입하고, 화면은
///   provider로 소비한다(계약 규약: 공유 DI provider는 `lib/shared/providers/` 정본).
///
/// `null`이면 **이 실행에서는 공유 가능한 초대 링크가 없다**는 뜻이다. 화면은 링크 UI를
/// 감추고 그 사실을 알려야 한다(없는 링크를 그럴듯하게 만들어 주면, 눌렀을 때 엉뚱한
/// 백엔드로 가거나 조용히 아무 일도 안 일어난다).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase/firebase_bootstrap.dart' show FirebaseTarget;

/// 현재 실행의 초대 링크 origin. `null`이면 링크를 만들 수 없다.
///
/// 기본값은 웹의 진입 origin이고, Firebase 조립부가 [inviteOriginFor]로 덮어쓴다.
/// 데모(in-memory) 실행은 덮어쓰지 않으므로 이 기본값이 그대로 쓰인다.
final Provider<String?> inviteOriginProvider =
    Provider<String?>((Ref ref) => kIsWeb ? Uri.base.origin : null);

/// [target]에 붙은 실행에서 쓸 초대 링크 origin.
///
/// **웹은 대상과 무관하게 진입 origin을 쓴다.** 앱이 서빙된 그 자리가 곧 링크가 가리켜야
/// 할 자리이기 때문이다 — 에뮬레이터(`http://localhost:5000`)·dev·prod가 한 규칙으로
/// 풀린다. 호스트를 대상별로 하드코딩하면 로컬에서 띄운 앱의 링크가 배포 도메인을
/// 가리키게 된다.
///
/// **안드로이드는 App Links라 도메인이 빌드 시점에 고정된다.** `AndroidManifest.xml`의
/// 인텐트 필터에 적힌 host만 앱으로 오고, 그 도메인이
/// `/.well-known/assetlinks.json`으로 서명을 검증해 줘야 한다. 그래서:
///
///   - prod·dev — 각 Firebase Hosting 도메인. 매니페스트에 **둘 다** 등록돼 있어야 한다.
///   - emulator — **`null`.** 로컬 에뮬레이터에는 그 파일을 서빙할 도메인이 없고,
///     AVD는 호스트에 `10.0.2.2`로만 닿아 검증 대상 도메인이 될 수 없다. 여기서 dev나
///     prod 도메인을 빌려 쓰면 **링크를 누른 사람이 다른 백엔드의 그룹에 참여 요청**을
///     보내게 된다(에뮬레이터 데이터는 그 기기 안에만 있으므로 애초에 공유 대상이 아니다).
///     이 조합에서 링크 시연이 필요하면 **웹으로** 한다.
String? inviteOriginFor(FirebaseTarget target) {
  if (kIsWeb) return Uri.base.origin;
  return switch (target) {
    FirebaseTarget.prod => 'https://keepcon-ab660.web.app',
    FirebaseTarget.dev => 'https://keepcon-dev.web.app',
    FirebaseTarget.emulator => null,
  };
}
