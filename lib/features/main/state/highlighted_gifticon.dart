/// main 페이지 — 목록에서 잠시 강조할 기프티콘.
///
/// 만료 임박 알림을 탭하면 홈으로 오는데, 기프티콘이 여러 장이면 **어느 것 때문에
/// 알림이 왔는지** 사용자가 다시 찾아야 한다. 그 카드를 스크롤해 보여주고 잠깐
/// 강조해서 그 물음에 답한다.
///
/// 화면 상태(어느 카드를 강조할지)라 main 페이지가 소유한다 — 목적지 계약
/// (`shared/deeplink`)은 "홈에서 이 기프티콘을 짚어라"까지만 말하고, 강조를 어떻게
/// 표현하고 언제 거둘지는 화면의 몫이다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 강조가 유지되는 시간. 지나면 자동으로 거둔다.
///
/// 계속 남겨두면 다음에 홈에 들어왔을 때도 이유 없이 카드 하나가 빛나 보인다.
const Duration highlightDuration = Duration(seconds: 4);

/// 강조 대상과 그 수명을 함께 관리한다.
///
/// **타이머를 목록 위젯이 아니라 여기 두는 이유:** 알림을 탭했을 때 사용자가 다른 탭에
/// 있거나 목록이 아직 안 그려졌을 수 있다. 위젯이 거두게 하면 그 경우 강조가 영원히
/// 남아, 한참 뒤에 홈에 들어왔을 때 이유 없이 카드가 빛난다. 상태 스스로 거두면
/// 화면이 떠 있든 아니든 같은 시간에 끝난다.
class HighlightedGifticonController extends Notifier<String?> {
  Timer? _timer;

  @override
  String? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// [gifticonId]를 강조하고 [highlightDuration] 뒤에 스스로 거둔다.
  ///
  /// 강조 중에 다시 호출되면 타이머를 새로 잡는다(연달아 알림을 탭한 경우, 마지막
  /// 것이 온전한 시간을 받는다).
  void highlight(String gifticonId) {
    _timer?.cancel();
    state = gifticonId;
    _timer = Timer(highlightDuration, () => state = null);
  }

  /// 즉시 거둔다.
  void clear() {
    _timer?.cancel();
    state = null;
  }
}

/// 지금 강조할 [Gifticon.id]. 없으면 `null`.
///
/// 셸이 알림 목적지를 소비하며 [HighlightedGifticonController.highlight]로 채우고,
/// 컨트롤러가 스스로 비운다. 목록은 이 값을 **읽어서** 스크롤·테두리만 담당한다.
final NotifierProvider<HighlightedGifticonController, String?>
    highlightedGifticonIdProvider =
    NotifierProvider<HighlightedGifticonController, String?>(
  HighlightedGifticonController.new,
);
