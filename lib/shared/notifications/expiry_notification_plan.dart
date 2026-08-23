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

import '../models/app_notification.dart';
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

/// 알림 센터가 거슬러 보여주는 기간. 이보다 오래전에 울린 알림은 목록에서 뺀다.
///
/// 기프티콘 하나당 최대 [expiryNotifyLeadDays]개(3건)가 쌓이므로 상한이 없으면 보유량이
/// 많은 사용자의 목록이 끝없이 길어진다. 30일이면 가장 이른 D-7 알림까지 넉넉히 담긴다.
const Duration expiryNotificationHistory = Duration(days: 30);

/// [gifticons]에 대해 **이미 울린** 만료 임박 알림을 복원한다.
///
/// [planExpiryNotifications]의 대칭이다 — 같은 격자([expiryNotifyLeadDays] × [expiryNotifyHour])를
/// 쓰되 예약이 미래만 남기는 자리에서 이쪽은 **과거만** 남긴다. 두 함수가 같은 상수를 보므로
/// "예약된 알림"과 "목록에 뜨는 알림"이 어긋날 수 없다.
///
/// 발송 기록을 저장하지 않고 계산으로 복원하는 이유는 [AppNotification] dartdoc에 있다.
/// 요약하면, 울린 사실을 남기려면 기기가 꺼져 있을 때도 쓸 서버가 필요한데 발송 시각이
/// 정책 상수로 결정론적이라 계산으로 같은 답을 얻을 수 있다.
///
/// 규칙:
/// - [GifticonStatus.available]인 것만 대상이다(예약과 같은 기준). 이미 쓰거나 만료된 건은
///   해결된 알림이라 목록을 채울 이유가 없다.
/// - 발송 시각이 [now]보다 **과거이거나 같아야** 한다(미래 = 아직 안 울린 것 = 예약의 몫).
/// - [within]보다 오래된 것은 버린다.
/// - **최신순**으로 정렬한다(목록이 최신순이므로 소비자가 다시 정렬하지 않아도 된다).
///
/// [now]는 테스트 주입용이며, 생략하면 [DateTime.now]를 쓴다.
List<ExpiryNotificationItem> firedExpiryNotifications(
  List<Gifticon> gifticons, {
  DateTime? now,
  Duration within = expiryNotificationHistory,
}) {
  final DateTime current = now ?? DateTime.now();
  final DateTime oldest = current.subtract(within);
  final List<ExpiryNotificationItem> fired = <ExpiryNotificationItem>[];

  for (final Gifticon g in gifticons) {
    if (g.status != GifticonStatus.available) continue;

    for (final int lead in expiryNotifyLeadDays) {
      // 예약과 **같은 식**으로 시각을 만든다 — 여기서 계산이 갈리면 울린 알림과 목록의
      // 시각이 어긋나 "온 적 없는 알림"이나 "빠진 알림"이 생긴다.
      final DateTime firedAt = DateTime(
        g.expiryDate.year,
        g.expiryDate.month,
        g.expiryDate.day - lead,
        expiryNotifyHour,
      );
      // 예약은 `isAfter(current)`인 것만 남긴다 — 그 여집합이 정확히 이 조건이라
      // 한 시점이 두 목록에 동시에 들거나 어느 쪽에도 안 드는 일이 없다.
      if (firedAt.isAfter(current)) continue;
      if (firedAt.isBefore(oldest)) continue;

      fired.add(ExpiryNotificationItem(
        gifticonId: g.id,
        leadDays: lead,
        firedAt: firedAt,
        title: _title(lead),
        message: _body(g),
      ));
    }
  }

  // 최신순. 같은 시각이면 기프티콘 id → lead 순으로 안정 정렬한다(목록 순서가 흔들리면
  // 같은 입력에도 화면이 달라 보인다).
  fired.sort((ExpiryNotificationItem a, ExpiryNotificationItem b) {
    final int byTime = b.firedAt.compareTo(a.firedAt);
    if (byTime != 0) return byTime;
    final int byId = a.gifticonId.compareTo(b.gifticonId);
    if (byId != 0) return byId;
    return a.leadDays.compareTo(b.leadDays);
  });

  return fired;
}
