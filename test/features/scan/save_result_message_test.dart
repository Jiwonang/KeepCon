/// 저장 결과 스낵바 문구 테스트.
///
/// 예전에는 세 경우가 **모두 같은 문구**였다 —
/// `'기프티콘이 성공적으로 저장되었습니다.'`. 지갑에 넣었을 때도, 그룹에
/// 공유됐을 때도, **공유만 실패했을 때도.** 그래서 사용자는 자기가 고른 그룹에
/// 실제로 들어갔는지 알 수 없었고, 부분 실패(저장 성공 + 공유 실패)는 조용히
/// 묻혔다. 상태에는 `sharedGroupName`·`shareError`가 담겨 있는데 화면이 그것을
/// 쓰지 않았다(`gifticon_form_state.dart`의 `shareError` 주석이 그 사실을
/// 인정하고 있었다).
///
/// 실제 앱으로 세 번 저장해 스낵바가 매번 같은 것을 확인한 뒤 고쳤다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/util/save_result_message.dart';

void main() {
  group('저장 결과 문구', () {
    test('내 지갑에 저장하면 공유를 언급하지 않는다', () {
      final String message = saveResultMessage(
        shareError: null,
        sharedGroupName: null,
      );

      expect(message, '기프티콘이 성공적으로 저장되었습니다.');
      expect(message, isNot(contains('그룹')));
    });

    test('그룹에 공유되면 그 그룹 이름을 말한다', () {
      // 어느 그룹에 들어갔는지가 핵심이다 — "저장했어요"만으로는 사용자가
      // 고른 대로 됐는지 알 수 없다.
      expect(
        saveResultMessage(shareError: null, sharedGroupName: '가족'),
        '가족 그룹에 공유했어요.',
      );
      expect(
        saveResultMessage(shareError: null, sharedGroupName: '친구 모임'),
        '친구 모임 그룹에 공유했어요.',
      );
    });

    test('공유가 실패해도 저장은 됐다는 사실을 먼저 말한다', () {
      // 부분 실패다 — 기프티콘은 지갑에 남아 있다. 그 사실을 먼저 말하지 않으면
      // 사용자가 저장 자체가 실패한 줄 알고 다시 등록해 중복이 생긴다.
      final String message = saveResultMessage(
        shareError: '그룹에 공유하지 못했어요.',
        sharedGroupName: null,
      );

      expect(message, contains('저장했'));
      expect(message, contains('공유하지 못했'));
      // 다음 행동을 알려 준다 — 실패만 알리면 사용자가 할 수 있는 게 없다.
      expect(message, contains('다시 공유'));
    });

    test('재공유 경로로 실재하는 곳을 가리킨다', () {
      // 처음에는 '내 지갑에서 다시 공유할 수 있어요'라고 적었다. 그런데 내 지갑
      // (`lib/features/main`)에는 공유 액션이 **없다** — 그 화면은 오히려
      // "공유 탭에서 해주세요"라고 안내한다. 기존 기프티콘의 재공유 진입점은
      // 공유 탭 → 그룹 상세의 '공유' pill 하나뿐이다.
      //
      // 없는 경로로 안내하면 사용자는 시키는 대로 하고도 아무것도 찾지 못한다.
      // 다음 행동을 알려 주는 문구일수록 그 행동이 실재해야 한다.
      final String message = saveResultMessage(
        shareError: '그룹에 공유하지 못했어요.',
        sharedGroupName: null,
      );

      expect(message, contains('공유 탭'));
      expect(message, isNot(contains('내 지갑')));
    });

    test('공유 실패가 그룹 이름보다 우선한다', () {
      // 이름을 읽은 뒤에 공유가 실패하는 순서는 없지만, 둘이 함께 오면
      // **실패를 알리는 쪽**이 맞다 — 성공했다고 말하면 거짓이 된다.
      expect(
        saveResultMessage(shareError: '실패', sharedGroupName: '가족'),
        contains('공유하지 못했'),
      );
    });

    test('공유는 됐는데 그룹 이름을 못 읽으면 이름 없이 공유를 알린다', () {
      // 이름 조회는 별도 스트림이라 타임아웃될 수 있다
      // (`gifticon_form_state.dart`가 5초 상한을 건다). 그때 `null 그룹에
      // 공유했어요` 같은 문구가 나가면 안 된다.
      final String message = saveResultMessage(
        shareError: null,
        sharedGroupName: null,
        sharedToGroup: true,
      );

      expect(message, isNot(contains('null')));
      expect(message, '그룹에 공유했어요.');
    });

    test('이름을 못 읽은 공유와 지갑 저장은 서로 다른 문구다', () {
      // 같으면 사용자는 자기가 고른 그룹에 실제로 들어갔는지 알 수 없다 —
      // 이 파일이 없애려던 바로 그 상태다. 게다가 확인하러 가도 막다른 길이다:
      // 이미 공유된 기프티콘은 `unsharedGifticonsProvider`가 후보에서 빼므로
      // 공유 탭에는 "공유할 수 있는 기프티콘이 없어요."만 뜬다.
      final String sharedNoName = saveResultMessage(
        shareError: null,
        sharedGroupName: null,
        sharedToGroup: true,
      );
      final String wallet = saveResultMessage(
        shareError: null,
        sharedGroupName: null,
      );

      expect(sharedNoName, isNot(wallet));
      expect(sharedNoName, contains('공유'));
      expect(wallet, isNot(contains('공유')));
    });
  });
}
