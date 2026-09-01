/// 공유 계약 스위트를 **두 구현에 모두** 돌린다.
///
/// 이 파일이 하는 일은 백엔드를 갈아 끼우는 것뿐이다 — 기대는 전부
/// `share_repository_contract_suite.dart`에 있고, 그래야 한쪽만 고쳐도 다른 쪽이
/// 시끄럽게 실패한다. **기대를 여기에 쓰지 마라**(쓰는 순간 두 구현이 다른 계약을
/// 검증하게 되고, 이 파일의 존재 이유가 사라진다).
///
/// 경계(fake가 대체하지 못하는 것 셋)는 스위트 파일의 머리말이 정본이다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_share_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

import 'share_repository_contract_suite.dart';

/// in-memory 구현 어댑터.
class _InMemoryBackend implements ShareBackend {
  /// ⚠️ **자원을 전부 생성 시점에 만든다.** 별도 `start()` 단계를 두면 그것이 중간에
  ///    죽었을 때 `tearDown`의 [stop]이 아직 초기화되지 않은 필드를 만져
  ///    `LateInitializationError`를 던지고, **그 오류가 진짜 원인을 가린다.**
  ///    생성이 곧 준비이면 그 상태 자체가 존재하지 않는다.
  _InMemoryBackend() {
    // `now:`가 `this`의 필드를 읽으므로 필드 초기화식에는 둘 수 없다.
    _repo = InMemoryShareRepository(
      authRepository: _auth,
      gifticonRepository: _gifticons,
      now: () => _clock,
    );
  }

  final InMemoryAuthRepository _auth = InMemoryAuthRepository();
  final InMemoryGifticonRepository _gifticons = InMemoryGifticonRepository();

  /// 저장소가 '지금'이라고 믿는 시각.
  ///
  /// **고정 시각이 아니라 실제 현재 시각에서 출발한다.** 주입 시계의 범위는 만료
  /// *판정*으로 좁혀져 있어서 그룹 생성 시 `Group.inviteExpiresAt`는 여전히 실제
  /// `DateTime.now()` 기준으로 찍힌다. 임의의 고정 시각을 쓰면 두 기준이 어긋나
  /// "링크가 만료됐다"가 실행 날짜에 따라 달라진다.
  DateTime _clock = DateTime.now();

  late final InMemoryShareRepository _repo;

  @override
  void stop() {
    _repo.dispose();
    _gifticons.dispose();
    _auth.dispose();
  }

  @override
  ShareRepository get repo => _repo;

  @override
  AuthRepository get auth => _auth;

  @override
  Future<void> passTime(Duration d) async => _clock = _clock.add(d);

  @override
  Future<Group> seedGroupWithLinkToken(String token) async {
    // 계약에 토큰을 지정하는 API가 없고 in-memory에는 백도어도 없다 — 대신 **데모
    // 시드**가 6자리 토큰 그룹을 갖고 있다(이 구현의 실제 데이터 모양이다).
    final List<Group> seeded =
        await _repo.getGroups(InMemoryAuthRepository.defaultUser.id);
    return seeded.firstWhere(
      (Group g) => g.inviteToken == token,
      orElse: () => throw StateError(
        '시드에 링크 토큰이 `$token`인 그룹이 없다 — 이 픽스처의 전제가 사라졌다. '
        '시드를 바꿨다면 이 값도 함께 옮겨라.',
      ),
    );
  }
}

/// firebase 구현 어댑터 — 인메모리 Firestore(`fake_cloud_firestore`) 위에서 돈다.
class _FirebaseBackend implements ShareBackend {
  // 인증은 프로젝트 자체 인터페이스(`AuthRepository`)로 주입된다 — `firebase_auth`가
  // 아니라서 목이 필요 없다. 이 저장소가 firebase에 의존하는 부분은 Firestore뿐이다.
  final InMemoryAuthRepository _auth = InMemoryAuthRepository();
  final InMemoryGifticonRepository _gifticons = InMemoryGifticonRepository();
  final FakeFirebaseFirestore _db = FakeFirebaseFirestore();

  // 생성 시점에 준비된다(위 in-memory 어댑터의 ⚠️와 같은 이유).
  late final FirebaseShareRepository _repo = FirebaseShareRepository(
    authRepository: _auth,
    gifticonRepository: _gifticons,
    firestore: _db,
  );

  @override
  void stop() {
    // `FirebaseShareRepository`에는 `dispose`가 없다(스트림을 자체 보관하지 않는다).
    _gifticons.dispose();
    _auth.dispose();
  }

  @override
  ShareRepository get repo => _repo;

  @override
  AuthRepository get auth => _auth;

