/// KeepCon 공유 계약 — 앱 바깥에서 들어온 "가야 할 곳"(목적지) 모델.
///
/// ## 왜 named route 테이블이 아닌가
/// KeepCon의 내비게이션은 탭 셸 + `Navigator.push`다. 여기에 `onGenerateRoute` 테이블을
/// 덧대면 **경로 문자열과 실제 화면 전환이 두 벌**이 되어, 탭 전환은 셸이 하고 push는
/// 라우터가 하는 어긋난 구조가 된다. 딥링크·알림이 실제로 필요한 것은 URL 파싱이 아니라
/// **"앱 밖의 신호를 앱 안의 행동으로 옮기는 한 줄의 통로"** 다.
///
/// 그래서 목적지를 값으로 표현하고, 조립부의 provider 한 곳
/// (`shared/providers/deep_link_providers.dart`)에 실어 셸이 소비한다. 이미
/// `pendingInviteCodeProvider`가 초대 한정으로 쓰던 방식을, 두 번째 소비자(알림 탭)가
/// 생기면서 계약으로 승격한 것이다.
///
/// ## sealed인 이유
/// 목적지가 늘어날 때(알림 탭 → 기프티콘 강조 등) 소비하는 `switch`가 컴파일 에러로
/// 새 경우를 강제하게 하려는 것이다. 처리를 빠뜨린 목적지는 "아무 일도 일어나지 않는"
/// 형태로 조용히 실패하는데, 딥링크에서 그건 발견하기 가장 어려운 버그다.
library;

/// 앱 바깥의 신호(딥링크·알림)가 지정하는 목적지.
sealed class AppDestination {
  /// 상수 생성자(하위 타입이 `const`가 될 수 있게).
  const AppDestination();
}

/// 초대코드로 그룹 참여 흐름을 연다.
///
/// 공유 탭으로 전환하고 참여 시트를 코드가 채워진 상태로 띄운다.
final class InviteDestination extends AppDestination {
  /// InviteDestination 인스턴스를 생성한다.
  const InviteDestination(this.inviteCode);

  /// 참여에 쓸 초대코드. 빈 문자열은 파서가 만들지 않는다.
  final String inviteCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InviteDestination &&
          runtimeType == other.runtimeType &&
          inviteCode == other.inviteCode;

  @override
  int get hashCode => inviteCode.hashCode;

  @override
  String toString() => 'InviteDestination($inviteCode)';
}

/// 홈 목록에서 특정 기프티콘을 짚어 보여준다(만료 임박 알림을 탭했을 때).
///
/// **상세 화면으로 보내지 않는 이유:** 개인 기프티콘 상세 화면이 아직 없다. 목록에서
/// 해당 카드를 강조해 스크롤해 주는 것만으로도 "어느 것 때문에 알림이 왔는가"라는
/// 물음에는 답이 된다. 상세 화면이 생기면 이 목적지의 처리부만 바꾸면 된다.
final class GifticonHighlightDestination extends AppDestination {
  /// GifticonHighlightDestination 인스턴스를 생성한다.
  const GifticonHighlightDestination(this.gifticonId);

  /// 강조할 [Gifticon.id]. 알림 payload로 실려 온다.
  final String gifticonId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GifticonHighlightDestination &&
          runtimeType == other.runtimeType &&
          gifticonId == other.gifticonId;

  @override
  int get hashCode => gifticonId.hashCode;

  @override
  String toString() => 'GifticonHighlightDestination($gifticonId)';
}
