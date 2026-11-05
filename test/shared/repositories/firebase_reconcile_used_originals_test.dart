/// 원본 사후 보정(`reconcileUsedOriginals`)의 **Firestore 고유 경로** — 잠금 문서를
/// 믿지 않는가, 항목 읽기 거부를 건너뛰는가.
///
/// ## 왜 이 테스트가 있는가
///
/// Firestore 구현은 원본의 공유 항목을 `shareLocks/{gifticonId}`의 `sharedGifticonId`로
/// 찾는다. 지금 규칙은 잠금을 항목과 짝이 맞게만 쓰게 하지만, 좁혀지기 전에는 로그인한
/// 누구나 쓸 수 있어 위조된 값이 남아 있을 수 있다. 그 포인터를 믿고 판정하면, 남이 잠금 하나를
/// 고쳐 소유자의 **다른** used 항목을 가리키게 하는 것만으로 멀쩡한 원본이 사용 완료가
/// 된다. 판정은 읽어 온 항목 자체(`gifticonId`·`sharedByUserId`)로 해야 한다.
///
/// ## 공유 계약 스위트에 올리지 않는 이유
///
/// 잠금 문서는 in-memory 구현에 없는 Firestore 고유의 경로다. 그리고 fake에는 규칙이
/// 없어 항목 읽기 거부가 저절로 일어나지 않으므로 `mock_exceptions`로 주입한다
/// (`firebase_mark_used_cross_member_test.dart`와 같은 이유). 어긋남 자체를 **실패
/// 주입으로** 만드는 경로는 공유 계약 스위트(`runUsedOriginalReconcileContract`)가
/// 두 구현에 함께 고정한다 — 여기서는 공유 항목을 `used`로 직접 옮겨 그 상태만 만든다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_share_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late InMemoryAuthRepository auth;
  late FirebaseGifticonRepository gifticons;
  late FirebaseShareRepository repo;
  late Group group;

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = InMemoryAuthRepository();
    // 원본과 공유가 **같은 Firestore**다 — 실서비스 조립과 같다.
    gifticons = FirebaseGifticonRepository(firestore: db);
    repo = FirebaseShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      firestore: db,
    );
    await auth.signUp(
      email: 'reconcile-owner@keepcon.test',
      password: 'keepcon',
      displayName: '소유자',
    );
    group = await repo.createGroup(name: '보정', emoji: '🧾', maxMembers: 5);
  });

  tearDown(() => auth.dispose());

  /// 원본을 저장하고 공유한다.
  Future<(Gifticon, SharedGifticon)> shareNew(String productName) async {
    final Gifticon g = await gifticons.addGifticon(Gifticon(
      id: '',
      ownerId: auth.currentUser!.id,
      brand: '스타벅스',
      productName: productName,
      price: 4500,
      category: '카페',
      expiryDate: DateTime(2030, 1, 1),
      registeredAt: DateTime(2025, 1, 1),
    ));
    return (g, await repo.shareGifticon(groupId: group.id, gifticon: g));
  }

  DocumentReference<Map<String, dynamic>> sharedRef(SharedGifticon s) =>
      db.doc('${FirebaseShareRepository.sharedCollection}/${s.id}');

  DocumentReference<Map<String, dynamic>> lockRef(Gifticon g) =>
      db.doc('${FirebaseShareRepository.shareLocksCollection}/${g.id}');

  /// 원본 동기화가 실패한 뒤의 상태 — 공유 항목만 `used`, 원본은 `available`.
  Future<void> leaveDrifted(SharedGifticon s) =>
      sharedRef(s).update(<String, dynamic>{'status': ShareStatus.used.name});

  Future<GifticonStatus?> statusOf(Gifticon g) async =>
      (await gifticons.getGifticonById(g.id))?.status;

  test('잠금 문서가 가리키는 항목으로 어긋난 원본을 맞춘다', () async {
    final (Gifticon a, SharedGifticon sa) = await shareNew('아메리카노 T');
    await leaveDrifted(sa);

    expect(await repo.reconcileUsedOriginals(), 1);
    expect(await statusOf(a), GifticonStatus.used);
  });

  test('위조된 잠금이 내 다른 used 항목을 가리켜도 멀쩡한 원본을 바꾸지 않는다', () async {
    // A는 공유 중(available), B는 정상적으로 사용 완료됐다(원본도 used).
    final (Gifticon a, _) = await shareNew('공유 중인 것');
    final (Gifticon b, SharedGifticon sb) = await shareNew('이미 쓴 것');
    await repo.markUsed(sb.id);
    expect(await statusOf(b), GifticonStatus.used);

    // 규칙이 좁혀지기 전에 위조된 잠금처럼 B의 used 항목으로 돌려 놓는다. 그 항목은 **소유자가
    // 공유한 used 항목**이라 공유자·상태 검사만으로는 통과한다 — 원본 id 대조만이
    // 이 위조를 거른다.
    await lockRef(a).set(<String, dynamic>{
      'sharedGifticonId': sb.id,
      'groupId': group.id,
    });

    expect(await repo.reconcileUsedOriginals(), 0);
    expect(await statusOf(a), GifticonStatus.available,
        reason: '위조된 포인터를 믿으면 쓰지도 않은 기프티콘이 목록에서 사라진다');
  });

  test('항목 읽기가 거부되면(그룹을 떠남) 그 원본만 건너뛰고 나머지는 맞춘다', () async {
    final (Gifticon a, SharedGifticon sa) = await shareNew('읽기 거부');
    final (Gifticon b, SharedGifticon sb) = await shareNew('정상');
    await leaveDrifted(sa);
    await leaveDrifted(sb);
    whenCalling(Invocation.method(#get, null)).on(sharedRef(sa)).thenThrow(
          FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied'),
        );

    expect(await repo.reconcileUsedOriginals(), 1,
        reason: '원본 하나의 실패가 전체 보정을 멈추면 안 된다');
    expect(await statusOf(a), GifticonStatus.available);
    expect(await statusOf(b), GifticonStatus.used);
  });

  test('잠금이 없으면 건너뛴다 — 포인터 삭제는 보정을 막을 뿐 원본을 바꾸지 못한다', () async {
    final (Gifticon a, SharedGifticon sa) = await shareNew('잠금 삭제');
    await leaveDrifted(sa);
    await lockRef(a).delete();

    expect(await repo.reconcileUsedOriginals(), 0);
    expect(await statusOf(a), GifticonStatus.available);
  });
}
