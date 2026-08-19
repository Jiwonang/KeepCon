/// Firestore 문서 → 계약 모델 **매핑의 손상 내성** 테스트.
///
/// 배경: 매퍼가 `data['brand'] as String?`처럼 캐스팅으로 필드를 읽고 있었다. 필드 타입이
/// 어긋나면(레거시 문서·스키마 드리프트·콘솔에서 수기 수정) 캐스팅은 [TypeError]를 던지는데,
/// [TypeError]는 [Exception]이 아니라 **[Error]** 라서 두 겹으로 샌다:
///
/// - 계약이 "가드 위반은 [StateError]"로 규정한 그물에 안 걸린다.
/// - 목록 매핑(`watchSharedGifticons`)에서 터지면 **문서 하나가 그룹의 공유 목록 스트림
///   전체를 죽인다** — 그룹 매퍼는 손상 문서를 걸러 그 사고를 막고 있었지만 공유·이력·알림
///   매퍼에는 그 방어가 없었다.
///
/// 이 파일이 고정하는 것은 두 가지다.
///
/// 1. **읽기: 어떤 쓰레기 값을 넣어도 던지지 않는가.** 매퍼가 캐스팅으로 되돌아가면 깨진다.
/// 2. **쓰기: 손상 문서를 거부하는가.** 관용은 목록 전용이다 — 쓰기 경로가 같은 관용을 쓰면
///    폴백이 곧 판정이 되어 불변식이 뚫린다.
///
/// 매퍼는 문서 없이 맵만으로 도는 순수 static 함수로 노출돼 있어(`@visibleForTesting`),
/// Firestore 인스턴스도 `Firebase.initializeApp()`도 없이 직접 호출한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_share_repository.dart';

