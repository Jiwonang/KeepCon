/// 저장 결과 스낵바 문구.
///
/// 화면에서 분리해 둔 이유는 **세 갈래를 테스트로 고정**하기 위해서다. 예전에는
/// 세 경우가 모두 `'기프티콘이 성공적으로 저장되었습니다.'` 한 문구였고,
/// 그래서 사용자는 자기가 고른 그룹에 실제로 들어갔는지 알 수 없었으며 부분
/// 실패(저장 성공 + 공유 실패)는 조용히 묻혔다. 상태에는
/// `sharedGroupName`·`shareError`가 담겨 있는데 화면이 쓰지 않았다.
library;

/// 저장 결과 안내 문구. 저장 성공을 전제로 **공유 결과**를 덧붙인다.
///
/// 세 갈래다:
///   - 지갑에 저장 — 공유를 시도하지 않았다
///   - 그룹 공유 성공 — 어느 그룹인지 이름으로 말한다
///   - 그룹 공유 실패 — **저장은 됐다는 사실을 먼저** 말한다. 부분 실패라
///     기프티콘은 지갑에 남아 있고, 사용자는 그룹 상세에서 다시 공유할 수 있다
///
/// `sharedGroupName`이 null인데 `shareError`도 null이면 지갑 저장이다
/// (`gifticon_form_state.dart`는 대상 그룹이 있을 때만 공유를 시도한다).
/// 공유는 성공했는데 그룹 이름을 못 읽은 경우도 이름 없이 안내한다 — 이름
/// 조회는 별도 스트림이라 타임아웃될 수 있다.
String saveResultMessage({
  required String? shareError,
  required String? sharedGroupName,
}) {
  if (shareError != null) {
    return '기프티콘은 저장했지만 그룹에 공유하지 못했어요. '
        '내 지갑에서 다시 공유할 수 있어요.';
  }

  if (sharedGroupName != null) {
    return '$sharedGroupName 그룹에 공유했어요.';
  }

  return '기프티콘이 성공적으로 저장되었습니다.';
}