  @override
  Future<void> passTime(Duration d) async {
    // 이 구현은 `DateTime.now()`를 직접 읽으므로 시계를 밀 수 없다 — 대신 **저장된
    // 만료 시각을 그만큼 당긴다.** 관측되는 만료 여부는 같다(스위트 머리말 참조).
    //
    // 세 곳을 모두 당긴다: 그룹 문서의 두 정본과 조회 문서 둘. `requestToJoin`이 보는
    // 것은 조회 문서지만, 한 곳만 당기면 그룹과 조회 문서의 만료가 어긋나 **현실에
    // 없는 상태**를 만들고 그 위에서 통과한 테스트는 아무것도 보증하지 않는다.
    Timestamp? shift(Object? v) =>
        v is Timestamp ? Timestamp.fromDate(v.toDate().subtract(d)) : null;

    Future<void> shiftAll(
      CollectionReference<Map<String, dynamic>> col,
      List<String> fields,
    ) async {
      final QuerySnapshot<Map<String, dynamic>> snap = await col.get();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
        final Map<String, dynamic> patch = <String, dynamic>{};
        for (final String f in fields) {
          final Timestamp? moved = shift(doc.data()[f]);
          if (moved != null) patch[f] = moved;
        }
        if (patch.isNotEmpty) await doc.reference.update(patch);
      }
    }

    await shiftAll(
      _db.collection(FirebaseShareRepository.groupsCollection),
      <String>['inviteExpiresAt', 'shortInviteCodeExpiresAt'],
    );
    await shiftAll(
      _db.collection(FirebaseShareRepository.inviteTokensCollection),
      <String>['expiresAt'],
    );
    await shiftAll(
      _db.collection(FirebaseShareRepository.inviteCodesCollection),
      <String>['expiresAt'],
    );
  }

  @override
  Future<Group> seedGroupWithLinkToken(String token) async {
    // 레거시 문서를 **문서로** 심는다 — 계약에는 토큰을 고르는 API가 없고, 있으면
    // 안 된다(토큰은 저장소가 정한다).
    //
    // ⚠️ `_groupToDoc`이 **실제로 쓰는 키만** 심는다. 생산이 쓰지 않는 필드를 더하면
    //    현실에 없는 문서 모양을 검증하게 되고, 그만큼 이 스위트의 보증이 거짓이 된다.
    final DocumentReference<Map<String, dynamic>> ref =
        _db.collection(FirebaseShareRepository.groupsCollection).doc();
    // 방장은 합성 id다. 스위트가 요구하는 것은 "게스트가 멤버가 아닐 것"뿐이라
    // 실제 세션 사용자일 필요가 없다.
    const String ownerId = 'legacy-owner';
    final DateTime expiresAt = DateTime.now().add(Group.inviteValidity);
    await ref.set(<String, dynamic>{
      'name': '레거시 그룹',
      'emoji': '🕰️',
      'inviteToken': token,
      'inviteOwnerOnly': false,
      'inviteExpiresAt': Timestamp.fromDate(expiresAt),
      'maxMembers': 5,
      'members': <Map<String, dynamic>>[
        <String, dynamic>{
          'userId': ownerId,
          'displayName': '레거시 방장',
          'avatarEmoji': '🙂',
          'role': MemberRole.owner.name,
        },
      ],
      'memberIds': <String>[ownerId],
      'ownerId': ownerId,
    });
    // 비멤버는 규칙상 `groups`를 못 읽으므로 그룹으로 가는 다리는 조회 문서뿐이다 —
    // 레거시 그룹에도 그것이 있어야 링크가 열린다.
    await _db
        .collection(FirebaseShareRepository.inviteTokensCollection)
        .doc(token)
        .set(<String, dynamic>{
      'groupId': ref.id,
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    final Group? seeded = await _repo.getGroupById(ref.id);
    if (seeded == null) {
      throw StateError('심은 레거시 그룹을 매퍼가 읽지 못했다 — 문서 모양이 바뀌었다');
    }
    return seeded;
  }
}

void main() {
  // 라벨과 팩토리를 한 자리에 둔다 — 라벨을 읽으려고 백엔드를 미리 만들면 그 인스턴스가
  // 자원을 쥔 채 버려진다(생성이 곧 준비이므로).
  final Map<String, ShareBackend Function()> backends =
      <String, ShareBackend Function()>{
    'in-memory': _InMemoryBackend.new,
    'firebase(fake)': _FirebaseBackend.new,
  };

  backends.forEach((String label, ShareBackend Function() make) {
    group('[$label] requestToJoin — 자격증명 해석·만료', () {
      runCredentialResolutionContract(make);
    });
  });
}
