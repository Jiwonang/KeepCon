// ShareRepository 알림 읽음 상태(watchNotificationsReadAt / markNotificationsRead) 테스트.
//
// 계약:
// - watchNotificationsReadAt: 한 번도 안 읽었으면 null, 읽으면 마지막 읽음 시각을 방출.
// - markNotificationsRead: 현재 사용자의 마지막 읽음 시각을 현재로 갱신(세션 없으면 StateError).
// - 안읽음 판정: createdAt이 readAt 이후인 알림. mark 후엔 기존 알림이 모두 읽음이 된다.
//
// 행위자 = InMemoryAuthRepository.defaultUser(id 'user-1').

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

void main() {
  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late InMemoryShareRepository repo;

  final String me = InMemoryAuthRepository.defaultUser.id; // 'user-1'

  setUp(() {
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    repo = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
    );
  });

  tearDown(() {
    repo.dispose();
    gifticons.dispose();
    auth.dispose();
  });

  test('처음엔 읽음 시각이 null(전부 안읽음)', () async {
    final DateTime? readAt = await repo.watchNotificationsReadAt(me).first;
    expect(readAt, isNull);
    // 시드 알림이 존재해 안읽음이 있다.
    expect((await repo.getNotifications(me)), isNotEmpty);
  });

  test('markNotificationsRead 후 읽음 시각이 갱신되고 기존 알림은 모두 읽음', () async {
    final DateTime before = DateTime.now();
    await repo.markNotificationsRead();

    final DateTime? readAt = await repo.watchNotificationsReadAt(me).first;
    expect(readAt, isNotNull);
    expect(readAt!.isBefore(before), isFalse); // now 이상.

    // 기존(시드) 알림은 모두 readAt 이전에 생성됨 → 안읽음 0.
    final List<GroupNotification> notifs = await repo.getNotifications(me);
    final int unread = notifs
        .where((GroupNotification n) => n.createdAt.isAfter(readAt))
        .length;
    expect(unread, 0);
  });

  test('미로그인 상태에서 markNotificationsRead는 StateError', () async {
    await auth.signOut();
    await expectLater(repo.markNotificationsRead(), throwsStateError);
  });
}
