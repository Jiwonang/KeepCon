/// scan — 유효기간이 **고를 수 있는 범위**와 지난 날짜 판정.
///
/// 값 자체는 원래 `gifticon_form_page.dart`의 `showDatePicker` 호출부에
/// `DateTime(2020)`·`DateTime(2035)`로 박혀 있었다. 한곳으로 올린 이유는 이 범위를
/// **보는 곳이 셋**이기 때문이다 — 피커의 경계, 피커를 여는 시작 위치(클램프),
/// 그리고 지난 날짜 안내. 셋이 갈라지면 "고를 수 없는 값이 프리필돼 있는" 상태가
/// 조용히 생긴다(실제로 그 상태였다 — 아래 참조).
///
/// ## 왜 파서를 이 범위로 제한하지 않는가
///
/// `GifticonOcrParser`는 **이미지에 적힌 것을 그대로 읽는 것이 일이다.** 2016년이
/// 인쇄돼 있으면 2016년을 내야 하고, 실제로 그렇게 동작한다(픽스처 테스트가
/// `expect(result.expiryDate, DateTime(2016, 2, 12))`로 못박고 있다). 파서가
/// 범위를 강제하면 원본과 다른 값을 내는 셈이라, 사용자가 화면에서 확인·수정할
/// 기회 자체가 사라진다.
///
/// 그래서 범위는 **화면의 책임**이다. 파서는 읽은 대로 주고, 화면은 그것이 고를 수
/// 있는 범위 밖이면 피커가 죽지 않게 좁혀 열고, 지난 날짜면 사용자에게 알린다.
library;

/// 유효기간으로 고를 수 있는 가장 이른 날.
///
/// 지난 날짜를 **허용하는** 하한이다. `GifticonStatus.expired`가 계약상 정상
/// 상태이고(`available → expired` 전이가 정의돼 있다), 이미 만료된 기프티콘을
/// 기록해 두는 것도 정당한 사용이라 오늘로 막지 않는다. 대신 지난 날짜에는
/// [isPastExpiry]로 안내를 띄운다.
final DateTime expirySelectableFrom = DateTime(2020);

/// 유효기간으로 고를 수 있는 가장 늦은 날.
final DateTime expirySelectableTo = DateTime(2035);

/// [date]가 이미 지난 날짜인가 — 날짜 단위로만 본다.
///
/// 시각을 함께 비교하면 **오늘 만료**가 지난 것으로 잡힌다. 유효기간은 그날
/// 자정까지 유효한 것이 보통이므로 오늘은 지나지 않은 것으로 센다.
///
/// [now]를 받는 이유는 테스트가 시계를 고정하기 위해서다 — `DateTime.now()`를
/// 안에서 부르면 자정 경계에서 테스트가 코드가 아니라 달력 때문에 깨진다
/// (이 저장소는 같은 유형으로 2026-08-27 CI가 실제로 터진 이력이 있다).
bool isPastExpiry(DateTime date, {required DateTime now}) {
  final DateTime dayOfDate = DateTime(date.year, date.month, date.day);
  final DateTime today = DateTime(now.year, now.month, now.day);
  return dayOfDate.isBefore(today);
}
