/// Firestore 문서 → 계약 모델 **매핑의 손상 내성** 테스트.
///
/// 배경: 매퍼가 `data['brand'] as String?`처럼 캐스팅으로 필드를 읽고 있었다. 필드 타입이
/// 어긋나면(레거시 문서·스키마 드리프트·콘솔에서 수기 수정) 캐스팅은 [TypeError]를 던지는데,
/// [TypeError]는 [Exception]이 아니라 **[Error]** 라서 두 겹으로 샌다:
///
/// - 계약이 "가드 위반은 [StateError]"로 규정한 그물에 안 걸린다.
/// - 목록 매핑(`watchSharedGifticons`)에서 터지면 **문서 하나가 그룹의 공유 목록 스트림
///   전체를 죽인다** — 그룹 매퍼(`groupFromDataOrNull`)는 손상 문서를 걸러 그 사고를 막고
///   있었지만 공유·이력·알림 매퍼에는 그 방어가 없었다.
///
/// 그래서 이 파일이 고정하는 것은 **어떤 쓰레기 값을 넣어도 던지지 않는가**다. 매퍼가
/// 캐스팅으로 되돌아가면 이 그룹이 전부 깨진다.
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
    'inviteCode': 3,
    'inviteOwnerOnly': 'yes',
    // `is num`을 통과하지만 `toInt()`가 UnsupportedError(= Error)를 던지는 값.
    // Firestore는 IEEE 754 double을 그대로 저장하므로 실제로 들어올 수 있다.
    'maxMembers': double.nan,
    'members': 'not-a-list',
    'memberIds': 'not-a-list',
    'inviteExpiresAt': 'nope',
  };

  group('공유 기프티콘 매퍼 — 손상 문서에도 던지지 않는다', () {
    test('타입이 전부 어긋난 문서도 예외 없이 매핑된다', () {
      final SharedGifticon s =
          FirebaseShareRepository.sharedFromData('s1', garbage);

      expect(s.id, 's1');
      // 어긋난 값은 안전한 기본값으로 흡수한다.
      expect(s.groupId, '');
      expect(s.brand, '');
      expect(s.productName, '');
      expect(s.lockedByUserId, isNull);
      expect(s.barcode, isNull);
      // 시각은 기존 파서 규약대로 epoch로 떨어진다.
      expect(s.expiryDate, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('빈 문서도 던지지 않는다', () {
      expect(
        () => FirebaseShareRepository.sharedFromData(
            's1', const <String, dynamic>{}),
        returnsNormally,
      );
    });

    test('공유자 필드가 손상되면 빈 문자열 — 공유자 비교에서 걸러진다(fail-closed)', () {
      final SharedGifticon s =
          FirebaseShareRepository.sharedFromData('s1', garbage);
      // `cancelShare`는 `sharedByUserId == currentUser.id`를 요구하므로, 빈 값은
      // 어떤 실제 사용자와도 일치하지 않아 회수가 거부된다.
      expect(s.sharedByUserId, '');
      expect(s.sharedByUserId, isNot(equals('user-1')));
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
        // 필드 누락
        final Map<String, dynamic> missing = healthy()..remove(field);
        expect(
          () => FirebaseShareRepository.requireSharedFromData('s1', missing),
          throwsStateError,
          reason: '$field 누락',
        );
        // 타입 손상
        expect(
          () => FirebaseShareRepository.requireSharedFromData(
              's1', healthy(<String, dynamic>{field: 42})),
          throwsStateError,
          reason: '$field 손상',
        );
      }
    });

    test('빈 문서는 당연히 거부한다', () {
      expect(
        () => FirebaseShareRepository.requireSharedFromData(
            's1', const <String, dynamic>{}),
        throwsStateError,
      );
      // 반면 목록용 매퍼는 같은 입력에 던지지 않는다 — 두 규약이 공존한다.
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
      // `members`가 리스트가 아니므로 멤버 0명 → Group 불변식 위반 → null.
      expect(
          FirebaseShareRepository.groupFromDataOrNull('g1', garbage), isNull);
    });

    test('레거시 문서(memberIds 없음)는 members를 그대로 믿는다', () {
      final Group? g =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'name': '가족',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
        ],
      });

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
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
        ],
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

    test('maxMembers가 손상 값이면 기본값으로 떨어진다', () {
      final Group? g =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'maxMembers': double.nan,
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
        ],
      });

      expect(g!.maxMembers, Group.defaultMaxMembers);
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
      final Group? g =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'inviteExpiresAt': 'nope',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
        ],
      });

      // 만료 판정의 단일 진입점에 '지금'을 넣어 확인한다.
      expect(g!.isInviteExpired(DateTime.now()), isTrue);
    });
  });
}
