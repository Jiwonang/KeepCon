/// 딥링크 URI → 목적지 파싱 테스트.
///
/// 세 수신 경로(웹 진입 URL·안드로이드 콜드 스타트·웜 스타트)가 전부 이 함수 하나를
/// 지나므로, 여기서 갈라지면 "웹에서는 되는데 앱에서는 안 되는" 형태가 된다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/deeplink/app_destination.dart';
import 'package:keepcon/shared/deeplink/deep_link_parser.dart';
import 'package:keepcon/shared/models/group.dart';

void main() {
  group('초대 링크', () {
    test('경로형 /invite/<code>', () {
      expect(
        parseDeepLink(Uri.parse('https://keepcon-ab660.web.app/invite/482913')),
        const InviteDestination('482913'),
      );
    });

    test('쿼리형 ?invite=<code>', () {
      expect(
        parseDeepLink(
            Uri.parse('https://keepcon-ab660.web.app/?invite=ABC123')),
        const InviteDestination('ABC123'),
      );
    });

    test('Group.inviteUrl을 그대로 되돌려 읽는다(라운드트립)', () {
      // 링크를 만드는 쪽과 읽는 쪽이 어긋나면 초대가 통째로 죽는다.
      final Group group = Group(
        id: 'g1',
        name: '가족',
        emoji: '👨‍👩‍👧',
        members: const <GroupMember>[
          GroupMember(
            userId: 'u1',
            displayName: '나',
            avatarEmoji: '🙂',
            role: MemberRole.owner,
          ),
        ],
        inviteCode: '482913',
      );
      expect(
        parseDeepLink(Uri.parse(group.inviteUrl)),
        const InviteDestination('482913'),
      );
    });
  });

  group('호스트를 가리지 않는다', () {
    // 호스트 필터링은 안드로이드 인텐트 필터가 이미 한다. 여기서 또 거르면 로컬 웹
    // 실행과 호스팅 미리보기 채널이 조용히 무시된다 — 개발 중 가장 자주 쓰는 경로다.
    test('localhost 개발 서버', () {
      expect(
        parseDeepLink(Uri.parse('http://localhost:8080/invite/777')),
        const InviteDestination('777'),
      );
    });

    test('Firebase Hosting 미리보기 채널', () {
      expect(
        parseDeepLink(
          Uri.parse('https://keepcon-ab660--pr7-abcd.web.app/invite/777'),
        ),
        const InviteDestination('777'),
      );
    });
  });

  group('앱이 다룰 링크가 아니면 null', () {
    test('초대와 무관한 경로', () {
      expect(parseDeepLink(Uri.parse('https://example.com/about')), isNull);
    });

    test('invite 경로지만 코드가 없다', () {
      expect(parseDeepLink(Uri.parse('https://example.com/invite')), isNull);
      expect(parseDeepLink(Uri.parse('https://example.com/invite/')), isNull);
    });

    test('빈 쿼리 값', () {
      expect(parseDeepLink(Uri.parse('https://example.com/?invite=')), isNull);
      expect(
        parseDeepLink(Uri.parse('https://example.com/?invite=%20%20')),
        isNull,
      );
    });

    test('경로도 쿼리도 없는 진입', () {
      expect(parseDeepLink(Uri.parse('https://example.com/')), isNull);
    });
  });

  test('목적지 값 동등성 — 같은 코드면 같은 목적지', () {
    // 버스에 실린 목적지를 비교/중복 제거할 때 값 동등성이 필요하다.
    expect(const InviteDestination('A'), const InviteDestination('A'));
    expect(const InviteDestination('A'), isNot(const InviteDestination('B')));
    expect(
      const InviteDestination('A').hashCode,
      const InviteDestination('A').hashCode,
    );
  });
}