void main() {
  /// 모든 필드에 "타입이 틀린" 값을 넣은 문서 — 캐스팅이 있으면 첫 필드에서 터진다.
  ///
  /// ⚠️ 그룹 매퍼에 이 픽스처를 넣으면 `members`가 리스트가 아니라 멤버 0명 → 불변식
  /// 위반으로 **곧바로 null을 반환**한다. 그래서 그 아래에서만 읽히는 그룹 레벨 필드
  /// (`name`·`emoji`·`inviteToken`·`inviteOwnerOnly`·`maxMembers`·`inviteExpiresAt`)는
  /// 이 픽스처로는 **평가되지 않는다** — 각각의 단독 테스트가 담당한다.
  const Map<String, dynamic> garbage = <String, dynamic>{
    'groupId': 42,
    'gifticonId': <String>['not', 'a', 'string'],
    'sharedByUserId': true,
    'brand': 3.14,
    'productName': <String, dynamic>{'nested': 'map'},
    'status': 99,
    'lockedByUserId': 0,
    'reservedByUserId': false,
    'barcode': <int>[1, 2],
    'expiryDate': 'not-a-timestamp',
    'userId': 1,
    'sharedGifticonId': 2,
    'usedAt': 'nope',
    'type': 7,
    'title': <String>[],
    'message': 1.5,
    'createdAt': 3,
    'name': 1,
    'emoji': 2,
    'inviteToken': 3,
    'inviteOwnerOnly': 'yes',
    'maxMembers': 'many',
    'members': 'not-a-list',
    'memberIds': 'not-a-list',
    'inviteExpiresAt': 'nope',
  };

  /// 방장 1명짜리 정상 멤버 배열.
  List<Map<String, dynamic>> owner([String id = 'user-1']) =>
      <Map<String, dynamic>>[
        <String, dynamic>{'userId': id, 'role': 'owner'},
      ];

  group('공유 기프티콘 매퍼(읽기) — 손상 문서에도 던지지 않는다', () {
    test('타입이 전부 어긋난 문서도 예외 없이 매핑된다', () {
      final SharedGifticon s =
          FirebaseShareRepository.sharedFromData('s1', garbage);

      expect(s.id, 's1');
      expect(s.groupId, '');
      expect(s.brand, '');
      expect(s.productName, '');
      expect(s.lockedByUserId, isNull);
      expect(s.barcode, isNull);
      expect(s.expiryDate, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('빈 문서도 던지지 않는다', () {
      expect(
        () => FirebaseShareRepository.sharedFromData(
            's1', const <String, dynamic>{}),
        returnsNormally,
      );
    });

    test('정상 문서는 그대로 매핑된다(방어가 값을 뭉개지 않는다)', () {
      final SharedGifticon s = FirebaseShareRepository.sharedFromData(
        's9',
        <String, dynamic>{
          'groupId': 'g1',
          'gifticonId': 'gx',
          'sharedByUserId': 'user-1',
          'brand': '메가커피',
          'productName': '아이스 아메리카노',
          'status': ShareStatus.used.name,
          'lockedByUserId': 'user-2',
          'barcode': '1234',
        },
      );

      expect(s.groupId, 'g1');
      expect(s.brand, '메가커피');
      expect(s.productName, '아이스 아메리카노');
      expect(s.status, ShareStatus.used);
      expect(s.lockedByUserId, 'user-2');
      expect(s.barcode, '1234');
    });
  });

  group('쓰기 트랜잭션 매퍼 — 읽기는 관대하게, 쓰기는 엄격하게', () {
    /// 정상 문서(필수 식별자 셋 + 알려진 status).
    Map<String, dynamic> healthy([Map<String, dynamic> patch = const {}]) =>
        <String, dynamic>{
          'groupId': 'g1',
          'gifticonId': 'gx-1',
          'sharedByUserId': 'user-1',
          'status': ShareStatus.available.name,
          ...patch,
        };

    test('정상 문서는 통과한다(시드·_sharedToDoc이 쓰는 모양)', () {
      final SharedGifticon s =
          FirebaseShareRepository.requireSharedFromData('s1', healthy());
      expect(s.groupId, 'g1');
      expect(s.status, ShareStatus.available);
    });

    test('손상된 status는 available로 위장하지 못하고 StateError가 된다', () {
      // 관용 매퍼는 available로 흡수한다 — 목록에는 그대로 그려도 된다.
      expect(
        FirebaseShareRepository.sharedFromData('s1', healthy({'status': 99}))
            .status,
        ShareStatus.available,
      );
      // 쓰기 경로는 거부한다. 흡수를 허용하면 이미 사용한 항목이 한 번 더 사용 완료되고
      // UsageLog가 중복 적재된다(가드가 이 매퍼의 결과를 보므로 독립 검증이 아니다).
      expect(
        () => FirebaseShareRepository.requireSharedFromData(
            's1', healthy({'status': 99})),
        throwsStateError,
      );
      // 값은 문자열이지만 알 수 없는 이름인 경우도 같다.
      expect(
        () => FirebaseShareRepository.requireSharedFromData(
            's1', healthy({'status': 'bogus'})),
        throwsStateError,
      );
    });

    test('필수 식별자가 비면 StateError — 빈 값이 이력·알림·잠금 경로로 새지 않게', () {
      for (final String field in <String>[
        'groupId',
        'gifticonId',
        'sharedByUserId',
      ]) {
        final Map<String, dynamic> missing = healthy()..remove(field);
        expect(
          () => FirebaseShareRepository.requireSharedFromData('s1', missing),
          throwsStateError,
          reason: '$field 누락',
        );
        expect(
          () => FirebaseShareRepository.requireSharedFromData(
              's1', healthy(<String, dynamic>{field: 42})),
          throwsStateError,
          reason: '$field 손상',
        );
      }
    });

    test('빈 문서는 거부하지만, 목록용 매퍼는 같은 입력에 던지지 않는다', () {
      expect(
        () => FirebaseShareRepository.requireSharedFromData(
            's1', const <String, dynamic>{}),
        throwsStateError,
      );
      expect(
        () => FirebaseShareRepository.sharedFromData(
            's1', const <String, dynamic>{}),
        returnsNormally,
      );
    });
  });

  group('이력·알림 매퍼 — 손상 문서에도 던지지 않는다', () {
    test('사용 이력', () {
      final UsageLog l = FirebaseShareRepository.logFromData('l1', garbage);
      expect(l.id, 'l1');
      expect(l.groupId, '');
      expect(l.usedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('알림', () {
      final GroupNotification n =
          FirebaseShareRepository.notifFromData('n1', garbage);
      expect(n.id, 'n1');
      expect(n.title, '');
      expect(n.message, '');
    });
  });

  group('그룹 매퍼 — 손상 문서는 던지지 않고 걸러진다', () {
    test('타입이 어긋난 문서는 예외가 아니라 null', () {
      expect(
          FirebaseShareRepository.groupFromDataOrNull('g1', garbage), isNull);
    });

    test('레거시 문서(memberIds 없음)는 members를 그대로 믿는다', () {
      final Group? g = FirebaseShareRepository.groupFromDataOrNull(
        'g1',
        <String, dynamic>{'name': '가족', 'members': owner()},
      );

      expect(g, isNotNull);
      expect(g!.name, '가족');
      expect(g.memberCount, 1);
      expect(g.isOwnedBy('user-1'), isTrue);
    });

    test('memberIds가 손상 값이면 레거시와 같게 다룬다(목록을 죽이지 않는다)', () {
      final Group? g =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'name': '가족',
        'memberIds': 'not-a-list',
        'members': owner(),
      });

      expect(g, isNotNull);
      expect(g!.memberCount, 1);
    });

    test('멤버 항목이 손상돼도 던지지 않고, 유령 멤버는 정원을 먹지 않는다', () {
      // `members: 'not-a-list'`는 첫 줄에서 단락돼 멤버 단위 리더를 하나도 태우지 않는다.
      // 여기서는 리스트는 맞되 **항목이 손상된** 경우를 태운다.
      final Group? g =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'members': <dynamic>[
          <String, dynamic>{
            'userId': 7,
            'displayName': 1,
            'avatarEmoji': 2,
            'role': 99,
          },
          'not-a-map',
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
        ],
      });

      expect(g, isNotNull);
      // userId를 못 읽은 항목은 아무와도 매칭되지 않으면서 정원 한 칸을 먹으므로 걸러낸다.
      expect(g!.memberCount, 1);
      expect(g.members.single.userId, 'user-1');
    });

    test('name·emoji가 손상돼도 던지지 않고 기본값이 된다', () {
      // `garbage` 픽스처는 members 단락 때문에 이 두 필드에 **닿지 않는다** —
      // 정상 members와 함께 넣어야 리더를 실제로 태운다.
      final Group? g =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'name': 1,
        'emoji': <String>['x'],
        'members': owner(),
      });

      expect(g, isNotNull);
      expect(g!.name, '');
      expect(g.emoji, '🎁');
    });

    test('maxMembers가 손상 값이면 기본값으로 떨어진다', () {
      final Group? g = FirebaseShareRepository.groupFromDataOrNull(
        'g1',
        <String, dynamic>{'maxMembers': double.nan, 'members': owner()},
      );

      expect(g!.maxMembers, Group.defaultMaxMembers);
    });

    test('포화하는 거대 double은 읽기 실패로 다뤄 기본값이 된다', () {
      // `1e300`은 유한해서 isFinite만으로는 못 막고, toInt()가 int64 최대값으로 포화한다.
      // 그대로 두면 isFull이 영원히 false가 되어 정원 가드가 사라진다.
      expect(1e300.isFinite, isTrue);

      final Group? g = FirebaseShareRepository.groupFromDataOrNull(
        'g1',
        <String, dynamic>{'maxMembers': 1e300, 'members': owner()},
      );

      expect(g!.maxMembers, Group.defaultMaxMembers);
      expect(g.isFull, isFalse);
    });

    test('프리셋을 넘는 정상 값은 축소하지 않는다 — 계약에 상한이 없다', () {
      // 리더가 프리셋으로 조이면 `createGroup(maxMembers: 30)`으로 만든 그룹이 20으로
      // 읽혀, in-memory 구현과 갈라지고 방장이 한 번 쓰면 그 축소값이 문서에 굳는다.
      final Group? g = FirebaseShareRepository.groupFromDataOrNull(
        'g1',
        <String, dynamic>{'maxMembers': 30, 'members': owner()},
      );

      expect(g!.maxMembers, 30);
      expect(30, greaterThan(Group.memberCapPresets.last));
    });

    test('멤버가 정원보다 많아도 던지지 않고 하한으로 끌어올린다', () {
      final int over = Group.memberCapPresets.last + 5;
      final List<Map<String, dynamic>> many = <Map<String, dynamic>>[
        <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
        for (int i = 2; i <= over; i++)
          <String, dynamic>{'userId': 'user-$i', 'role': 'member'},
      ];

      final Group? g = FirebaseShareRepository.groupFromDataOrNull(
        'g1',
        <String, dynamic>{'maxMembers': 1, 'members': many},
      );

      expect(g, isNotNull);
      expect(g!.memberCount, over);
      // 서로 **다른** 멤버 over명이어야 한다 — 픽스처의 보간이 깨지면(예: `'user-\$i'`로
      // 이스케이프) 전부 같은 id가 되어 이 단언이 잡는다.
      expect(g.members.map((GroupMember m) => m.userId).toSet().length, over);
      // 불변식 maxMembers >= memberCount 유지.
      expect(g.maxMembers, over);
      expect(g.isFull, isTrue);
    });

    // `canInvite = isOwnedBy || !inviteOwnerOnly` — **false가 더 허용적인 값**이다.
    // 그래서 결측(레거시)과 손상의 폴백 방향이 갈린다.
    test('inviteOwnerOnly가 없으면(레거시) 기본 정책 false', () {
      final Group? g =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
          <String, dynamic>{'userId': 'user-2', 'role': 'member'},
        ],
      });

      expect(g!.inviteOwnerOnly, isFalse);
      expect(g.canInvite('user-2'), isTrue); // 멤버 아무나 초대 가능(기본 정책)
    });

    test('inviteOwnerOnly가 손상 값이면 true — 잠근 정책이 조용히 풀리지 않는다', () {
      final Group? g =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'inviteOwnerOnly': 'yes',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
          <String, dynamic>{'userId': 'user-2', 'role': 'member'},
        ],
      });

      expect(g!.inviteOwnerOnly, isTrue);
      expect(g.canInvite('user-2'), isFalse); // 일반 멤버는 초대 불가로 닫힌다
      expect(g.canInvite('user-1'), isTrue); // 방장은 그대로
    });

    test('만료 필드가 손상 값이면 epoch — 만료로 본다(fail-closed)', () {
      final Group? g = FirebaseShareRepository.groupFromDataOrNull(
        'g1',
        <String, dynamic>{'inviteExpiresAt': 'nope', 'members': owner()},
      );

      expect(g!.isInviteExpired(DateTime.now()), isTrue);
    });

    test('전체 되쓰기 경로는 _groupToDoc이 싣는 필드의 손상을 거부한다', () {
      // 읽기(목록)는 통과하지만 전체 되쓰기는 거부하는 대비. `_groupToDoc`이 문서 전체를
      // 되쓰므로 흡수한 값을 통과시키면 손상이 정상 값으로 굳는다.
      for (final Map<String, dynamic> corrupt in <Map<String, dynamic>>[
        <String, dynamic>{'name': 1},
        <String, dynamic>{'emoji': 2},
        <String, dynamic>{'inviteToken': 3},
        <String, dynamic>{'inviteOwnerOnly': 'yes'},
        <String, dynamic>{'maxMembers': 1e300},
        <String, dynamic>{'inviteExpiresAt': 'nope'},
      ]) {
        final Map<String, dynamic> data = <String, dynamic>{
          'members': owner(),
          ...corrupt,
        };
        expect(
          FirebaseShareRepository.groupFromDataOrNull('g1', data),
          isNotNull,
          reason: '읽기는 통과해야 한다',
        );
        expect(
          () => FirebaseShareRepository.requireGroupFromData('g1', data),
          throwsStateError,
          reason: '전체 되쓰기는 거부해야 한다',
        );
        // 멤버십만 되쓰는 경로(나가기)는 이 필드들을 되쓰지 않으므로 막지 않는다 —
        // 막으면 손상 그룹에서 나갈 수조차 없게 된다.
        expect(
          () => FirebaseShareRepository.requireGroupMembershipFromData(
              'g1', data),
          returnsNormally,
          reason: '멤버십 되쓰기는 통과해야 한다',
        );
      }
    });

    test('쓰기 경로는 memberIds 원소 손상도 거부한다 — 정상 멤버가 탈락해 사라진다', () {
      // `members`는 전부 정상이고 `memberIds`도 리스트라 "리스트인지"만 보면 통과한다.
      // 그런데 원소가 손상되면 `rawIds.contains(userId)`가 실패해 user-2가 걸러지고,
      // 그 상태로 되쓰면 문서에서 영구히 사라진다 — 유령 멤버 검증이 막으려던 것과
      // 같은 데이터 손실이 다른 경로로 들어온다.
      final Map<String, dynamic> data = <String, dynamic>{
        'memberIds': <dynamic>['user-1', 42],
        'members': <dynamic>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
          <String, dynamic>{'userId': 'user-2', 'role': 'member'},
        ],
      };

      // 읽기는 걸러진 채로 보여 준다(목록이 죽는 것보다 낫다).
      expect(
        FirebaseShareRepository.groupFromDataOrNull('g1', data)!.memberCount,
        1,
      );
      // 두 쓰기 경로 모두 거부한다 — 나가기(_memberIdsPatch)도 멤버십을 되쓴다.
      expect(
        () => FirebaseShareRepository.requireGroupFromData('g1', data),
        throwsStateError,
      );
      expect(
        () =>
            FirebaseShareRepository.requireGroupMembershipFromData('g1', data),
        throwsStateError,
      );
    });

    test('memberIds 원소가 전부 문자열이면 통과한다(정상 문서)', () {
      final Group g =
          FirebaseShareRepository.requireGroupFromData('g1', <String, dynamic>{
        'memberIds': <dynamic>['user-1', 'user-2'],
        'members': <dynamic>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
          <String, dynamic>{'userId': 'user-2', 'role': 'member'},
        ],
      });

      expect(g.memberCount, 2);
    });

    test('쓰기 경로는 유령 멤버를 거부한다 — 되쓰면 그 멤버가 문서에서 사라진다', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'members': <dynamic>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
          <String, dynamic>{'userId': 7, 'role': 'member'},
        ],
      };

      // 읽기는 유령을 걸러 그룹을 보여 준다.
      expect(
        FirebaseShareRepository.groupFromDataOrNull('g1', data)!.memberCount,
        1,
      );
      // 두 쓰기 경로 모두 거부한다 — 걸러진 채 되쓰면 그 멤버가 영구히 사라진다.
      expect(
        () => FirebaseShareRepository.requireGroupFromData('g1', data),
        throwsStateError,
      );
      expect(
        () =>
            FirebaseShareRepository.requireGroupMembershipFromData('g1', data),
        throwsStateError,
      );
    });

    test('되쓰지 않는 경로는 손상 문서도 통과시킨다 — 삭제·나가기가 막히지 않게', () {
      // `deleteGroup`(tx.delete)·`setInviteOwnerOnly`(인자값 한 필드)는 문서를 되쓰지
      // 않으므로 폴백이 굳을 일이 없다. 여기에 강한 검증을 붙이면 손상 그룹을 앱에서
      // 지울 수도, 설정을 되돌릴 수도 없어 콘솔 편집 말고는 복구 경로가 사라진다.
      final Map<String, dynamic> data = <String, dynamic>{
        'name': 1,
        'inviteExpiresAt': 'nope',
        'members': owner(),
      };

      // 불변식은 여전히 요구한다(멤버0·방장≠1이면 그룹이 아니다).
      expect(
          FirebaseShareRepository.groupFromDataOrNull('g1', data), isNotNull);
      expect(
        FirebaseShareRepository.groupFromDataOrNull(
            'g1', <String, dynamic>{'members': 'not-a-list'}),
        isNull,
      );
    });

    test('결측은 손상이 아니다 — 레거시 문서는 쓰기 경로도 통과한다', () {
      // memberIds·maxMembers·inviteExpiresAt이 없는 24시간 정책 이전 문서.
      final Group g =
          FirebaseShareRepository.requireGroupFromData('g1', <String, dynamic>{
        'name': '가족',
        'inviteCode': '123456',
        'members': owner(),
      });

      expect(g.name, '가족');
      expect(g.inviteToken, '123456');
      expect(g.maxMembers, Group.defaultMaxMembers);
    });

    test('레거시 inviteCode를 inviteToken으로 받아 준다(둘 다 손상이면 빈 값)', () {
      final Group? legacy = FirebaseShareRepository.groupFromDataOrNull(
        'g1',
        <String, dynamic>{'inviteCode': '123456', 'members': owner()},
      );
      expect(legacy!.inviteToken, '123456');

      // 새 이름이 있으면 그쪽이 이긴다.
      final Group? both = FirebaseShareRepository.groupFromDataOrNull(
        'g1',
        <String, dynamic>{
          'inviteToken': 'new-token',
          'inviteCode': '123456',
          'members': owner(),
        },
      );
      expect(both!.inviteToken, 'new-token');

      // 둘 다 타입이 어긋나도 던지지 않는다(예전엔 캐스팅 두 개가 연달아 있었다).
      final Group? broken =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'inviteToken': 1,
        'inviteCode': 2,
        'members': owner(),
      });
      expect(broken!.inviteToken, '');
    });
  });
}
