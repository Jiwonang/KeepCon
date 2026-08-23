/// KeepCon 공유 계약 — 알림 센터가 한 목록에 담는 알림 한 건.
///
/// 알림은 출처가 둘이고 **성질이 다르다.**
/// - **그룹 알림**([GroupNotification]) — 저장소에 실제로 쌓인 문서다. 남이 만든 사건
///   (공유·사용 완료)이라 기록이 없으면 알 방법이 없다.
/// - **개인 만료 알림** — 저장된 기록이 **없다.** OS에 예약된 로컬 푸시일 뿐이고, 울린
///   사실을 남기려면 기기가 꺼져 있을 때도 쓸 서버가 필요하다. 대신 내 기프티콘의
///   만료일에서 **계산해 복원한다** — 발송 격자(D-7·D-3·D-1, 오전 9시)가 정책 상수라
///   "언제 울렸는가"가 결정론적으로 정해지기 때문이다.
///
/// 그래서 저장 여부가 아니라 **화면이 보는 형태**로 둘을 합친다. 파생 항목은 개별 삭제·
/// 읽음 표시가 불가능하다(계산식의 출력이라 지울 대상이 없다) — 개별 관리가 필요해지면
/// 그때 저장 방식으로 올린다.
///
/// ## sealed인 이유
/// 소비하는 `switch`가 새 종류에 대해 컴파일 에러를 내게 하려는 것이다([AppDestination]과
/// 같은 근거). 알림은 처리를 빠뜨려도 "그 항목만 조용히 안 보이는" 형태로 실패해서,
/// 목록을 눈으로 봐서는 빠진 줄을 알아채기 어렵다.
library;

import 'share.dart';

/// 알림 센터 목록의 한 항목.
sealed class AppNotification {
  /// 상수 생성자(하위 타입이 `const`가 될 수 있게).
  const AppNotification();

  /// 목록 안에서 유일한 식별자. 파생 항목도 계산으로 같은 값이 나온다(안정적).
  String get id;

  /// 발생(발송) 시각. 목록 정렬과 안읽음 판정의 기준이다.
  DateTime get createdAt;

  /// 카드 제목.
  String get title;

  /// 카드 본문.
  String get message;
}

/// 저장소에 쌓인 그룹 알림 한 건.
final class GroupNotificationItem extends AppNotification {
  /// GroupNotificationItem 인스턴스를 생성한다.
  const GroupNotificationItem(this.notification);

  /// 원본 그룹 알림. 화면이 [GroupNotification.type]별 아이콘을 고르는 데 쓴다.
  final GroupNotification notification;

  @override
  String get id => notification.id;

  @override
  DateTime get createdAt => notification.createdAt;

  @override
  String get title => notification.title;

  @override
  String get message => notification.message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupNotificationItem &&
          runtimeType == other.runtimeType &&
          notification == other.notification;

  @override
  int get hashCode => notification.hashCode;

  @override
  String toString() => 'GroupNotificationItem(${notification.id})';
}

/// 이미 울린 개인 만료 임박 알림 한 건(내 기프티콘에서 **계산해 복원**한 것).
final class ExpiryNotificationItem extends AppNotification {
  /// ExpiryNotificationItem 인스턴스를 생성한다.
  const ExpiryNotificationItem({
    required this.gifticonId,
    required this.leadDays,
    required this.firedAt,
    required this.title,
    required this.message,
  });

  /// 알림이 가리키는 [Gifticon.id]. 탭하면 홈 목록에서 이 카드를 강조한다.
  final String gifticonId;

  /// 만료 며칠 전 알림인지(`expiryNotifyLeadDays`의 한 값).
  final int leadDays;

  /// 발송된 시각(계산값 — 만료일 `leadDays`일 전의 `expiryNotifyHour`시).
  final DateTime firedAt;

  @override
  final String title;

  @override
  final String message;

  /// 기프티콘 + lead 일수로 조합한다 — 같은 기프티콘의 D-7과 D-1이 **별개 항목**이면서,
  /// 다시 계산해도 같은 값이 나와야 목록이 흔들리지 않는다(발송 시각은 lead에서
  /// 결정되므로 id에 따로 넣지 않는다).
  @override
  String get id => 'expiry:$gifticonId:D-$leadDays';

  @override
  DateTime get createdAt => firedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpiryNotificationItem &&
          runtimeType == other.runtimeType &&
          gifticonId == other.gifticonId &&
          leadDays == other.leadDays &&
          firedAt == other.firedAt &&
          title == other.title &&
          message == other.message;

  @override
  int get hashCode =>
      Object.hash(gifticonId, leadDays, firedAt, title, message);

  @override
  String toString() =>
      'ExpiryNotificationItem($gifticonId, D-$leadDays, at: $firedAt)';
}
