/// share 화면의 **쓰기 액션 실패 안내** 회귀 테스트.
///
/// 배경: 이 화면들의 에러 핸들러는 `on StateError`로 좁혀 잡고 있었다. 계약이 가드 위반을
/// [StateError]로 규정하므로 in-memory 구현에서는 잘 동작했지만, 실서버(Firestore)가
/// 던지는 예외(권한 거부·오프라인 등)는 그 그물을 그대로 통과해 **아무 안내도 없이 화면이
/// 멈췄다** — 사용자에겐 버튼이 죽은 것으로만 보인다. 실제로 이 침묵 때문에 "초대 코드로
/// 그룹 참여가 실 백엔드에서 아예 실패한다"는 결함이 오랫동안 드러나지 않았다.
///
/// 그래서 이 파일이 고정하는 것은 **실패 원인과 무관하게 항상 안내가 뜨는가**다. 저장소가
/// 계약 밖 예외([Exception] — Firestore 실패 계열의 대역)를 던지게 하고, 각 액션마다
/// 스낵바 문구가 뜨는지 단언한다. `on StateError`로 되돌리면 이 그룹이 전부 깨진다.
///
/// 함께 고정하는 두 번째 규약: **try는 저장소 호출만 감싼다.** 성공 뒤의 `pop`·성공 스낵바가
/// try 안에 있으면, 작업은 성공했는데 화면 정리에서 예외가 났을 때 실패 안내가 떠 사용자가
/// 오해한다. 성공 경로가 그대로 동작하는지도 함께 확인한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/pages/group_detail_page.dart';
import 'package:keepcon/features/share/pages/member_invite_page.dart';
import 'package:keepcon/features/share/pages/shared_gifticon_detail_page.dart';
import 'package:keepcon/features/share/widgets/share_sheets.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

/// 계약 구현을 그대로 쓰되, 지정한 쓰기 메서드만 **비-[StateError] 예외**로 실패시키는 저장소.
///
/// 실서버가 던지는 `FirebaseException`의 대역이다 — UI가 예외 타입으로 백엔드를 구분하지
/// 않는다는 규약을 지키므로, 테스트도 firebase 패키지에 의존하지 않는다. 읽기 경로는 계약
/// 구현에 그대로 위임해, 화면이 진짜 데이터를 그리는 상태에서 액션만 실패시킨다.
class _BackendFailingShareRepository extends InMemoryShareRepository {
  _BackendFailingShareRepository({
    required super.authRepository,
    required super.gifticonRepository,
  }) : super(seed: false);

  /// 실패시킬 메서드 이름. 비어 있으면 전부 정상 동작한다.
  final Set<String> failing = <String>{};

  /// [watchGroups]가 대신 방출할 그룹(멤버 2명 이상 픽스처용 — in-memory 구현으로는
  /// 현재 사용자 외의 멤버를 만들 수 없다). `null`이면 계약 구현에 위임한다.
  List<Group>? groupsOverride;

  Never _boom(String name) => throw Exception('backend down: $name');

  @override
  Stream<List<Group>> watchGroups(String userId) => groupsOverride == null
      ? super.watchGroups(userId)
      : Stream<List<Group>>.value(groupsOverride!);

  @override
  Future<Group> createGroup({
    required String name,
    required String emoji,
    int maxMembers = Group.defaultMaxMembers,
  }) =>
      failing.contains('createGroup')
          ? _boom('createGroup')
          : super.createGroup(name: name, emoji: emoji, maxMembers: maxMembers);

  @override
  Future<void> leaveGroup(String groupId) => failing.contains('leaveGroup')
      ? _boom('leaveGroup')
      : super.leaveGroup(groupId);

  @override
  Future<void> deleteGroup(String groupId) => failing.contains('deleteGroup')
      ? _boom('deleteGroup')
      : super.deleteGroup(groupId);

  @override
  Future<Group> transferOwnershipAndLeave({
    required String groupId,
    required String newOwnerUserId,
  }) =>
      failing.contains('transferOwnershipAndLeave')
          ? _boom('transferOwnershipAndLeave')
          : super.transferOwnershipAndLeave(
              groupId: groupId,
              newOwnerUserId: newOwnerUserId,
            );

  @override
  Future<Group> removeMember({
    required String groupId,
    required String userId,
  }) =>
      failing.contains('removeMember')
          ? _boom('removeMember')
          : super.removeMember(groupId: groupId, userId: userId);

  @override
  Future<Group> setInviteOwnerOnly({
    required String groupId,
    required bool ownerOnly,
  }) =>
      failing.contains('setInviteOwnerOnly')
          ? _boom('setInviteOwnerOnly')
          : super.setInviteOwnerOnly(groupId: groupId, ownerOnly: ownerOnly);

