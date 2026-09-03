/// 승인·거절·취소 — **경합으로 이미 지워진 요청 문서**의 읽기 거부를 계약의
/// [StateError]("Join request not found")로 번역하는가.
///
/// ## 왜 이 테스트가 있는가
///
/// `joinRequests` 읽기 규칙은 `resource.data`를 참조하므로 **없는 문서에서는 평가가
/// 오류(=거부)로 죽는다** — 존재 오라클을 막으려고 의도적으로 남긴 403이고,
/// `tool/verify_firestore_rules.sh`의 "없는 요청 문서 조회 → 403"이 그 규약을 못박는다.
/// `requestToJoin`의 "첫 요청" 결함과 같은 뿌리인데, 승인·거절·취소는 문서가 이미
/// 지워진 **경합**(요청자 취소 직후 방장이 승인, 그룹 삭제 캐스케이드 직후 취소)에서만
/// 그 403을 맞는다. 그때 계약이 약속한 [StateError] 대신
/// `FirebaseException(permission-denied)`이 UI까지 올라갔다.
///
/// ## 공유 계약 스위트에 올리지 않는 이유
///
/// 계약 스위트 머리말 4가 명시한 그 사각지대다 — fake에는 규칙이 없어 거부가 절대
/// 일어나지 않으므로, 번역 분기를 지워도 스위트는 초록이다. 여기서는
/// `mock_exceptions`로 **거부를 주입해** 그 분기를 실제로 밟게 한다. in-memory 구현에는
/// 규칙도 거부도 없으니 계약이 아니라 firebase 고유 행위이고, 그래서 전용 파일이다.
/// (`requestToJoin`의 같은 결함은 형제 수정이 같은 구도의 전용 테스트로 덮는다 —
/// 그 수정이 머지되기 전까지 이 저장소의 `requestToJoin`에는 결함이 남아 있다.)
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_share_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late FirebaseShareRepository repo;

  const String ownerEmail = 'owner@keepcon.test';
  const String password = 'keepcon';

  /// 방장이 만든 그룹 — 게스트의 요청 문서 id가 이 그룹에 매인다.
  late Group targetGroup;
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
      email: ownerEmail,
      password: password,
      displayName: '방장',
    );
    targetGroup = await repo.createGroup(name: '경합', emoji: '⚔️');
    // 요청자 — 여기서 요청 문서를 만들지 않는 것이 시나리오의 본질이다:
    // "이미 지워진(=없는) 문서"의 읽기 거부가 주입 대상이다.
    guest = await auth.signUp(
      email: 'guest@keepcon.test',
      password: password,
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

  /// 게스트의 요청 문서 id — 저장소의 `{groupId}_{userId}` 규약.
  String requestId() => '${targetGroup.id}_${guest.id}';

  String requestPath() =>
      '${FirebaseShareRepository.joinRequestsCollection}/${requestId()}';

  /// 그 참조의 `get`에 보안 규칙의 거부를 주입한다. id 조립은 [requestId] 한 곳에만
  /// 둔다 — 두 벌이면 규약이 바뀔 때 stub이 실제 코드가 읽는 문서와 다른 참조에 걸린다.
  void denyReadWith(String code) {
    whenCalling(Invocation.method(#get, null))
        .on(db.doc(requestPath()))
        .thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: code),
        );
  }

  Future<void> signInOwner() async {
    await auth.signIn(email: ownerEmail, password: password);
  }

  /// 계약의 "요청 없음" — 세 메서드가 같은 문장으로 던진다.
  Matcher throwsNotFound() => throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        contains('Join request not found'),
      ));

  /// 권한 거부가 아닌 실패(unavailable)는 "없음"으로 접지 않고 그대로 던진다 —
  /// 흡수하면 일시적 네트워크 문제가 "요청이 사라졌다"는 오진이 된다.
  /// 세 메서드가 같은 규약이므로 단언도 한 벌만 둔다(따로 두면 한쪽만 고쳐져
  /// 나머지 경로의 커버리지가 조용히 약해진다).
  Future<void> expectUnavailablePassesThrough(
      Future<Object?> Function() action) async {
    denyReadWith('unavailable');
    await expectLater(
      action(),
      throwsA(isA<FirebaseException>()
          .having((FirebaseException e) => e.code, 'code', 'unavailable')),
    );
  }

  group('approveJoinRequest', () {
    test('지워진 요청 읽기가 permission-denied면 계약의 StateError로 번역된다', () async {
      await signInOwner();
      denyReadWith('permission-denied');

      await expectLater(
        repo.approveJoinRequest(requestId()),
        throwsNotFound(),
      );
      // 본론(트랜잭션)에 들어가지 않았다 — 승인 흔적(멤버 추가)이 없다.
      expect(db.hasSavedDocument(requestPath()), isFalse);
      final DocumentSnapshot<Map<String, dynamic>> groupDoc =
          await db.doc('groups/${targetGroup.id}').get();
      expect(groupDoc.data()?['memberIds'], isNot(contains(guest.id)));
    });

    test('다른 실패(unavailable)는 "없음"으로 읽지 않고 그대로 던진다', () async {
      await signInOwner();
      await expectUnavailablePassesThrough(
          () => repo.approveJoinRequest(requestId()));
    });
  });

  group('rejectJoinRequest', () {
    test('지워진 요청 읽기가 permission-denied면 계약의 StateError로 번역된다', () async {
      await signInOwner();
      denyReadWith('permission-denied');

      await expectLater(
        repo.rejectJoinRequest(requestId()),
        throwsNotFound(),
      );
      expect(db.hasSavedDocument(requestPath()), isFalse);
    });

    test('다른 실패(unavailable)는 "없음"으로 읽지 않고 그대로 던진다', () async {
      await signInOwner();
      await expectUnavailablePassesThrough(
          () => repo.rejectJoinRequest(requestId()));
    });
  });

  group('cancelJoinRequest', () {
    // 행위자는 요청자 본인(setUp의 마지막 signUp으로 이미 게스트가 현재 사용자다).
    // 그룹 삭제 캐스케이드가 요청을 먼저 지운 직후의 취소가 이 모양이다.
    test('지워진 요청 읽기가 permission-denied면 계약의 StateError로 번역된다', () async {
      denyReadWith('permission-denied');

      await expectLater(
        repo.cancelJoinRequest(requestId()),
        throwsNotFound(),
      );
    });

    test('다른 실패(unavailable)는 "없음"으로 읽지 않고 그대로 던진다', () async {
      await expectUnavailablePassesThrough(
          () => repo.cancelJoinRequest(requestId()));
    });
  });
}
