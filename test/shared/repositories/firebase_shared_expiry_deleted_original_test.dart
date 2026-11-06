/// 원본을 지운 공유 항목의 연장 — Firebase 구현의 permission-denied 번역 회귀.
///
/// 삭제 API(`GifticonRepository.deleteGifticon`, v3.19)가 생기기 전에는 공유 항목의
/// 원본이 사라질 길이 없었다. 이제는 화면 가드(공유 중이면 삭제 막기)를 경합으로
/// 비껴간 원본 없는 공유 항목이 남을 수 있다. 그 항목을 연장하면 `extendSharedExpiry`가
/// **스냅샷보다 먼저** 원본을 읽는데, 규칙 있는 Firestore에서 없는 원본 읽기는 `null`이
/// 아니라 permission-denied다(`gifticons` 읽기 규칙이 `resource.data`를 참조한다).
/// 번역이 없으면 연장 전체가 실패해 **스냅샷마저 옮길 길이 사라진다.**
///
/// 공유 계약 스위트는 이 계층을 못 본다 — `fake_cloud_firestore`는 규칙을 평가하지 않아
/// 없는 문서를 `null`로 돌려주므로 두 구현 모두 이미 건너뛴다. 그래서 거부를 주입해
/// 실서버의 모양을 재현한다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_share_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late InMemoryAuthRepository auth;
  late FirebaseGifticonRepository gifticons;
  late FirebaseShareRepository repo;

  late Gifticon original;
  late SharedGifticon item;

  final DateTime newExpiry = DateTime(2031, 6, 30);

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = InMemoryAuthRepository();
    // 실서비스 조립과 같게 원본과 공유를 같은 Firestore에 둔다.
    gifticons = FirebaseGifticonRepository(firestore: db);
    repo = FirebaseShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      firestore: db,
    );

    final User owner = await auth.signUp(
      email: 'deleted-original@keepcon.test',
      password: 'keepcon',
      displayName: '공유자',
    );
    final Group group = await repo.createGroup(name: '원본 삭제', emoji: '🗑');
    original = await gifticons.addGifticon(Gifticon(
      id: '',
      ownerId: owner.id,
      brand: '스타벅스',
      productName: '아메리카노 T',
      price: 4500,
      category: '카페',
      expiryDate: DateTime(2030, 1, 1),
      registeredAt: DateTime(2025, 1, 1),
    ));
    item = await repo.shareGifticon(groupId: group.id, gifticon: original);

    // 화면 가드를 비껴간 삭제(경합)를 재현한다.
    await gifticons.deleteGifticon(original.id);
  });

  tearDown(() => auth.dispose());

  /// 원본 문서 읽기에 보안 규칙의 응답을 주입한다(없는 문서 → 평가 오류 → 거부).
  void denyOriginalReadWith(String code) {
    whenCalling(Invocation.method(#get, null))
        .on(db
            .doc('${FirebaseGifticonRepository.collectionName}/${original.id}'))
        .thenThrow(FirebaseException(plugin: 'cloud_firestore', code: code));
  }

  test('원본 읽기가 permission-denied여도 스냅샷은 연장된다', () async {
    denyOriginalReadWith('permission-denied');

    final SharedGifticon updated =
        await repo.extendSharedExpiry(item.id, newExpiry);

    expect(updated.expiryDate, newExpiry);
    final DocumentSnapshot<Map<String, dynamic>> stored = await db
        .doc('${FirebaseShareRepository.sharedCollection}/${item.id}')
        .get();
    expect((stored.data()!['expiryDate'] as Timestamp).toDate(), newExpiry,
        reason: '원본이 없다고 스냅샷까지 못 옮기면 그룹 멤버는 만료된 것으로 본다');
    // 거부를 주입한 참조로 다시 읽으면 단언이 그 stub에 걸린다 — 저장 여부를 직접 본다.
    expect(
        db.hasSavedDocument(
            '${FirebaseGifticonRepository.collectionName}/${original.id}'),
        isFalse,
        reason: '원본 동기화가 지워진 문서를 되살리면 안 된다');
  });

  test('그 밖의 실패는 삼키지 않는다 — 통신 실패는 그대로 올라간다', () async {
    // 번역을 permission-denied 하나로 묶었는지 고정한다. 넓히면 진짜 통신 실패에서
    // 스냅샷만 옮겨지고 원본은 그대로인 어긋남을 조용히 만든다.
    denyOriginalReadWith('unavailable');

    await expectLater(
      repo.extendSharedExpiry(item.id, newExpiry),
      throwsA(isA<FirebaseException>()),
    );
  });
  group('소유자 경로의 읽기 거부를 계약의 StateError로', () {
    // 지운 문서를 다시 지우면(다른 기기가 먼저 지운 경우) 실서버는 트랜잭션 읽기를
    // permission-denied로 거부한다. 번역이 없으면 화면이 "연결을 확인하세요"를 띄워
    // 사용자가 없는 것을 계속 다시 지우려 한다.
    void denyTxReadWith(String code) {
      whenCalling(Invocation.method(#get, <Object?>[null]))
          .on(db.doc(
              '${FirebaseGifticonRepository.collectionName}/${original.id}'))
          .thenThrow(FirebaseException(plugin: 'cloud_firestore', code: code));
    }

    test('permission-denied는 StateError로 번역된다', () async {
      denyTxReadWith('permission-denied');
      await expectLater(
          gifticons.deleteGifticon(original.id), throwsStateError);
    });

    // 형제 경로 — 다른 기기가 지운 뒤 이 기기의 상세가 사용 완료·연장을 거는 경우.
    // 번역이 deleteGifticon에만 있으면 두 메서드는 통신 실패로 안내한다.
    test('updateStatus도 읽기 거부를 StateError로 번역한다', () async {
      denyTxReadWith('permission-denied');
      await expectLater(
          gifticons.updateStatus(original.id, GifticonStatus.used),
          throwsStateError);
    });

    test('extendExpiry도 읽기 거부를 StateError로 번역한다', () async {
      denyTxReadWith('permission-denied');
      await expectLater(
          gifticons.extendExpiry(original.id, DateTime(2032, 1, 1)),
          throwsStateError);
    });

    test('통신 실패는 번역하지 않는다', () async {
      denyTxReadWith('unavailable');
      await expectLater(gifticons.deleteGifticon(original.id),
          throwsA(isA<FirebaseException>()));
    });
  });

  group('deleteGifticon — 공유 잠금과 커밋 거부', () {
    late Gifticon live;

    setUp(() async {
      live = await gifticons.addGifticon(original.copyWith(id: ''));
    });

    // ⚠️ fake에는 낙관적 동시성이 없어 "트랜잭션 **안에서**" 읽는지는 여기서 구분되지
    //    않는다(`lockRef.get()`으로 바꿔도 통과 — 뮤테이션 실측). 공유 생성과의 충돌
    //    자체는 실 SDK·에뮬레이터 영역이다.
    test('삭제는 공유 잠금을 읽는다 — 그 읽기가 실패하면 지우지 않는다', () async {
      whenCalling(Invocation.method(#get, <Object?>[null]))
          .on(db.doc(
              '${FirebaseShareRepository.shareLocksCollection}/${live.id}'))
          .thenThrow(FirebaseException(
              plugin: 'cloud_firestore', code: 'unavailable'));

      await expectLater(
          gifticons.deleteGifticon(live.id), throwsA(isA<FirebaseException>()));
      expect(
          db.hasSavedDocument(
              '${FirebaseGifticonRepository.collectionName}/${live.id}'),
          isTrue);
    });

    test('잠금 문서가 없어도 지워진다 — 공유된 적 없는 기프티콘', () async {
      await gifticons.deleteGifticon(live.id);
      expect(await gifticons.getGifticonById(live.id), isNull);
      expect(await gifticons.getGifticons(live.ownerId), isEmpty);
    });

    const GifticonDetails details = GifticonDetails(
      brand: '투썸',
      productName: '라떼',
      price: 1,
      barcode: null,
      category: '기타',
    );

    test('내용 수정도 공유 잠금을 읽는다 — 그 읽기가 실패하면 고치지 않는다', () async {
      whenCalling(Invocation.method(#get, <Object?>[null]))
          .on(db.doc(
              '${FirebaseShareRepository.shareLocksCollection}/${live.id}'))
          .thenThrow(FirebaseException(
              plugin: 'cloud_firestore', code: 'unavailable'));

      await expectLater(gifticons.updateDetails(live.id, details),
          throwsA(isA<FirebaseException>()));
      expect((await gifticons.getGifticonById(live.id))!.brand, '스타벅스');
    });

    test('내용 수정의 커밋 거부도 GifticonShareBlockedException으로 알린다', () async {
      final FirebaseGifticonRepository rejecting =
          FirebaseGifticonRepository(firestore: _CommitRejectingFirestore(db));

      await expectLater(rejecting.updateDetails(live.id, details),
          throwsA(isA<GifticonShareBlockedException>()));
    });

    test('내용 수정의 읽기 거부는 "없음"이다', () async {
      whenCalling(Invocation.method(#get, <Object?>[null]))
          .on(db.doc('${FirebaseGifticonRepository.collectionName}/${live.id}'))
          .thenThrow(FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied'));

      await expectLater(
        gifticons.updateDetails(live.id, details),
        throwsA(isA<StateError>().having((StateError e) => e, 'type',
            isNot(isA<GifticonShareBlockedException>()))),
      );
    });

    test('커밋의 거부는 GifticonShareBlockedException으로 알린다', () async {
      // 읽기가 통과한 뒤 커밋이 permission-denied면 규칙의 `hasActiveShare`다. '없음'으로
      // 번역하면 화면이 살아 있는 기프티콘의 상세를 닫고, 번역이 없으면 통신 실패로
      // 안내한다 — 어느 쪽이든 사용자가 다음에 할 일이 틀린다.
      //
      // fake의 `tx.delete`는 문서 참조의 `delete`를 거치지 않아 mock_exceptions로 커밋
      // 거부를 주입할 수 없다(실측). 그래서 트랜잭션 본문이 끝난 뒤 거부를 던지는
      // 대역을 쓴다 — 본문의 읽기는 실제로 통과한다.
      final FirebaseGifticonRepository rejecting =
          FirebaseGifticonRepository(firestore: _CommitRejectingFirestore(db));

      await expectLater(rejecting.deleteGifticon(live.id),
          throwsA(isA<GifticonShareBlockedException>()));
    });
  });
}

/// 트랜잭션 본문은 그대로 돌리고, 끝난 뒤 **커밋 단계의 규칙 거부**를 흉내 내는 대역.
/// 본문이 던지지 않고 끝나야 거부가 나므로, 읽기 거부(`_txGetOwned`)와 갈라 볼 수 있다.
class _CommitRejectingFirestore implements FirebaseFirestore {
  _CommitRejectingFirestore(this._inner);

  final FakeFirebaseFirestore _inner;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _inner.collection(collectionPath);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) =>
      _inner.runTransaction<T>((Transaction tx) async {
        await transactionHandler(tx);
        // ⚠️ fake는 본문의 쓰기를 즉시 적용하므로 문서 잔존은 여기서 볼 수 없다 — 이
        //    대역이 고정하는 것은 **예외 번역**뿐이다.
        throw FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied');
      }, timeout: timeout, maxAttempts: maxAttempts);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '이 테스트 더블이 지원하지 않는 멤버: ${invocation.memberName}');
}
