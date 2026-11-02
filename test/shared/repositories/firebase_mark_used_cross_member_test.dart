/// 다른 멤버의 사용 완료 — **원본 읽기 거부**를 받았을 때 원본을 used로 맞추는가.
///
/// ## 왜 이 테스트가 있는가
///
/// `gifticons` 읽기 규칙은 소유자만 허용한다. 그래서 소유자가 아닌 멤버가 `markUsed`를
/// 하면 원본 동기화의 첫 읽기가 permission-denied로 죽고, 예전 구현은 그것을 삼킨 채
/// 건너뛰었다 — 소유자의 개인 목록에 이미 쓴 기프티콘이 '보유중'으로 남았다.
/// 지금은 그 거부를 받으면 규칙이 멤버에게 연 유일한 쓰기(`status` + 근거
/// `usedViaShareId`)로 원본을 맞춘다(`firestore.rules`의 `isSharedUseSync`).
///
/// ## 공유 계약 스위트에 올리지 않는 이유
///
/// fake에는 규칙이 없어 거부가 절대 일어나지 않는다 — 스위트에서는 멤버도 원본을 그냥
/// 읽어 버려 이 분기를 밟지 않는다. `mock_exceptions`로 거부를 주입해 실제로 밟게 한다
/// (`firebase_join_request_first_read_test.dart`와 같은 이유). 규칙이 그 쓰기를 실제로
/// 허용·거부하는지는 `tool/verify_firestore_rules.sh`가 정본이다.
library;

import 'dart:convert';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_share_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';

/// 특정 문서의 `update`만 **영영 미완료** Future로 돌려주는 래퍼 — 서버 ack가 오지 않는
/// 단절을 흉내 낸다(`firebase_join_request_write_timeout_test.dart`와 같은 seam).
/// 나머지는 안쪽 fake로 위임하고, 이 테스트가 안 쓰는 멤버는 [noSuchMethod]로 막는다.
class _HangingUpdateFirestore implements FirebaseFirestore {
  _HangingUpdateFirestore(this._inner, this._hangDocPath);

  final FakeFirebaseFirestore _inner;
  final String _hangDocPath;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _HangingUpdateCollection(_inner.collection(collectionPath), this);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) =>
      _inner.runTransaction(transactionHandler,
          timeout: timeout, maxAttempts: maxAttempts);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '이 테스트 더블이 지원하지 않는 멤버: ${invocation.memberName}');
}

// sealed 플러그인 타입의 구현은 이 더블의 존재 이유다(write_timeout 테스트와 같은 사유).
// ignore: subtype_of_sealed_class
class _HangingUpdateCollection
    implements CollectionReference<Map<String, dynamic>> {
  _HangingUpdateCollection(this._inner, this._db);

  final CollectionReference<Map<String, dynamic>> _inner;
  final _HangingUpdateFirestore _db;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final DocumentReference<Map<String, dynamic>> ref = _inner.doc(path);
    return ref.path == _db._hangDocPath ? _HangingUpdateDoc(ref) : ref;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '이 테스트 더블이 지원하지 않는 멤버: ${invocation.memberName}');
}

// ignore: subtype_of_sealed_class
class _HangingUpdateDoc implements DocumentReference<Map<String, dynamic>> {
  _HangingUpdateDoc(this._inner);

  final DocumentReference<Map<String, dynamic>> _inner;

  @override
  String get id => _inner.id;

  @override
  Future<void> update(Map<Object, Object?> data) =>
      Completer<void>().future; // 서버 ack가 영영 오지 않는 쓰기

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '이 테스트 더블이 지원하지 않는 멤버: ${invocation.memberName}');
}

