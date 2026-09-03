/// 첫 참여 요청 — **없는 요청 문서의 읽기 거부**를 "아직 없음"으로 해석하는가.
///
/// ## 왜 이 테스트가 있는가 (2026-09-03 dev 실측)
///
/// `joinRequests` 읽기 규칙은 `resource.data`를 참조하므로 **없는 문서에서는 평가가
/// 오류(=거부)로 죽는다** — 존재 오라클을 막으려고 의도적으로 남긴 403이고,
/// `tool/verify_firestore_rules.sh`의 "없는 요청 문서 조회 → 403"이 그 규약을 못박는다.
/// 그런데 `requestToJoin`이 멱등성 확인을 **트랜잭션 안의 읽기**로 하고 있어서, 첫
/// 요청자(문서가 아직 없는)의 요청이 규칙 있는 백엔드(dev·에뮬레이터)에서 **항상**
/// permission-denied로 죽었다. 세 검증 계층이 전부 이 교차점을 비껴갔다 — Dart 테스트는
/// 규칙이 없고(fake), 규칙 검증은 REST로 읽기 없이 바로 생성하며, dev에는 규칙 자체가
/// 배포돼 있지 않았다.
///
/// ## 공유 계약 스위트에 올리지 않는 이유
///
/// 계약 스위트 머리말 4가 명시한 그 사각지대다 — fake에는 규칙이 없어 거부가 절대
/// 일어나지 않으므로, 흡수 분기를 지워도 스위트는 초록이다. 여기서는
/// `mock_exceptions`로 **거부를 주입해** 그 분기를 실제로 밟게 한다. in-memory 구현에는
/// 규칙도 거부도 없으니 계약이 아니라 firebase 고유 행위이고, 그래서 전용 파일이다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_share_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late FirebaseShareRepository repo;

  /// 방장이 만든 그룹 — 게스트가 이 그룹의 링크 토큰으로 요청한다.
  /// (읽기 거부는 자격증명 종류와 무관하다 — 코드든 링크든 같은 요청 문서를 읽는다.)
  late Group group;
  late User guest;

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    repo = FirebaseShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      firestore: db,
    );
    await auth.signUp(
      email: 'owner@keepcon.test',
      password: 'keepcon',
      displayName: '방장',
    );
    group = await repo.createGroup(name: '첫요청', emoji: '📮');
    // 요청의 행위자는 정의상 비멤버다.
    guest = await auth.signUp(
      email: 'guest@keepcon.test',
      password: 'keepcon',
      displayName: '손님',
    );
  });

  tearDown(() {
    // `mock_exceptions`의 stub 레지스트리는 전역이지만 여기서 비울 필요가 없다 —
    // 참조 매칭이 (firestore, path) 동등성이라, 테스트마다 새로 만드는
    // `FakeFirebaseFirestore`에는 지난 테스트의 stub이 걸릴 수 없다.
    gifticons.dispose();
    auth.dispose();
  });

  /// 게스트의 요청 문서 경로.
  String requestPath() =>
      '${FirebaseShareRepository.joinRequestsCollection}/${group.id}_${guest.id}';

  /// 게스트의 요청 문서 참조 — 저장소 내부가 만드는 것과 (firestore, path)로 같다.
  /// id 조립은 [requestPath] 한 곳에만 둔다 — 두 벌이면 규약이 바뀔 때 stub이
  /// 실제 코드가 읽는 문서와 다른 참조에 걸린다.
  DocumentReference<Map<String, dynamic>> requestRef() => db.doc(requestPath());

  /// 그 참조의 `get`에 보안 규칙의 거부를 주입한다.
  void denyReadWith(String code) {
    whenCalling(Invocation.method(#get, null)).on(requestRef()).thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: code),
        );
  }

  test('요청 문서 읽기가 permission-denied여도 첫 요청은 생성된다', () async {
    denyReadWith('permission-denied');

    final JoinRequest req = await repo.requestToJoin(group.inviteToken);

    expect(req.groupId, group.id);
    expect(req.userId, guest.id);
    expect(req.isPending, isTrue);
    // 문서 존재는 쿼리가 아니라 `hasSavedDocument`로 확인한다 — fake의 쿼리 `get()`은
    // 컬렉션의 **문서 참조마다** `doc.get()`을 다시 부르므로(stub이 거기에도 걸린다),
    // 쿼리로 확인하면 검증 수단이 검증 대상의 stub에 맞아 죽는다(실측).
    expect(db.hasSavedDocument(requestPath()), isTrue);
    expect(db.dump(), contains('"status": "pending"'));
  });

  test('다른 실패(unavailable)는 "없음"으로 읽지 않고 그대로 던진다', () async {
    // 네트워크 실패를 흡수하면 살아 있는 대기 요청을 새 문서로 덮어써
    // `requestedAt`이 초기화된다 — 거부만 없음의 신호다.
    denyReadWith('unavailable');

    await expectLater(
      repo.requestToJoin(group.inviteToken),
      throwsA(isA<FirebaseException>()),
    );
    expect(db.hasSavedDocument(requestPath()), isFalse);
  });

  test('멤버십 판정 읽기의 일시적 실패는 "비멤버"로 오판하지 않는다', () async {
    // 이미 멤버(방장)가 자기 그룹 링크를 눌렀는데 그룹 문서 읽기가 일시적으로
    // 실패하면, 그 실패를 흡수하는 순간 "비멤버"로 오판돼 자기 그룹에 참여 요청을
    // 만들러 내려간다 — 멤버십 catch를 권한 거부로만 좁힌 경계가 지키는 것이
    // 이것이다(위 두 테스트는 요청 문서 쪽 stub만 걸어 이 분기를 밟지 않는다).
    await auth.signIn(email: 'owner@keepcon.test', password: 'keepcon');
    whenCalling(Invocation.method(#get, null))
        .on(db.doc('${FirebaseShareRepository.groupsCollection}/${group.id}'))
        .thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        );

    await expectLater(
      repo.requestToJoin(group.inviteToken),
      throwsA(isA<FirebaseException>()),
    );
    expect(
      db.hasSavedDocument(
        '${FirebaseShareRepository.joinRequestsCollection}/'
        '${group.id}_${group.owner.userId}',
      ),
      isFalse,
    );
  });
}