  @override
  Future<Group> regenerateInviteCode({required String groupId}) =>
      failing.contains('regenerateInviteCode')
          ? _boom('regenerateInviteCode')
          : super.regenerateInviteCode(groupId: groupId);

  @override
  Future<SharedGifticon> shareGifticon({
    required String groupId,
    required Gifticon gifticon,
  }) =>
      failing.contains('shareGifticon')
          ? _boom('shareGifticon')
          : super.shareGifticon(groupId: groupId, gifticon: gifticon);

  @override
  Future<SharedGifticon> toggleReservation(String sharedGifticonId) =>
      failing.contains('toggleReservation')
          ? _boom('toggleReservation')
          : super.toggleReservation(sharedGifticonId);

  @override
  Future<SharedGifticon> markUsed(String sharedGifticonId) =>
      failing.contains('markUsed')
          ? _boom('markUsed')
          : super.markUsed(sharedGifticonId);

  @override
  Future<void> cancelShare(String sharedGifticonId) =>
      failing.contains('cancelShare')
          ? _boom('cancelShare')
          : super.cancelShare(sharedGifticonId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String me = InMemoryAuthRepository.defaultUser.id;

  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late _BackendFailingShareRepository repo;

  setUp(() {
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    repo = _BackendFailingShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
    );
  });

  tearDown(() {
    repo.dispose();
    gifticons.dispose();
    auth.dispose();
  });

