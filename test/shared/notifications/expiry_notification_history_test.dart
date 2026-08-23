/// **이미 울린** 만료 임박 알림 복원 테스트([firedExpiryNotifications]).
///
/// 알림 센터는 개인 만료 알림을 저장된 기록이 아니라 **계산으로** 되살린다. 계산이
/// 예약([planExpiryNotifications])과 조금이라도 어긋나면 두 가지로 드러난다 —
/// 사용자가 받은 적 없는 알림이 목록에 뜨거나, 받은 알림이 목록에서 빠진다. 둘 다
/// 실기기에서 며칠 기다려야 보이므로 여기서 경계를 고정한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/models/app_notification.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/notifications/expiry_notification_plan.dart';
import 'package:keepcon/shared/util/expiry_policy.dart';

Gifticon _g({
  required String id,
  required DateTime expiry,
  GifticonStatus status = GifticonStatus.available,
  String brand = '스타벅스',
  String productName = '아메리카노 T',
}) =>
    Gifticon(
      id: id,
      ownerId: 'user-1',
      brand: brand,
      productName: productName,
      category: '카페',
      price: 4500,
      expiryDate: expiry,
      registeredAt: DateTime(2026, 1, 1),
      status: status,
    );

void main() {
  // 8/7 15:30. 발송 시각은 항상 그날 오전 9시라, 오늘 몫은 이미 지나 있다.
  final DateTime now = DateTime(2026, 8, 7, 15, 30);

  group('대상 선별', () {
    test('사용 완료·만료 상태는 복원하지 않는다 — 해결된 알림이다', () {
      final List<ExpiryNotificationItem> fired = firedExpiryNotifications(
        <Gifticon>[
          _g(
              id: 'used',
              expiry: DateTime(2026, 8, 10),
              status: GifticonStatus.used),
          _g(
              id: 'exp',
              expiry: DateTime(2026, 8, 10),
              status: GifticonStatus.expired),
        ],
        now: now,
      );

      expect(fired, isEmpty);
    });

    test('아직 안 울린 것(미래)은 복원하지 않는다 — 예약의 몫이다', () {
      // 만료가 한참 뒤면 D-7조차 아직 미래다.
      final List<ExpiryNotificationItem> fired = firedExpiryNotifications(
        <Gifticon>[_g(id: 'far', expiry: DateTime(2026, 12, 25))],
        now: now,
      );

      expect(fired, isEmpty);
    });
  });

  group('예약과의 여집합 — 한 시점이 양쪽에 들거나 어느 쪽에도 안 들지 않는다', () {
    test('같은 입력에서 예약 + 복원이 격자를 정확히 나눠 갖는다', () {
      final List<Gifticon> gifticons = <Gifticon>[
        _g(
            id: 'g-1',
            expiry: DateTime(2026, 8, 10)), // D-7은 지났고 D-3은 오늘, D-1은 미래
      ];

      final Set<DateTime> planned = planExpiryNotifications(gifticons, now: now)
          .map((ScheduledExpiryNotification n) => n.scheduledAt)
          .toSet();
      final Set<DateTime> fired = firedExpiryNotifications(gifticons, now: now)
          .map((ExpiryNotificationItem n) => n.firedAt)
          .toSet();

      // 겹치지 않는다.
      expect(planned.intersection(fired), isEmpty,
          reason: '한 발송 시점이 예약과 복원 양쪽에 들면 알림이 두 번 세어진다');
      // 합치면 격자 전체(lead 3개)를 덮는다 — 빠진 시점이 없다.
      expect(planned.union(fired).length, expiryNotifyLeadDays.length,
          reason: '어느 쪽에도 안 든 시점이 있으면 그 알림은 사라진다');
    });

    test('발송 시각 정각은 복원 쪽이 가져간다(경계)', () {
      // 만료 8/14 → D-7 발송은 8/7 09:00. now를 정확히 그 순간으로 둔다.
      final DateTime atFire = DateTime(2026, 8, 7, expiryNotifyHour);
      final List<Gifticon> gifticons = <Gifticon>[
        _g(id: 'g-1', expiry: DateTime(2026, 8, 14)),
      ];

      final List<ExpiryNotificationItem> fired =
          firedExpiryNotifications(gifticons, now: atFire);
      final List<ScheduledExpiryNotification> planned =
          planExpiryNotifications(gifticons, now: atFire);

      expect(fired.map((ExpiryNotificationItem n) => n.leadDays),
          contains(expirySoonDays),
          reason: '울린 순간의 알림은 이미 받은 것이므로 목록에 있어야 한다');
      expect(planned.map((ScheduledExpiryNotification n) => n.leadDays),
          isNot(contains(expirySoonDays)),
          reason: '같은 시점을 예약이 또 잡으면 중복 발송이다');
    });
  });

  group('보관 기간', () {
    test('기본 30일보다 오래된 알림은 뺀다', () {
      // 만료 7/1 → D-1 발송 6/30 09:00 (now로부터 38일 전).
      final List<ExpiryNotificationItem> fired = firedExpiryNotifications(
        <Gifticon>[_g(id: 'old', expiry: DateTime(2026, 7, 1))],
        now: now,
      );

      expect(fired, isEmpty);
    });

    test('within을 넓히면 오래된 것도 나온다 — 상한은 정책이지 계산이 아니다', () {
      final List<ExpiryNotificationItem> fired = firedExpiryNotifications(
        <Gifticon>[_g(id: 'old', expiry: DateTime(2026, 7, 1))],
        now: now,
        within: const Duration(days: 365),
      );

      expect(fired, hasLength(expiryNotifyLeadDays.length));
    });
  });

  group('항목 내용', () {
    test('발송 시각·본문이 예약과 같은 규칙으로 채워진다', () {
      // 만료 8/10 → D-3 발송은 8/7 09:00(오늘 오전, 이미 지남).
      final List<ExpiryNotificationItem> fired = firedExpiryNotifications(
        <Gifticon>[
          _g(
              id: 'g-1',
              expiry: DateTime(2026, 8, 10),
              brand: '투썸',
              productName: '케이크'),
        ],
        now: now,
      );

      final ExpiryNotificationItem d3 =
          fired.firstWhere((ExpiryNotificationItem n) => n.leadDays == 3);
      expect(d3.firedAt, DateTime(2026, 8, 7, expiryNotifyHour));
      expect(d3.message, '투썸 케이크', reason: '본문은 예약 알림과 같은 문구여야 한다');
      expect(d3.gifticonId, 'g-1');
    });

    test('id는 기프티콘 + lead 조합이라 다시 계산해도 같다', () {
      final List<Gifticon> gifticons = <Gifticon>[
        _g(id: 'g-1', expiry: DateTime(2026, 8, 10)),
      ];

      final List<String> first = firedExpiryNotifications(gifticons, now: now)
          .map((ExpiryNotificationItem n) => n.id)
          .toList();
      final List<String> second = firedExpiryNotifications(gifticons, now: now)
          .map((ExpiryNotificationItem n) => n.id)
          .toList();

      expect(first, second);
      expect(first.toSet(), hasLength(first.length),
          reason: 'D-7과 D-1은 별개 항목이다');
    });
  });

  group('정렬', () {
    test('최신순으로 준다 — 목록이 다시 정렬하지 않아도 된다', () {
      final List<ExpiryNotificationItem> fired = firedExpiryNotifications(
        <Gifticon>[
          _g(id: 'a', expiry: DateTime(2026, 8, 9)),
          _g(id: 'b', expiry: DateTime(2026, 8, 12)),
        ],
        now: now,
      );

      for (int i = 1; i < fired.length; i++) {
        expect(fired[i - 1].firedAt.isBefore(fired[i].firedAt), isFalse,
            reason: '앞 항목이 뒤 항목보다 오래되면 최신순이 아니다');
      }
    });
  });
}
