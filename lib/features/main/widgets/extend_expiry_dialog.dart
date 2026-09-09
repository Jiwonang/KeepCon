/// main 페이지 — 유효기간 연장 날짜 선택.
///
/// 브랜드사가 기프티콘 기간을 늘려 줬을 때 그 결과를 앱에 반영하는 경로다. 그래서
/// **새 만료일을 사용자가 직접 고른다** — "+1개월" 같은 프리셋은 실제로 연장된 날짜와
/// 어긋나고, 어긋난 날짜는 만료 임박 알림·D-day 표시를 통째로 틀리게 만든다.
///
/// 범위는 scan의 등록 폼과 같은 상수([expirySelectableTo])를 쓴다. 하한만 다르다 —
/// 등록은 지난 날짜도 허용하지만(이미 만료된 것을 기록해 두는 것도 정당한 사용),
/// **연장은 뒤로만 옮길 수 있으므로**(계약 [GifticonRepository.extendExpiry]) 지난 날짜를
/// 고를 수 있게 두면 저장소가 거부하는 값을 화면이 먼저 내주는 셈이 된다.
library;

import 'package:flutter/material.dart';

import '../../scan/util/expiry_date_range.dart';

/// [pickExtendedExpiryDate]의 결과.
///
/// 취소와 "고를 수 있는 날이 없음"을 **구분한다.** 둘 다 null로 접으면 후자에서 버튼이
/// 조용히 무반응이 되어 사용자는 앱이 고장 난 것으로 읽는다.
sealed class ExtendDatePick {
  const ExtendDatePick();
}

/// 사용자가 새 만료일을 골랐다.
class ExtendDatePicked extends ExtendDatePick {
  const ExtendDatePicked(this.date);

  /// 고른 날짜.
  final DateTime date;
}

/// 사용자가 선택기를 닫았다.
class ExtendDateCancelled extends ExtendDatePick {
  const ExtendDateCancelled();
}

/// 고를 수 있는 날이 하나도 없어 선택기를 열지 못했다.
///
/// 하한(연장 가능한 첫날)이 상한을 넘은 경우다. 호출부는 이 사실을 사용자에게 알려야 한다.
///
/// [limit]을 함께 싣는 이유: 상한 상수는 scan 소유(`features/scan/util`)라 호출 화면이
/// 그것을 직접 import하면 **페이지 간 의존이 하나 더 생긴다**(이 저장소에 그런 선례가
/// 없다). 값을 결과에 실어 교차 참조를 이 파일 하나로 가둔다.
class ExtendDateUnavailable extends ExtendDatePick {
  const ExtendDateUnavailable(this.limit);

  /// 연장할 수 있는 마지막 날. 안내 문구에 쓴다.
  final DateTime limit;
}

/// 새 만료일을 고르는 날짜 선택기를 띄운다.
///
/// [currentExpiry]는 지금 저장된 만료일, [now]는 시각 정본([nowProvider])이 준 '오늘'이다.
/// 하한은 **둘 중 나중**의 다음 날이다:
/// - 오늘보다 이르면 이미 지난 날짜를 고르게 되고(만료된 것을 다시 만료된 채로 둔다),
/// - 현재 만료일보다 이르거나 같으면 계약의 "뒤로만" 가드에 걸려 거부된다.
///
/// 만료된 기프티콘이 이 기능의 주 대상이라 보통은 오늘이 하한이지만, 아직 만료되지 않은
/// 기프티콘을 미리 연장하는 경우에는 현재 만료일 다음 날이 하한이 된다.
Future<ExtendDatePick> pickExtendedExpiryDate(
  BuildContext context, {
  required DateTime currentExpiry,
  required DateTime now,
}) async {
  final DateTime today = DateTime(now.year, now.month, now.day);
  // ⚠️ `.add(const Duration(days: 1))`을 쓰지 마라 — 그것은 **정확히 24시간**이라 DST
  // 폴백(25시간짜리 하루)이 낀 타임존에서는 같은 달력 날짜에 머문다(Dart 문서: "may not
  // even hit the calendar date"). 그러면 하한이 현재 만료일 자신이 되고, `showDatePicker`가
  // 하한을 날짜로 정규화하면서 **저장소가 거부하는 값**(같은 날 = 연장이 아니다)을 화면이
  // 내주게 된다. 웹 빌드는 사용자 브라우저 타임존에서 돌아가므로 실제로 닿는 경로다.
  // 생성자의 오버플로 정규화는 달력 기준이라 그 함정이 없다.
  final DateTime dayAfterCurrent = DateTime(
    currentExpiry.year,
    currentExpiry.month,
    currentExpiry.day + 1,
  );
  final DateTime first =
      dayAfterCurrent.isAfter(today) ? dayAfterCurrent : today;

  // 상한이 하한보다 이르면 `showDatePicker`가 단언으로 죽는다. 상한을 넘긴 만료일
  // (파서가 2099년을 읽어 낼 수 있다 — expiry_date_range.dart 참조)이나 상한 연도를
  // 지난 시계에서 실제로 일어난다. 그때는 고를 수 있는 날이 없으므로 열지 않되,
  // **취소와 구별해서** 돌려준다 — 같은 null이면 버튼이 조용히 무반응이 된다.
  if (first.isAfter(expirySelectableTo)) {
    return ExtendDateUnavailable(expirySelectableTo);
  }

  final DateTime? picked = await showDatePicker(
    context: context,
    initialDate: first,
    firstDate: first,
    lastDate: expirySelectableTo,
    helpText: '새 유효기간 선택',
    confirmText: '연장',
    cancelText: '취소',
  );
  return picked == null
      ? const ExtendDateCancelled()
      : ExtendDatePicked(picked);
}
