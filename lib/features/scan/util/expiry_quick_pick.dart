/// 유효기간 빠른 선택 옵션 (scan 페이지 로컬).
///
/// 기프티콘 유효기간은 "오늘부터 N일/N년"으로 적혀 있는 경우가 많아,
/// DatePicker에서 날짜를 찾아 누르는 것보다 버튼 한 번이 빠르다.
///
/// 계약(`Gifticon.expiryDate`)은 `DateTime` non-nullable이므로
/// 이 옵션이 계산한 값을 그대로 `GifticonFormController.setExpiryDate`에 넘긴다.
/// (계약에 새 타입을 추가하지 않는다 — 표현 계층의 편의 기능이다)
///
/// 왜 페이지 로컬인가 (CLAUDE.md '늦게 승격'):
/// 유효기간을 입력하는 화면은 현재 스캔 폼 하나뿐이다. 두 번째 소비자가
/// 실제로 생기면 그때 `contract-architect`에게 공유 승격을 요청한다.
library;

/// 유효기간 빠른 선택 항목.
enum ExpiryQuickPick {
  /// 오늘 + 30일.
  after30Days('+30일'),

  /// 오늘 + 90일.
  after90Days('+90일'),

  /// 오늘 + 1년.
  afterOneYear('+1년');

  const ExpiryQuickPick(this.label);

  /// 버튼에 표시할 문구.
  final String label;

  /// [base](보통 오늘) 기준으로 만료일을 계산한다.
  ///
  /// 계산 규칙:
  ///
  /// - `DateTime(year, month, day + N)` 형태로 **달력 기준** 계산을 한다.
  ///   `Duration(days: N)`을 더하면 서머타임이 있는 지역에서 시각이 1시간
  ///   밀려 날짜가 어긋날 수 있다(한국은 해당 없지만 규칙을 안전한 쪽으로 둔다).
  /// - 반환값은 항상 **자정(00:00)으로 정규화**된다. DatePicker가 돌려주는
  ///   값과 형태를 맞춰, 같은 날짜인데 시각만 달라 비교가 어긋나는 일을 막는다.
  /// - **+1년의 윤년 경계는 짧은 쪽으로 클램프한다.**
  ///   예: 2024-02-29 + 1년 → 2025-02-28.
  ///   Dart `DateTime` 정규화(→ 2025-03-01)를 그대로 쓰면 실제 유효기간보다
  ///   **늦은** 만료일이 저장되어, 이미 만료된 기프티콘이 메인 목록에서
  ///   사용 가능으로 보이는 위험한 방향의 오차가 된다. 만료일은 항상
  ///   짧은 쪽 오차가 안전하다.
  ///
  /// 예:
  ///
  /// ```
  /// base = 2026-07-30
  ///
  /// after30Days  → 2026-08-29
  /// after90Days  → 2026-10-28
  /// afterOneYear → 2027-07-30
  /// ```
  DateTime resolve(DateTime base) {
    switch (this) {
      case ExpiryQuickPick.after30Days:
        return DateTime(base.year, base.month, base.day + 30);

      case ExpiryQuickPick.after90Days:
        return DateTime(base.year, base.month, base.day + 90);

      case ExpiryQuickPick.afterOneYear:
        final DateTime candidate =
            DateTime(base.year + 1, base.month, base.day);

        // 존재하지 않는 날짜(2/29 → 다음 해에 없음)는 DateTime이
        // 다음 달로 이월시킨다(3/1). 만료일이 실제보다 늦어지는
        // 위험한 방향이므로, 그 달의 마지막 날로 클램프한다.
        //
        // DateTime(y, m + 1, 0)은 m월의 마지막 날이다.
        if (candidate.month != base.month) {
          return DateTime(base.year + 1, base.month + 1, 0);
        }

        return candidate;
    }
  }
}
