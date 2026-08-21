// `inviteOriginFor` — 초대 링크가 어느 도메인을 가리키는지 정하는 표.
//
// 이 표가 틀리면 링크는 **에러 없이** 브라우저로 새거나(미검증 도메인) 남의 백엔드로
// 간다. 실제로 이 저장소는 prod 호스트 하나로 박아 두어, 에뮬레이터·dev에서 띄운 앱이
// 실서비스 도메인 링크를 발급하고 있었다.
//
// 이 파일이 생긴 이유: `inviteOriginFor`는 SSOT 계약 함수 중 **유일하게 테스트가 0건**
// 이었는데, 정작 한 PR 안에서 동작이 두 번 뒤집혔다(`kIsWeb` 제거 → 되살림). `analyze`·
// `SSOT guard`·`Firestore rules` 어느 것도 이 표를 보지 않는다.
//
// ⚠️ **emulator + 웹 갈래는 여기서 검증되지 않는다.** VM 테스트에서 `kIsWeb`은 컴파일
//    타임 `false`라 `FirebaseTarget.emulator`는 항상 `null`로 떨어진다. 그 갈래를 고정하려면
//    `flutter test --platform chrome`이 필요하고 이 저장소는 그것을 돌리지 않는다 —
//    못 박는다는 사실을 적어 둔다(없는 커버리지를 있는 것처럼 두지 않는다).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/firebase/firebase_bootstrap.dart';
import 'package:keepcon/shared/providers/invite_link_providers.dart';
import 'package:keepcon/shared/util/invite_link.dart';

void main() {
  test('백엔드별 origin 표가 고정돼 있다', () {
    expect(inviteOriginFor(FirebaseTarget.dev), 'https://keepcon-dev.web.app');
    expect(
      inviteOriginFor(FirebaseTarget.prod),
      'https://keepcon-ab660.web.app',
    );
    // VM(= 안드로이드 갈래)에서는 null — 화면이 `_NoInviteLinkNotice`를 띄우는 조건이다.
    expect(inviteOriginFor(FirebaseTarget.emulator), isNull);
  });

  test('링크를 발급하는 도메인은 매니페스트의 App Links 필터에도 있어야 한다', () {
    // 둘이 갈라지면 링크는 만들어지는데 앱으로 오지 않는다 — App Links 검증 실패는
    // 오류를 내지 않으므로 조용히 브라우저로 샌다.
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for (final FirebaseTarget t in <FirebaseTarget>[
      FirebaseTarget.dev,
      FirebaseTarget.prod,
    ]) {
      final String host = Uri.parse(inviteOriginFor(t)!).host;
      expect(manifest, contains('android:host="$host"'), reason: '$t');
    }
  });

  test('발급하는 origin은 전부 다른 기기에서 열리는 주소다', () {
    // emulator 갈래(웹에서 localhost)는 예외이고, 그 사실을 화면이 알려야 한다 —
    // 판정은 `isSharableOrigin`이 갖는다.
    for (final FirebaseTarget t in <FirebaseTarget>[
      FirebaseTarget.dev,
      FirebaseTarget.prod,
    ]) {
      expect(isSharableOrigin(inviteOriginFor(t)!), isTrue, reason: '$t');
    }
  });

  group('isSharableOrigin', () {
    test('로컬 개발 서버 주소는 공유 불가로 본다', () {
      for (final String o in <String>[
        'http://localhost:8083',
        'http://127.0.0.1:5000',
        'http://app.localhost:3000',
      ]) {
        expect(isSharableOrigin(o), isFalse, reason: o);
      }
    });

    test('배포 도메인은 공유 가능', () {
      expect(isSharableOrigin('https://keepcon-dev.web.app'), isTrue);
      expect(isSharableOrigin('https://keepcon-ab660.web.app'), isTrue);
    });

    test('파싱할 수 없는 값은 공유 불가로 닫는다', () {
      // 모를 때는 "공유하세요"라고 말하지 않는 쪽으로 닫는다.
      expect(isSharableOrigin(''), isFalse);
      expect(isSharableOrigin('not a url'), isFalse);
    });
  });
}
