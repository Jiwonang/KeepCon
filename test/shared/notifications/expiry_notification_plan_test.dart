/// 만료 임박 알림 계획 계산 테스트.
///
/// 알림은 며칠 뒤에야 결과가 드러나므로 실기기 확인만으로는 회귀를 잡을 수 없다.
/// "언제 무엇을 띄울지"를 순수 함수로 떼어낸 이유가 여기 있다.
library;

import 'package:flutter_test/flutter_test.dart';
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
  final DateTime now = DateTime(2026, 8, 7, 15, 30);

  group('대상 선별', () {
    test('사용 완료·만료 상태는 알리지 않는다', () {
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[
          _g(
            id: 'used',
            expiry: DateTime(2026, 8, 20),
            status: GifticonStatus.used,
          ),
          _g(
            id: 'expired',
            expiry: DateTime(2026, 8, 20),
            status: GifticonStatus.expired,
          ),
        ],
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('이미 만료된 기프티콘은 남은 시점이 없어 아무것도 예약되지 않는다', () {
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[_g(id: 'past', expiry: DateTime(2026, 8, 1))],
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('빈 목록은 빈 계획', () {
      expect(planExpiryNotifications(const <Gifticon>[], now: now), isEmpty);
    });
  });

  group('시점 계산', () {
    test('만료 D-7·D-3·D-1에 오전 9시로 잡는다', () {
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[_g(id: 'a', expiry: DateTime(2026, 8, 20))],
        now: now,
      );

      expect(
          plan.map((ScheduledExpiryNotification n) => n.scheduledAt),
          <DateTime>[
            DateTime(2026, 8, 13, 9), // D-7
            DateTime(2026, 8, 17, 9), // D-3
            DateTime(2026, 8, 19, 9), // D-1
          ]);
      expect(
        plan.map((ScheduledExpiryNotification n) => n.leadDays),
        <int>[7, 3, 1],
      );
    });

    test('이미 지난 시점은 버리고 남은 것만 예약한다', () {
      // 8/10 만료 → D-7(8/3)은 지났고, D-3(8/4 09:00)도 지났다. D-1(8/9 09:00)만 남는다.
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[_g(id: 'soon', expiry: DateTime(2026, 8, 10))],
        now: now,
      );
      expect(plan, hasLength(1));
      expect(plan.single.leadDays, 1);
      expect(plan.single.scheduledAt, DateTime(2026, 8, 9, 9));
    });

    test('오늘 오전 9시는 이미 지났으므로 예약하지 않는다', () {
      // now가 8/7 15:30이라 8/7 09:00은 과거다. 8/8 만료의 D-1이 여기 해당한다.
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[_g(id: 'tomorrow', expiry: DateTime(2026, 8, 8))],
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('만료일의 시분초는 무시한다 — 날짜 경계로만 계산', () {
      final List<ScheduledExpiryNotification> a = planExpiryNotifications(
        <Gifticon>[_g(id: 'x', expiry: DateTime(2026, 8, 20))],
        now: now,
      );
      final List<ScheduledExpiryNotification> b = planExpiryNotifications(
        <Gifticon>[_g(id: 'x', expiry: DateTime(2026, 8, 20, 23, 59))],
        now: now,
      );
      expect(
        a.map((ScheduledExpiryNotification n) => n.scheduledAt),
        b.map((ScheduledExpiryNotification n) => n.scheduledAt),
      );
    });

    test('월 경계를 넘어도 정확하다', () {
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[_g(id: 'm', expiry: DateTime(2026, 9, 2))],
        now: now,
      );
      expect(
        plan.map((ScheduledExpiryNotification n) => n.scheduledAt),
        <DateTime>[
          DateTime(2026, 8, 26, 9),
          DateTime(2026, 8, 30, 9),
          DateTime(2026, 9, 1, 9),
        ],
      );
    });
  });

  group('정렬·id·상한', () {
    test('가까운 순으로 정렬하고 id를 0부터 매긴다', () {
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[
          _g(id: 'far', expiry: DateTime(2026, 9, 30)),
          _g(id: 'near', expiry: DateTime(2026, 8, 20)),
        ],
        now: now,
      );

      final List<DateTime> times =
          plan.map((ScheduledExpiryNotification n) => n.scheduledAt).toList();
      final List<DateTime> sorted = List<DateTime>.of(times)..sort();
      expect(times, sorted);
      expect(
        plan.map((ScheduledExpiryNotification n) => n.id),
        List<int>.generate(plan.length, (int i) => i),
      );
    });

    test('같은 입력이면 같은 계획이 나온다(결정적)', () {
      final List<Gifticon> input = <Gifticon>[
        _g(id: 'b', expiry: DateTime(2026, 8, 20)),
        _g(id: 'a', expiry: DateTime(2026, 8, 20)),
      ];
      expect(
        planExpiryNotifications(input, now: now),
        planExpiryNotifications(input, now: now),
      );
    });

    test('상한을 넘으면 먼 것부터 버린다', () {
      final List<Gifticon> many = <Gifticon>[
        for (int i = 0; i < 30; i++)
          _g(id: 'g$i', expiry: DateTime(2026, 9, 1).add(Duration(days: i))),
      ];
      final List<ScheduledExpiryNotification> plan =
          planExpiryNotifications(many, now: now, maxCount: 10);

      expect(plan, hasLength(10));
      // 남은 것은 전부 버려진 것보다 이르다.
      final List<ScheduledExpiryNotification> all =
          planExpiryNotifications(many, now: now, maxCount: 1000);
      final DateTime lastKept = plan.last.scheduledAt;
      final DateTime firstDropped = all[10].scheduledAt;
      expect(lastKept.isAfter(firstDropped), isFalse);
    });
  });

  group('알림 문구', () {
    test('D-1은 "내일"로 표현한다', () {
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[_g(id: 'a', expiry: DateTime(2026, 8, 9))],
        now: now,
      );
      expect(plan.single.title, contains('내일'));
      expect(plan.single.title, isNot(contains('1일 뒤')));
    });

    test('D-7·D-3은 남은 일수를 쓴다', () {
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[_g(id: 'a', expiry: DateTime(2026, 8, 20))],
        now: now,
      );
      expect(plan[0].title, contains('7일 뒤'));
      expect(plan[1].title, contains('3일 뒤'));
    });

    test('본문은 브랜드와 상품명이며 바코드는 넣지 않는다', () {
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[
          _g(
            id: 'a',
            expiry: DateTime(2026, 8, 20),
            brand: 'GS25',
            productName: '모바일 상품권 1만원',
          ),
        ],
        now: now,
      );
      expect(plan.first.body, 'GS25 모바일 상품권 1만원');
    });

    test('원본 기프티콘 id를 실어 보낸다(탭 → 화면 이동의 근거)', () {
      final List<ScheduledExpiryNotification> plan = planExpiryNotifications(
        <Gifticon>[_g(id: 'gifticon-42', expiry: DateTime(2026, 8, 20))],
        now: now,
      );
      expect(
        plan.every(
            (ScheduledExpiryNotification n) => n.gifticonId == 'gifticon-42'),
        isTrue,
      );
    });
  });

  test('첫 알림 시점은 화면의 만료 임박 기준과 같다', () {
    // 홈이 빨갛게 변하는 날과 첫 알림이 어긋나면 사용자가 혼란스럽다.
    expect(expiryNotifyLeadDays.first, expirySoonDays);
  });
}