  /// 이 화면들은 [ListView]라 화면 밖 항목을 **짓지 않는다** — 기본 800x600 뷰포트에서는
  /// 액션 버튼이 아예 존재하지 않아 탭이 조용히 빗나간다. 스크롤 안무 대신 뷰포트를 키워
  /// 전부 짓게 한다(테스트가 검증하려는 건 레이아웃이 아니라 실패 안내다).
  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 시트는 `BuildContext`를 요구하므로, 버튼 하나짜리 호스트 화면에서 연다.
  Future<void> pumpSheetHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open,
  ) async {
    await pump(
      tester,
      Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => open(context),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  /// 확인 다이얼로그의 '확인'/지정 버튼을 누른다.
  Future<void> confirm(WidgetTester tester, [String label = '확인']) async {
    await tester.tap(find.widgetWithText(TextButton, label));
    await tester.pumpAndSettle();
  }

  /// 방장(나) + 멤버 1명짜리 그룹 픽스처 — 소유권 이전/멤버 내보내기 경로용.
  Group twoMemberGroup() => Group(
        id: 'g1',
        name: '가족',
        emoji: '🏠',
        inviteCode: '123456',
        members: <GroupMember>[
          GroupMember(
            userId: me,
            displayName: InMemoryAuthRepository.defaultUser.displayName,
            avatarEmoji: '🙂',
            role: MemberRole.owner,
          ),
          const GroupMember(
            userId: 'user-2',
            displayName: '엄마',
            avatarEmoji: '👩',
            role: MemberRole.member,
          ),
        ],
      );

  Gifticon gifticon(String id) => Gifticon(
        id: id,
        ownerId: me,
        brand: '메가커피',
        productName: '아이스 아메리카노',
        price: 3000,
        category: '카페',
        expiryDate: DateTime(2027, 1, 1),
        registeredAt: DateTime(2026, 1, 1),
      );

  group('그룹 상세 — 백엔드 실패도 반드시 안내한다', () {
    testWidgets('그룹 나가기 실패', (WidgetTester tester) async {
      final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
      repo.failing.add('leaveGroup');

      await pump(tester, GroupDetailPage(groupId: g.id));
      await tester.tap(find.text('그룹 나가기'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(find.text('지금은 나갈 수 없어요.'), findsOneWidget);
    });

    testWidgets('그룹 삭제 실패', (WidgetTester tester) async {
      final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
      repo.failing.add('deleteGroup');

      await pump(tester, GroupDetailPage(groupId: g.id));
      await tester.tap(find.text('그룹 삭제'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(find.text('그룹을 삭제하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    });

    testWidgets('멤버 내보내기 실패', (WidgetTester tester) async {
      repo.groupsOverride = <Group>[twoMemberGroup()];
      repo.failing.add('removeMember');

      await pump(tester, const GroupDetailPage(groupId: 'g1'));
      await tester.tap(find.byTooltip('내보내기'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(find.text('멤버를 내보낼 수 없어요. 다시 확인해 주세요.'), findsOneWidget);
    });

    testWidgets('소유권 이전 후 나가기 실패', (WidgetTester tester) async {
      repo.groupsOverride = <Group>[twoMemberGroup()];
      repo.failing.add('transferOwnershipAndLeave');

      await pump(tester, const GroupDetailPage(groupId: 'g1'));
      await tester.tap(find.text('그룹 나가기'));
      await tester.pumpAndSettle();
      // 방장은 나가기 전에 소유권을 넘겨야 한다 — 대상 멤버를 고른다.
      await tester.tap(find.text('엄마').last);
      await tester.pumpAndSettle();

      expect(find.text('지금은 나갈 수 없어요.'), findsOneWidget);
    });
  });

  group('공유 기프티콘 상세 — 백엔드 실패도 반드시 안내한다', () {
    /// 내가 공유한 available 항목 하나를 만들고 상세를 띄운다.
    Future<SharedGifticon> seedSharedItem() async {
      final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
      return repo.shareGifticon(groupId: g.id, gifticon: gifticon('gx-1'));
    }

    testWidgets('찜하기 실패', (WidgetTester tester) async {
      final SharedGifticon item = await seedSharedItem();
      repo.failing.add('toggleReservation');

      await pump(tester, SharedGifticonDetailPage(itemId: item.id));
      await tester.tap(find.text('찜하기 (사용 예정)'));
      await tester.pumpAndSettle();

      expect(find.text('지금은 찜할 수 없어요.'), findsOneWidget);
    });

    testWidgets('사용 완료 실패', (WidgetTester tester) async {
      final SharedGifticon item = await seedSharedItem();
      repo.failing.add('markUsed');

      await pump(tester, SharedGifticonDetailPage(itemId: item.id));
      await tester.tap(find.widgetWithText(ElevatedButton, '사용 완료'));
      await tester.pumpAndSettle();

      expect(find.text('지금은 사용 완료할 수 없어요.'), findsOneWidget);
      // 실패했으므로 성공 안내는 뜨지 않는다(try가 성공 처리까지 감싸면 순서가 꼬인다).
      expect(find.text('사용 완료 처리했어요.'), findsNothing);
    });

    testWidgets('공유 취소(회수) 실패', (WidgetTester tester) async {
      final SharedGifticon item = await seedSharedItem();
      repo.failing.add('cancelShare');

      await pump(tester, SharedGifticonDetailPage(itemId: item.id));
      await tester.tap(find.text('공유 취소 (회수)'));
      await tester.pumpAndSettle();
      await confirm(tester, '회수');

      expect(find.text('지금은 회수할 수 없어요.'), findsOneWidget);
    });
  });

  group('시트 — 백엔드 실패도 반드시 안내한다', () {
    testWidgets('그룹 만들기 실패', (WidgetTester tester) async {
      repo.failing.add('createGroup');

      await pumpSheetHost(tester, (BuildContext c) => showCreateGroupSheet(c));
      await tester.enterText(find.byType(TextField), '가족');
      await tester.tap(find.widgetWithText(ElevatedButton, '만들기'));
      await tester.pumpAndSettle();

      expect(find.text('지금은 그룹을 만들 수 없어요.'), findsOneWidget);
    });

    testWidgets('그룹 만들기 성공 — 시트가 닫히고 성공 안내가 뜬다', (WidgetTester tester) async {
      await pumpSheetHost(tester, (BuildContext c) => showCreateGroupSheet(c));
      await tester.enterText(find.byType(TextField), '가족');
      await tester.tap(find.widgetWithText(ElevatedButton, '만들기'));
      await tester.pumpAndSettle();

      expect(find.text('"가족" 그룹을 만들었어요.'), findsOneWidget);
      expect(find.text('만들기'), findsNothing); // 시트가 닫혔다.
    });

    testWidgets('기프티콘 공유 실패', (WidgetTester tester) async {
      final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
      await gifticons.addGifticon(gifticon('gx-1'));
      repo.failing.add('shareGifticon');

      await pumpSheetHost(
        tester,
        (BuildContext c) => showShareGifticonSheet(c, g.id),
      );
      await tester.tap(find.text('아이스 아메리카노'));
      await tester.pumpAndSettle();

      expect(find.text('지금은 공유할 수 없어요.'), findsOneWidget);
    });
  });

  group('멤버 초대 — 백엔드 실패도 반드시 안내한다', () {
    testWidgets('초대 권한 설정 실패', (WidgetTester tester) async {
      final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
      repo.failing.add('setInviteOwnerOnly');

      await pump(tester, MemberInvitePage(groupId: g.id));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('초대 설정을 바꾸지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    });

    testWidgets('초대코드 재발급 — 백엔드 실패는 재시도 안내로 구분한다', (WidgetTester tester) async {
      final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
      repo.failing.add('regenerateInviteCode');

      await pump(tester, MemberInvitePage(groupId: g.id));
      await tester.tap(find.text('코드 재발급'));
      await tester.pumpAndSettle();
      await confirm(tester, '재발급');

      expect(find.text('초대코드를 재발급하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      // 성공 안내가 함께 뜨면 성공 처리가 try 안에 남아 있다는 뜻이다.
      expect(find.text('새 초대코드를 발급했어요. 24시간 동안 유효해요.'), findsNothing);
    });
  });
}
