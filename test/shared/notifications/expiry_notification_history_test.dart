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
          contains(expiryNotifyLeadDays.first),
          reason: '울린 순간의 알림은 이미 받은 것이므로 목록에 있어야 한다');
      expect(planned.map((ScheduledExpiryNotification n) => n.leadDays),
          isNot(contains(expiryNotifyLeadDays.first)),
          reason: '같은 시점을 예약이 또 잡으면 중복 발송이다');
    });
  });

  group('실제로 발송됐던 것만 — 시간 술어만으로는 부족하다', () {
    test('등록 이전의 격자점은 복원하지 않는다 — 예약된 적이 없다', () {
      // 만료 임박 기프티콘을 스캔하는 것이 이 앱의 주 흐름이다. 8/23에 등록한 8/25
      // 만료 기프티콘은 D-7(8/18)·D-3(8/22)이 이미 지나 있지만, 그때 기프티콘이
      // 없었으므로 예약된 적도 울린 적도 없다. 시간 여집합만 보면 유령 알림 2건이
      // 생기고 신규 사용자에게는 그것이 그대로 안읽음 뱃지 숫자가 된다.
      final List<Gifticon> gifticons = <Gifticon>[
        Gifticon(
          id: 'g-1',
          ownerId: 'user-1',
          brand: '스타벅스',
          productName: '아메리카노 T',
          category: '카페',
          price: 4500,
          expiryDate: DateTime(2026, 8, 25),
          registeredAt: DateTime(2026, 8, 23, 14),
        ),
      ];
      final DateTime at = DateTime(2026, 8, 23, 15);

      final List<ExpiryNotificationItem> fired =
          firedExpiryNotifications(gifticons, now: at);
      expect(fired, isEmpty, reason: '등록 한 시간 전까지 울린 알림은 없다');

      // 예약 쪽은 정상 — D-1은 아직 미래라 여전히 잡힌다(둘이 겹치지도, 빠지지도 않는다).
      expect(planExpiryNotifications(gifticons, now: at).map((n) => n.leadDays),
          <int>[1]);
    });

    test('등록 이후의 격자점은 정상 복원된다(경계 확인)', () {
      final List<Gifticon> gifticons = <Gifticon>[
        Gifticon(
          id: 'g-1',
          ownerId: 'user-1',
          brand: '스타벅스',
          productName: '아메리카노 T',
          category: '카페',
          price: 4500,
          expiryDate: DateTime(2026, 8, 25),
          // D-7(8/18)보다 앞서 등록 → 세 격자점 모두 예약될 수 있었다.
          registeredAt: DateTime(2026, 8, 1),
        ),
      ];

      final List<ExpiryNotificationItem> fired =
          firedExpiryNotifications(gifticons, now: DateTime(2026, 8, 23, 15));
      expect(fired.map((ExpiryNotificationItem n) => n.leadDays), <int>[3, 7],
          reason: '이미 지난 D-3·D-7만(D-1은 아직 미래)');
    });

    test('날짜상 이미 만료된 것은 복원하지 않는다 — status는 전이되지 않는다', () {
      // `available → expired` 전이를 수행하는 주체가 이 앱에 없다(expiry_policy dartdoc).
      // status만 보면 어제 만료된 기프티콘이 available로 남아, 홈 카드는 "만료"라고
      // 칠하는데 알림 센터는 "내일 만료되는 기프티콘이 있어요"라고 말한다.
      final List<ExpiryNotificationItem> fired = firedExpiryNotifications(
        <Gifticon>[_g(id: 'gone', expiry: DateTime(2026, 8, 6))],
        now: now, // 2026-08-07 → 어제 만료
      );

      expect(fired, isEmpty, reason: '두 화면이 같은 기프티콘을 두고 다른 답을 내면 안 된다');
    });

    test('오늘 만료는 아직 만료가 아니다 — 알림이 남는다(경계)', () {
      final List<ExpiryNotificationItem> fired = firedExpiryNotifications(
        <Gifticon>[_g(id: 'today', expiry: DateTime(2026, 8, 7))],
        now: now,
      );

      expect(fired, isNotEmpty, reason: '오늘 쓸 수 있는 기프티콘의 알림은 유효하다');
    });
  });

  group('보관 기간', () {
    test('within보다 오래된 발송은 뺀다', () {
      // 만료 8/10 → D-7(8/3)·D-3(8/7 09:00)이 지났다. within을 1일로 좁히면
      // 8/6 이전 발송인 D-7이 빠진다.
      final List<ExpiryNotificationItem> fired = firedExpiryNotifications(
        <Gifticon>[_g(id: 'g-1', expiry: DateTime(2026, 8, 10))],
        now: now,
        within: const Duration(days: 1),
      );

      expect(fired.map((ExpiryNotificationItem n) => n.leadDays), <int>[3],
          reason: 'D-7(8/3)은 창 밖이다');
    });

    test('기본 30일 창은 현재 도달 불가다 — 만료 필터가 먼저 걸린다', () {
      // 만료 전인 기프티콘의 발송 시점은 아무리 이르러도 D-7, 즉 **7일 전**이 한계다.
      // 그래서 기본 30일은 지금 구성에서 한 건도 걸러내지 못한다 — 만료 필터가
      // 완화될 때를 위한 방어선으로만 남아 있다. 이 관계가 깨지면(예: 만료된 것도
      // 남기도록 정책이 바뀌면) 이 테스트가 먼저 알려 준다.
      expect(expiryNotificationHistory.inDays,
          greaterThan(expiryNotifyLeadDays.first),
          reason: '보관 창이 D-7보다 짧아지면 정상 알림이 잘린다');

      final List<ExpiryNotificationItem> fired = firedExpiryNotifications(
        <Gifticon>[_g(id: 'g-1', expiry: DateTime(2026, 8, 10))],
        now: now,
      );
      expect(fired, hasLength(2), reason: '기본 창에서는 지난 D-7·D-3이 모두 남는다');
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
