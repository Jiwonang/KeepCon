// Group 모델의 초대코드 계약 (순수 모델 — 저장소 없이 검증한다).
//
// 검증 대상:
// - 코드와 만료는 **짝** 불변식(한쪽만 채우면 생성자가 막는다).
// - hasActiveInviteCode / inviteCodeRemaining — 판정은 값의 유무가 아니라 시각과 함께.
// - copyWith의 clearInviteCode — nullable 필드를 지우는 **유일한** 표현.
//
// 왜 모델 층에서 따로 보는가: 이 셋은 저장소를 거치지 않는 순수 판정인데, 화면 게이팅
// (발급 버튼·카운트다운)과 두 구현의 만료 가드가 전부 여기에 기댄다. 한 곳에서 못박아야
// 로직이 소비자마다 갈리지 않는다.

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/group.dart';

void main() {
  final DateTime t0 = DateTime(2026, 8, 26, 12);

  List<GroupMember> members() => <GroupMember>[
        const GroupMember(
          userId: 'u_owner',
          displayName: '방장',
          avatarEmoji: '👑',
          role: MemberRole.owner,
        ),
      ];

  Group build({String? code, DateTime? codeUntil}) => Group(
        id: 'g1',
        name: '가족',
        emoji: '🎁',
        members: members(),
        inviteToken: 'tok-abc',
        inviteExpiresAt: t0.add(const Duration(hours: 24)),
        inviteCode: code,
        inviteCodeExpiresAt: codeUntil,
      );

  group('짝 불변식', () {
    test('코드와 만료가 함께 없으면 정상 — 이것이 기본 상태다', () {
      final Group g = build();
      expect(g.inviteCode, isNull);
      expect(g.inviteCodeExpiresAt, isNull);
    });

    test('코드와 만료가 함께 있으면 정상', () {
      final Group g =
          build(code: '482913', codeUntil: t0.add(const Duration(minutes: 5)));
      expect(g.inviteCode, '482913');
    });

    test('코드만 있으면 생성자가 막는다 — "만료 없는 코드"를 만들 수 없다', () {
      expect(() => build(code: '482913'), throwsA(isA<AssertionError>()));
    });

    test('만료만 있으면 생성자가 막는다 — 가리킬 코드가 없는 만료', () {
      expect(
        () => build(codeUntil: t0.add(const Duration(minutes: 5))),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('hasActiveInviteCode / inviteCodeRemaining', () {
    test('코드가 없으면 비활성이고 남은 시간도 null이다', () {
      final Group g = build();
      expect(g.hasActiveInviteCode(t0), isFalse);
      expect(g.inviteCodeRemaining(t0), isNull);
    });

    test('만료 전이면 활성이고 남은 시간을 준다', () {
      final Group g =
          build(code: '482913', codeUntil: t0.add(const Duration(minutes: 5)));
      expect(g.hasActiveInviteCode(t0), isTrue);
      expect(g.inviteCodeRemaining(t0), const Duration(minutes: 5));
      expect(
        g.inviteCodeRemaining(t0.add(const Duration(minutes: 3))),
        const Duration(minutes: 2),
      );
    });

    test('만료 시각 정각은 이미 만료다(경계 포함하지 않음)', () {
      final DateTime until = t0.add(const Duration(minutes: 5));
      final Group g = build(code: '482913', codeUntil: until);
      expect(g.hasActiveInviteCode(until), isFalse);
      expect(g.inviteCodeRemaining(until), isNull);
    });

    test('만료된 뒤에도 값은 남지만 판정은 비활성이다', () {
      // 만료 시각에 문서를 고쳐 줄 주체가 없으므로 값은 남는다. 그래서 판정을
      // `inviteCode != null`로 하면 죽은 코드가 살아 있는 것으로 읽힌다 — 이 테스트가
      // 그 지름길을 막는다.
      final Group g =
          build(code: '482913', codeUntil: t0.add(const Duration(minutes: 5)));
      final DateTime later = t0.add(const Duration(minutes: 6));
      expect(g.inviteCode, isNotNull);
      expect(g.hasActiveInviteCode(later), isFalse);
      expect(g.inviteCodeRemaining(later), isNull);
    });
  });

  group('copyWith', () {
    test('코드를 새 값으로 교체한다', () {
      final Group g =
          build(code: '111111', codeUntil: t0.add(const Duration(minutes: 5)));
      final DateTime until = t0.add(const Duration(minutes: 10));
      final Group next =
          g.copyWith(inviteCode: '222222', inviteCodeExpiresAt: until);
      expect(next.inviteCode, '222222');
      expect(next.inviteCodeExpiresAt, until);
    });

    test('clearInviteCode가 둘을 함께 비운다', () {
      final Group g =
          build(code: '482913', codeUntil: t0.add(const Duration(minutes: 5)));
      final Group cleared = g.copyWith(clearInviteCode: true);
      expect(cleared.inviteCode, isNull);
      expect(cleared.inviteCodeExpiresAt, isNull);
      expect(cleared.hasActiveInviteCode(t0), isFalse);
    });

    test('clearInviteCode는 같은 호출의 코드 인자보다 우선한다', () {
      // 둘을 함께 넘기는 것은 호출부의 혼동이다. 어느 쪽이 이기는지 정해 두지 않으면
      // "지운 줄 알았는데 살아 있는" 상태가 조용히 생긴다.
      final Group g = build();
      final Group cleared = g.copyWith(
        inviteCode: '482913',
        inviteCodeExpiresAt: t0.add(const Duration(minutes: 5)),
        clearInviteCode: true,
      );
      expect(cleared.inviteCode, isNull);
      expect(cleared.inviteCodeExpiresAt, isNull);
    });

    test('코드를 건드리지 않는 copyWith는 기존 코드를 보존한다', () {
      final DateTime until = t0.add(const Duration(minutes: 5));
      final Group g = build(code: '482913', codeUntil: until);
      final Group renamed = g.copyWith(name: '친구들');
      expect(renamed.inviteCode, '482913');
      expect(renamed.inviteCodeExpiresAt, until);
    });
  });

  group('동등성·표시', () {
    test('코드가 다르면 다른 그룹이다', () {
      final DateTime until = t0.add(const Duration(minutes: 5));
      expect(
        build(code: '111111', codeUntil: until),
        isNot(build(code: '222222', codeUntil: until)),
      );
    });

    test('toString에 코드 값이 새지 않는다', () {
      // 로그·오류 리포트로 새면 5분짜리 자격증명이 그 로그를 읽는 사람에게 넘어간다.
      final Group g =
          build(code: '482913', codeUntil: t0.add(const Duration(minutes: 5)));
      expect(g.toString(), isNot(contains('482913')));
    });
  });
}
