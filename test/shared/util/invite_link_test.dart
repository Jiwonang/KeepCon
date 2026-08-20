// 초대 링크 조립(inviteUrlFrom)·파싱(parseInviteToken) 단위 테스트.
//
// 경로형/쿼리형에서 토큰을 역추출하는 순수 함수 검증 + 조립-파싱 라운드트립
// (빌더와 파서의 형식이 갈라지면 링크가 조용히 죽는다).

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/util/invite_link.dart';

void main() {
  group('parseInviteToken', () {
    test('경로형 .../invite/<code>에서 코드 추출', () {
      expect(
        parseInviteToken(Uri.parse('https://keepcon.app/invite/482913')),
        '482913',
      );
    });

    test('쿼리형 ?invite=<code>에서 코드 추출', () {
      expect(
        parseInviteToken(Uri.parse('https://keepcon.app/join?invite=771205')),
        '771205',
      );
    });

    test('쿼리형이 경로형보다 우선', () {
      expect(
        parseInviteToken(Uri.parse('https://x/invite/AAA?invite=BBB')),
        'BBB',
      );
    });

    test('초대 링크가 아니면 null', () {
      expect(parseInviteToken(Uri.parse('https://keepcon.app/')), isNull);
      expect(parseInviteToken(Uri.parse('https://keepcon.app/main')), isNull);
    });

    test('빈/공백 코드는 null', () {
      expect(
          parseInviteToken(Uri.parse('https://keepcon.app/invite/')), isNull);
      expect(parseInviteToken(Uri.parse('https://keepcon.app/join?invite=')),
          isNull);
    });

    test('앞뒤 공백은 제거', () {
      expect(
        parseInviteToken(
            Uri.parse('https://keepcon.app/join?invite=%20123%20')),
        '123',
      );
    });
  });

  group('Group.inviteUrl 라운드트립', () {
    test('inviteUrl을 파싱하면 원래 inviteToken을 얻는다', () {
      final Group g = Group(
        id: 'g',
        name: '가족',
        emoji: '🏠',
        inviteToken: '482913',
        members: const <GroupMember>[
          GroupMember(
            userId: 'user-1',
            displayName: '나',
            avatarEmoji: '🙂',
            role: MemberRole.owner,
          ),
        ],
      );
      expect(
        parseInviteToken(Uri.parse(inviteUrlFrom(
          origin: 'https://keepcon-dev.web.app',
          inviteToken: g.inviteToken,
        ))),
        g.inviteToken,
      );
    });
  });

  group('inviteUrlFrom', () {
    test('origin + /invite/<token>으로 조립한다', () {
      expect(
        inviteUrlFrom(
            origin: 'https://keepcon-dev.web.app', inviteToken: 'AbC123'),
        'https://keepcon-dev.web.app/invite/AbC123',
      );
    });

    test('로컬 개발 origin(포트 포함)도 그대로 쓴다', () {
      expect(
        inviteUrlFrom(origin: 'http://localhost:5000', inviteToken: 'AbC123'),
        'http://localhost:5000/invite/AbC123',
      );
    });

    test('끝의 슬래시를 정리한다 — 안 하면 경로가 한 칸 밀려 파서가 못 찾는다', () {
      const String token = 'AbC123';
      final String url = inviteUrlFrom(
          origin: 'https://keepcon-dev.web.app/', inviteToken: token);
      expect(url, 'https://keepcon-dev.web.app/invite/$token');
      // 회귀의 본질은 문자열 모양이 아니라 **파싱 실패**다. 거기까지 고정한다.
      expect(parseInviteToken(Uri.parse(url)), token);
    });

    test('조립한 링크는 파서가 되돌린다(라운드트립)', () {
      const String token = '9Xk2QpLmNrTvWzYb4A';
      for (final String origin in <String>[
        'https://keepcon-ab660.web.app',
        'https://keepcon-dev.web.app',
        'http://localhost:5000',
      ]) {
        final String url = inviteUrlFrom(origin: origin, inviteToken: token);
        expect(parseInviteToken(Uri.parse(url)), token, reason: origin);
      }
    });
  });
}