void main() {
  const String password = 'keepcon';
  const String ownerEmail = 'cross-owner@keepcon.test';
  const String memberEmail = 'cross-member@keepcon.test';

  late FakeFirebaseFirestore db;
  late InMemoryAuthRepository auth;
  late FirebaseGifticonRepository gifticons;
  late FirebaseShareRepository repo;

  late Gifticon original;
  late SharedGifticon item;

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = InMemoryAuthRepository();
    // 원본과 공유가 **같은 Firestore**여야 한다 — 실서비스 조립과 같고, 거부 분기의
    // 직접 쓰기가 그 전제 위에 서 있다.
    gifticons = FirebaseGifticonRepository(firestore: db);
    repo = FirebaseShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      firestore: db,
    );

    final User ownerUser = await auth.signUp(
      email: ownerEmail,
      password: password,
      displayName: '소유자',
    );
    final Group group =
        await repo.createGroup(name: '교차 사용', emoji: '🎁', maxMembers: 5);
    original = await gifticons.addGifticon(Gifticon(
      id: '',
      ownerId: ownerUser.id,
      brand: '스타벅스',
      productName: '아메리카노 T',
      price: 4500,
      category: '카페',
      expiryDate: DateTime(2030, 1, 1),
      registeredAt: DateTime(2025, 1, 1),
    ));
    item = await repo.shareGifticon(groupId: group.id, gifticon: original);

    // 승인 흐름을 그대로 타서 두 번째 멤버를 넣는다.
    await auth.signUp(
      email: memberEmail,
      password: password,
      displayName: '다른 멤버',
    );
    final JoinRequest req = await repo.requestToJoin(group.inviteToken);
    await auth.signIn(email: ownerEmail, password: password);
    await repo.approveJoinRequest(req.id);
  });

  tearDown(() {
    // stub 레지스트리는 전역이지만 (firestore, path)로 매칭되므로 테스트마다 새로
    // 만드는 fake에는 지난 stub이 걸리지 않는다.
    auth.dispose();
  });

  DocumentReference<Map<String, dynamic>> originalRef() =>
      db.doc('${FirebaseGifticonRepository.collectionName}/${original.id}');

  /// 원본 읽기에 보안 규칙의 거부(또는 다른 실패)를 주입한다 — 멤버 세션의 실서비스 모양.
  void denyOriginalReadWith(String code) {
    whenCalling(Invocation.method(#get, null)).on(originalRef()).thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: code),
        );
  }

  /// 저장된 원본 문서. stub이 걸린 참조의 `get`을 피해 덤프로 읽는다 — 검증 수단이
  /// 검증 대상의 stub에 맞아 죽지 않게(first_read 테스트의 같은 주석 참조).
  Map<String, dynamic> storedOriginal() {
    final Map<String, dynamic> all =
        jsonDecode(db.dump()) as Map<String, dynamic>;
    final Map<String, dynamic> col =
        all[FirebaseGifticonRepository.collectionName] as Map<String, dynamic>;
    return col[original.id] as Map<String, dynamic>;
  }

  test('원본 읽기가 거부되면 status와 근거 공유 항목 id만 써서 원본을 맞춘다', () async {
    await auth.signIn(email: memberEmail, password: password);
    denyOriginalReadWith('permission-denied');

    final SharedGifticon used = await repo.markUsed(item.id);

    expect(used.status, ShareStatus.used);
    final Map<String, dynamic> stored = storedOriginal();
    expect(stored['status'], GifticonStatus.used.name);
    expect(stored[FirebaseGifticonRepository.usedViaShareIdField], item.id,
        reason: '규칙은 이 포인터로 공유 항목을 찾아 허용 여부를 판정한다 — 없으면 거부된다');
    expect(stored['ownerId'], original.ownerId, reason: '두 필드 외에는 건드리지 않는다');
  });

  test('다른 실패(unavailable)는 멤버 쓰기로 넘어가지 않는다 — 사용 완료는 유효', () async {
    await auth.signIn(email: memberEmail, password: password);
    denyOriginalReadWith('unavailable');

    final SharedGifticon used = await repo.markUsed(item.id);

    expect(used.status, ShareStatus.used,
        reason: '원본 동기화는 best-effort — 실패해도 공유분 사용 완료는 남는다');
    final Map<String, dynamic> stored = storedOriginal();
    expect(stored['status'], GifticonStatus.available.name);
    expect(stored.containsKey(FirebaseGifticonRepository.usedViaShareIdField),
        isFalse,
        reason: '권한 거부만이 "소유자가 아니다"의 신호다');
  });

  test('소유자 본인의 사용 완료는 기존 경로 그대로 — 포인터를 남기지 않는다', () async {
    final SharedGifticon used = await repo.markUsed(item.id);

    expect(used.status, ShareStatus.used);
    expect((await gifticons.getGifticonById(original.id))?.status,
        GifticonStatus.used);
    expect(
        storedOriginal()
            .containsKey(FirebaseGifticonRepository.usedViaShareIdField),
        isFalse);
  });

  test('멤버 쓰기가 매달려도 주입한 상한이 끊는다 — markUsed는 돌아온다', () async {
    // `.timeout(_writeTimeout)`을 지우면 이 테스트는 아래 Timeout으로 죽는다.
    final FirebaseShareRepository hanging = FirebaseShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      firestore: _HangingUpdateFirestore(db, originalRef().path),
      writeTimeout: const Duration(milliseconds: 120),
    );
    await auth.signIn(email: memberEmail, password: password);
    denyOriginalReadWith('permission-denied');

    final Stopwatch watch = Stopwatch()..start();
    final SharedGifticon used = await hanging.markUsed(item.id);
    watch.stop();

    expect(used.status, ShareStatus.used,
        reason: '시간 초과는 best-effort 동기화가 삼킨다 — 사용 완료 자체는 유효');
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)),
        reason: '상한이 주입값이 아니라 하드코딩으로 발화했다(seam 우회 회귀)');
  }, timeout: const Timeout(Duration(seconds: 10)));
}
