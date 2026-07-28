// 초대 링크 파서(parseInviteCode) 단위 테스트 (P3).
//
// Group.inviteUrl(경로형)과 쿼리형에서 초대코드를 역추출하는 순수 함수 검증 +
// Group.inviteUrl과의 라운드트립(빌더-파서 형식 drift 방지).

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/util/invite_link.dart';

void main() {
  group('parseInviteCode', () {
    test('경로형 .../invite/<code>에서 코드 추출', () {
      expect(
        parseInviteCode(Uri.parse('https://keepcon.app/invite/482913')),
        '482913',
      );
    });

    test('쿼리형 ?invite=<code>에서 코드 추출', () {
      expect(
        parseInviteCode(Uri.parse('https://keepcon.app/join?invite=771205')),
        '771205',
      );
    });

    test('쿼리형이 경로형보다 우선', () {
      expect(
        parseInviteCode(Uri.parse('https://x/invite/AAA?invite=BBB')),
        'BBB',
      );
    });

    test('초대 링크가 아니면 null', () {
      expect(parseInviteCode(Uri.parse('https://keepcon.app/')), isNull);
      expect(parseInviteCode(Uri.parse('https://keepcon.app/main')), isNull);
    });

    test('빈/공백 코드는 null', () {
      expect(parseInviteCode(Uri.parse('https://keepcon.app/invite/')), isNull);
      expect(parseInviteCode(Uri.parse('https://keepcon.app/join?invite=')),
          isNull);
    });

    test('앞뒤 공백은 제거', () {
      expect(
        parseInviteCode(Uri.parse('https://keepcon.app/join?invite=%20123%20')),
        '123',
      );
    });
  });

  group('Group.inviteUrl 라운드트립', () {
    test('inviteUrl을 파싱하면 원래 inviteCode를 얻는다', () {
      final Group g = Group(
        id: 'g',
        name: '가족',
        emoji: '🏠',
        inviteCode: '482913',
        members: const <GroupMember>[
          GroupMember(
            userId: 'user-1',
            displayName: '나',
            avatarEmoji: '🙂',
            role: MemberRole.owner,
          ),
        ],
      );
      expect(parseInviteCode(Uri.parse(g.inviteUrl)), g.inviteCode);
    });
  });
}
