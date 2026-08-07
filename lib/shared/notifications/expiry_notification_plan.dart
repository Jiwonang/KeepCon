/// KeepCon 공유 계약 — 만료 임박 알림 "계획" 계산(순수 함수).
///
/// "무엇을 언제 띄울지"만 계산하고 **실제 예약은 하지 않는다.** 플러그인·플랫폼·권한과
/// 완전히 분리돼 있어 단위 테스트로 검증할 수 있다 — 알림은 며칠 뒤에야 결과가 드러나는
/// 기능이라, 로직을 실기기 확인에만 의존하면 회귀를 잡을 방법이 없다.
///
/// 판정 기준([expiryNotifyLeadDays]·[expiryNotifyHour])은 만료 정책 SSOT
/// (`shared/util/expiry_policy.dart`)에서 온다 — 화면의 "만료 임박"과 알림이 같은
/// 기준을 쓰게 하기 위해서다.
library;

import '../models/gifticon.dart';
import '../util/expiry_policy.dart';

/// 한 번에 예약을 유지하는 알림의 최대 개수.
///
/// 안드로이드는 앱당 예약 알람 수에 상한(약 500)이 있고, 넘기면 조용히 실패하거나
/// 예외가 난다. 기프티콘 하나당 최대 [expiryNotifyLeadDays]개가 잡히므로 상한을 둔다.
///
/// 초과분은 **먼 것부터** 버린다([planExpiryNotifications]가 가까운 순으로 정렬 후 자른다).
/// 잘린 알림도 사용자가 앱을 다시 열면 그때 다시 계산되므로, 그 사이에 만료가 임박해지면
/// 다음 동기화에서 예약된다.
const int maxScheduledExpiryNotifications = 180;

/// 예약할 알림 한 건. 플랫폼 타입을 쓰지 않는 순수 값 객체다.
class ScheduledExpiryNotification {
  /// ScheduledExpiryNotification 인스턴스를 생성한다.
  const ScheduledExpiryNotification({
    required this.id,
    required this.gifticonId,
    required this.leadDays,
    required this.scheduledAt,
    required this.title,
    required this.body,
  });

  /// 플랫폼에 넘길 알림 id. [planExpiryNotifications]가 정렬 후 0부터 매긴다.
  ///
  /// 기프티콘 id에서 해시로 뽑지 않는 이유: 동기화가 **전량 취소 후 재예약**이라
  /// 배치 안에서만 유일하면 충분하고, 순번은 해시와 달리 **충돌이 원천적으로 없다**
  /// (해시 충돌은 알림 한 건이 조용히 사라지는 형태로 나타나 발견하기 어렵다).
  final int id;

  /// 원본 [Gifticon.id]. 알림 탭 → 해당 기프티콘으로 보내는 후속 작업이 쓴다.
  final String gifticonId;

  /// 만료 며칠 전 알림인지([expiryNotifyLeadDays]의 한 값).
  final int leadDays;

  /// 발송 예정 시각(로컬 벽시계 기준). 타임존 변환은 스케줄러 구현이 담당한다.
  final DateTime scheduledAt;

  /// 알림 제목.
  final String title;

  /// 알림 본문.
  final String body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledExpiryNotification &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          gifticonId == other.gifticonId &&
          leadDays == other.leadDays &&
          scheduledAt == other.scheduledAt &&
          title == other.title &&
          body == other.body;

  @override
  int get hashCode =>
      Object.hash(id, gifticonId, leadDays, scheduledAt, title, body);

  @override
  String toString() => 'ScheduledExpiryNotification(id: $id, '
      'gifticonId: $gifticonId, D-$leadDays, at: $scheduledAt)';
}

/// [gifticons]에 대해 예약해야 할 만료 임박 알림 목록을 계산한다.
///
/// 규칙:
/// - [GifticonStatus.available]인 것만 대상이다(사용 완료·만료 처리된 것은 알릴 이유가 없다).
/// - 각 기프티콘마다 [expiryNotifyLeadDays]의 시점에, 그 날 [expiryNotifyHour]시로 잡는다.
/// - **이미 지난 시각은 버린다.** D-7이 지났어도 D-3·D-1은 살아 있으므로, 오늘 등록한
///   내일 만료 기프티콘도 남은 시점이 있으면 알림을 받는다.
/// - 가까운 순으로 정렬하고 [maxCount]개까지만 남긴다.
///
/// [now]는 테스트 주입용이며, 생략하면 [DateTime.now]를 쓴다.
List<ScheduledExpiryNotification> planExpiryNotifications(
  List<Gifticon> gifticons, {
  DateTime? now,
  int maxCount = maxScheduledExpiryNotifications,
}) {
  final DateTime current = now ?? DateTime.now();
  final List<_Pending> pending = <_Pending>[];

  for (final Gifticon g in gifticons) {
    if (g.status != GifticonStatus.available) continue;

    for (final int lead in expiryNotifyLeadDays) {
      // 만료일에서 lead일을 뺀 **날짜**의 지정 시각. 만료일의 시분초는 무시한다
      // (SSOT가 만료를 날짜 경계로 판정하는 것과 같은 규약).
      final DateTime fireAt = DateTime(
        g.expiryDate.year,
        g.expiryDate.month,
        g.expiryDate.day - lead,
        expiryNotifyHour,
      );
      if (!fireAt.isAfter(current)) continue;

      pending.add(_Pending(
        gifticonId: g.id,
        leadDays: lead,
        scheduledAt: fireAt,
        title: _title(lead),
        body: _body(g),
      ));
    }
  }

  // 가까운 순. 같은 시각이면 기프티콘 id로 안정 정렬한다 — 순서가 흔들리면 같은
  // 입력에도 id가 달라져 테스트가 깨지고 재예약이 불필요하게 요동친다.
  pending.sort((_Pending a, _Pending b) {
    final int byTime = a.scheduledAt.compareTo(b.scheduledAt);
    if (byTime != 0) return byTime;
    final int byId = a.gifticonId.compareTo(b.gifticonId);
    if (byId != 0) return byId;
    return b.leadDays.compareTo(a.leadDays);
  });

  final int take = maxCount < pending.length ? maxCount : pending.length;
  return <ScheduledExpiryNotification>[
    for (int i = 0; i < take; i++)
      ScheduledExpiryNotification(
        id: i,
        gifticonId: pending[i].gifticonId,
        leadDays: pending[i].leadDays,
        scheduledAt: pending[i].scheduledAt,
        title: pending[i].title,
        body: pending[i].body,
      ),
  ];
}

/// 정렬 전 중간 표현 — id는 정렬이 끝나야 확정되므로 분리해 둔다.
class _Pending {
  const _Pending({
    required this.gifticonId,
    required this.leadDays,
    required this.scheduledAt,
    required this.title,
    required this.body,
  });

  final String gifticonId;
  final int leadDays;
  final DateTime scheduledAt;
  final String title;
  final String body;
}

String _title(int leadDays) =>
    leadDays == 1 ? '내일 만료되는 기프티콘이 있어요' : '$leadDays일 뒤 만료되는 기프티콘이 있어요';

/// 본문은 "무엇이 만료되는가"만 담는다 — 알림창에서 한 줄로 읽히고, 바코드 같은
/// 민감한 값은 잠금화면에 노출되지 않아야 한다.
String _body(Gifticon g) => '${g.brand} ${g.productName}';
