/// 참여 요청 **쓰기 상한** — `requestToJoin`의 `set`과 `cancelJoinRequest`의
/// `delete`에 걸린 타임아웃이 실제로 발화하는가.
///
/// ## 왜 이 테스트가 있는가
///
/// 두 상한이 지키는 것은 "읽기 성공 뒤 단절 → 쓰기 Future가 서버 ack까지 영영
/// 미완료 → 화면 `_busy`가 catch에서만 풀리는 구조상 버튼 영구 잠김"이다
/// (flutterfire #17643). 그런데 PR #162 리뷰의 뮤테이션 실측 — **상한을 지워도
/// 저장소 테스트가 전부 통과**했다. 상한이 무보호였다.
///
/// ## 왜 seam(주입 상한 + 미완료 래퍼)인가
///
/// fake 위에서는 지연을 주입할 수 없다 — `mock_exceptions`는 예외만 던진다.
/// scan의 선례(`_NameLookupHangingShareRepository`)는 실시간 5초를 그대로
/// 기다렸지만("가짜 시계가 저장소 스트림에 닿지 않는다" — 그 파일 머리말),
/// 여기는 15초×2라 실시간이 감당이 안 된다. 그래서 ①특정 문서의 쓰기만 영영
/// 미완료 Future를 돌려주는 Firestore 래퍼와 ②생성자 주입 상한
/// (`FirebaseShareRepository.writeTimeout`)을 짝으로 쓴다.
///
/// ## 뮤테이션 의미론
///
/// - `.timeout(_writeTimeout)`을 지우면 → 쓰기가 영영 미완료라 이 테스트는
///   **프레임워크 타임아웃으로 죽는다**(scan 선례와 같은 존재 이유).
/// - seam을 우회해 15초를 다시 하드코딩하면 → 발화는 하지만 아래 "5초 안"
///   단언이 red다(주입한 상한은 밀리초 단위다).
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_share_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

/// 특정 문서 경로의 `set`·`delete`만 **영영 미완료** Future로 돌려주는 래퍼.
///
/// 읽기(`get`)는 안쪽 fake로 위임한다 — 상한이 감싸는 것은 쓰기뿐이고, 사전
/// 확인 읽기는 실제로 성공해야 쓰기 지점까지 내려간다. 이 테스트가 쓰지 않는
/// 멤버는 [noSuchMethod]로 막아 둔다(부르면 소리 나게 죽는다 — 조용한 오동작
/// 방지).
class _HangingWriteFirestore implements FirebaseFirestore {
  _HangingWriteFirestore(this._inner, this._hangDocPath);

  final FakeFirebaseFirestore _inner;
  final String _hangDocPath;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _HangingWriteCollection(_inner.collection(collectionPath), this);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '이 테스트 더블이 지원하지 않는 멤버: ${invocation.memberName}');
}

class _HangingWriteCollection
    implements CollectionReference<Map<String, dynamic>> {
  _HangingWriteCollection(this._inner, this._db);

  final CollectionReference<Map<String, dynamic>> _inner;
  final _HangingWriteFirestore _db;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final DocumentReference<Map<String, dynamic>> ref = _inner.doc(path);
    return ref.path == _db._hangDocPath ? _HangingWriteDoc(ref) : ref;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '이 테스트 더블이 지원하지 않는 멤버: ${invocation.memberName}');
}

class _HangingWriteDoc implements DocumentReference<Map<String, dynamic>> {
  _HangingWriteDoc(this._inner);

  final DocumentReference<Map<String, dynamic>> _inner;

  @override
  String get id => _inner.id;

  @override
  String get path => _inner.path;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      _inner.get(options);

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      Completer<void>().future; // 서버 ack가 영영 오지 않는 쓰기

  @override
  Future<void> delete() => Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '이 테스트 더블이 지원하지 않는 멤버: ${invocation.memberName}');
}

void main() {
  late FakeFirebaseFirestore db;
  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;

  /// 셋업 전용 — 래퍼 없이 진짜 fake 위에서 그룹·요청을 만든다.
  late FirebaseShareRepository plainRepo;

  const String ownerEmail = 'owner@keepcon.test';
  const String password = 'keepcon';

  late Group targetGroup;
  late User guest;

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    plainRepo = FirebaseShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      firestore: db,
    );
    await auth.signUp(
      email: ownerEmail,
      password: password,
      displayName: '방장',
    );
    targetGroup = await plainRepo.createGroup(name: '상한', emoji: '⏱️');
    guest = await auth.signUp(
      email: 'guest@keepcon.test',
      password: password,
      displayName: '손님',
    );
  });

  tearDown(() {
    gifticons.dispose();
    auth.dispose();
  });

  String requestPath() =>
      '${FirebaseShareRepository.joinRequestsCollection}/${targetGroup.id}_${guest.id}';

  /// 요청 문서의 쓰기만 매달리는 저장소 — 상한은 밀리초로 주입한다.
  FirebaseShareRepository hangingRepo() => FirebaseShareRepository(
        authRepository: auth,
        gifticonRepository: gifticons,
        firestore: _HangingWriteFirestore(db, requestPath()),
        writeTimeout: const Duration(milliseconds: 120),
      );

  /// 상한 발화를 시간까지 물어서 단언한다 — "5초 안"은 seam 우회(15초 재하드코딩)
  /// 회귀를 잡기 위한 넉넉한 경계다(주입값 120ms의 40배, 기본값 15초의 1/3).
  Future<void> expectTimesOutQuickly(Future<Object?> Function() action) async {
    final Stopwatch watch = Stopwatch()..start();
    await expectLater(action(), throwsA(isA<TimeoutException>()));
    watch.stop();
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)),
        reason: '상한이 주입값이 아니라 하드코딩으로 발화했다(seam 우회 회귀)');
  }

  test('requestToJoin — 쓰기가 매달리면 주입한 상한이 끊는다', () async {
    // 게스트가 현재 사용자. 사전 확인(문서 없음)은 실제 fake로 통과하고,
    // 요청 문서 set만 영영 미완료다.
    await expectTimesOutQuickly(
        () => hangingRepo().requestToJoin(targetGroup.inviteToken));
  });

  test('cancelJoinRequest — 삭제가 매달리면 주입한 상한이 끊는다', () async {
    // 진짜 fake로 대기 요청을 만들어 두고(존재 확인이 통과해야 delete까지
    // 내려간다), 그 문서의 delete만 매달리게 한다.
    await plainRepo.requestToJoin(targetGroup.inviteToken);

    await expectTimesOutQuickly(
        () => hangingRepo().cancelJoinRequest('${targetGroup.id}_${guest.id}'));
  });
}
