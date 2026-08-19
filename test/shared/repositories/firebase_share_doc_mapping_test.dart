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
    'maxMembers': 'many',
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

    test('maxMembers가 손상 값이면 기본값으로 떨어진다', () {
      final Group? g =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'maxMembers': 'many',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
        ],
      });

      expect(g!.maxMembers, Group.defaultMaxMembers);
    });

    test('inviteOwnerOnly가 손상 값이면 false(권한을 넓히지 않는다)', () {
      final Group? g =
          FirebaseShareRepository.groupFromDataOrNull('g1', <String, dynamic>{
        'inviteOwnerOnly': 'yes',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'userId': 'user-1', 'role': 'owner'},
        ],
      });

      expect(g!.inviteOwnerOnly, isFalse);
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
