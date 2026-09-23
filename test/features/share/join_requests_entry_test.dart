// 그룹 상세의 **'승인요청목록' 진입점**을 고정한다.
//
// 참여 요청 목록은 그룹 상세 안에 인라인으로 펼쳐지다가 전용 화면으로, 다시 **모달
// 팝업**(`JoinRequestsDialog`)으로 옮겨졌고, 그 자리에는 버튼 하나가 남았다.
// 이 파일이 지키는 것은 넷이다.
//
//  ① **방장만 본다.** 아직 멤버가 아닌 사람들의 존재·수를 일반 멤버에게 알리지 않는다
//     (보안 규칙도 같은 선을 긋는다).
//  ② **0건에도 버튼이 남는다.** 인라인 섹션은 0건이면 통째로 사라졌는데, 진입점까지
//     사라지면 방장이 "요청이 없다"는 것조차 확인할 수 없고 화면 구조가 건수에 따라
//     흔들린다. 이 축이 회귀하면 조용히 예전 동작으로 돌아간다.
//  ③ **뱃지가 로딩·에러를 0으로 접지 않는다.** 이 스트림은 방장에게 요청 도착을 알리는
//     유일한 신호라, `valueOrNull?.length ?? 0`으로 접으면 에러일 때 버튼이 당당하게
//     "대기 중인 요청이 없어요"라고 거짓말한다. 그 거짓말이 곧 승인 누락이다.
//  ④ **목록은 팝업으로 열리고 그룹 상세는 그대로 남는다.** 전체 화면 push로 되돌아가면
//     상세가 통째로 덮여 "어느 그룹의 대기자인지"라는 맥락이 사라진다. 아래 단언은
//     push였다면 반드시 실패한다(닫힌 라우트는 `skipOffstage` 기본값에 걸려 검색에서
//     빠진다) — 그것이 이 축의 회귀 감지 원리다.
//
// 목록 본문(승인·거절·행 잠금·재시도)은 `join_request_ui_test.dart`가, 팝업의 스크림·
// 크기·닫기 경로는 `join_requests_dialog_test.dart`가 고정한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/pages/group_detail_page.dart';
import 'package:keepcon/features/share/widgets/join_requests_dialog.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

/// 대기 목록 스트림의 세 갈래(값·로딩·에러)를 테스트가 고르는 저장소.
///
/// 읽기·쓰기의 나머지는 계약 구현에 그대로 위임한다 — 화면이 진짜 그룹 데이터를 그리는
/// 상태에서 이 축만 흔들어야, 단언이 픽스처가 아니라 화면 동작을 재는 것이 된다.
class _PendingShareRepository extends InMemoryShareRepository {
  _PendingShareRepository({
    required super.authRepository,
    required super.gifticonRepository,
  }) : super(seed: false);

  /// [watchGroups]가 대신 방출할 그룹. in-memory 구현으로는 **내가 방장이 아닌** 그룹을
  /// 만들 수 없어서(생성자가 곧 방장) 비방장 축은 이 주입이 유일한 경로다.
  List<Group>? groupsOverride;

  /// 그룹 목록을 **여러 번** 방출해야 하는 테스트용(그룹이 도중에 사라지는 경우).
  /// 설정하면 [groupsOverride]보다 우선한다.
  StreamController<List<Group>>? groupsController;

  /// 대기 목록 방출 모드 — `data`(기본) / `hang`(첫 방출 전) / `error`.
  _PendingMode mode = _PendingMode.data;

  /// [_PendingMode.data]일 때 방출할 목록.
  List<JoinRequest> pending = const <JoinRequest>[];

  final List<String> approved = <String>[];
  final List<String> rejected = <String>[];

  @override
  Stream<List<Group>> watchGroups(String userId) {
    final StreamController<List<Group>>? c = groupsController;
    if (c != null) return _seededGroups(c);
    return groupsOverride == null
        ? super.watchGroups(userId)
        : Stream<List<Group>>.value(groupsOverride!);
  }

  /// [groupsOverride]를 **먼저 한 번** 흘린 뒤 [groupsController]를 잇는다.
  ///
  /// broadcast 스트림은 구독 전에 넣은 값을 되풀이하지 않는다 — 구독은 화면이 push된
  /// 뒤에 일어나므로, 컨트롤러만 쓰면 첫 값이 유실돼 그룹이 **영원히 로딩**이 된다
  /// (스피너가 계속 돌아 `pumpAndSettle`이 타임아웃한다 — 실측).
  Stream<List<Group>> _seededGroups(StreamController<List<Group>> c) async* {
    if (groupsOverride != null) yield groupsOverride!;
    yield* c.stream;
  }

  @override
  Stream<List<JoinRequest>> watchPendingJoinRequests(String groupId) {
    switch (mode) {
      case _PendingMode.hang:
        // 값을 주지 않고 열어 둔다 = 로딩 지속.
        final StreamController<List<JoinRequest>> c =
            StreamController<List<JoinRequest>>();
        addTearDown(c.close);
        return c.stream;
      case _PendingMode.error:
        return Stream<List<JoinRequest>>.error(StateError('규칙 거부'));
      case _PendingMode.data:
        return Stream<List<JoinRequest>>.value(pending);
    }
  }

  @override
  Future<Group> approveJoinRequest(String joinRequestId) async {
    approved.add(joinRequestId);
    // 화면은 반환값을 쓰지 않는다 — 계약 시그니처를 맞추기만 한다.
    return groupsOverride!.first;
  }

  @override
  Future<JoinRequest> rejectJoinRequest(String joinRequestId) async {
    rejected.add(joinRequestId);
    return pending
        .firstWhere((JoinRequest r) => r.id == joinRequestId)
        .copyWith(status: JoinRequestStatus.rejected);
  }
}

enum _PendingMode { data, hang, error }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String me = InMemoryAuthRepository.defaultUser.id;

  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late _PendingShareRepository repo;

  setUp(() {
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    repo = _PendingShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
    );
  });

  tearDown(() {
    repo.dispose();
    gifticons.dispose();
    auth.dispose();
  });

  JoinRequest req(String id, {String displayName = '요청자'}) => JoinRequest(
        id: id,
        groupId: 'g1',
        userId: 'u-$id',
        displayName: displayName,
        avatarEmoji: '🙂',
        requestedAt: DateTime(2026, 1, 1),
      );

  GroupMember member(String userId, String name, MemberRole role) =>
      GroupMember(
        userId: userId,
        displayName: name,
        avatarEmoji: '🙂',
        role: role,
      );

  /// 내가 방장인 그룹 / 남이 방장인 그룹 픽스처.
  // `group`은 flutter_test의 최상위 함수라 이름이 겹치면 테스트 그룹 선언이 가려진다.
  Group groupFixture({required bool iAmOwner}) => Group(
        id: 'g1',
        name: '가족',
        emoji: '🏠',
        inviteToken: 'tok',
        members: <GroupMember>[
          if (iAmOwner)
            member(me, '나', MemberRole.owner)
          else ...<GroupMember>[
            member('owner-2', '방장', MemberRole.owner),
            member(me, '나', MemberRole.member),
          ],
        ],
      );

  /// 그룹 상세는 [ListView]라 화면 밖 항목을 짓지 않는다 — 뷰포트를 키워 전부 짓게 한다.
  Future<void> pumpDetail(WidgetTester tester, {bool settle = true}) async {
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
        child: const MaterialApp(home: GroupDetailPage(groupId: 'g1')),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
      return;
    }
    // 로딩 축은 스피너가 계속 돌아 정착하지 않는다 — 프레임 단위로 진행한다.
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  group('진입점 노출', () {
    testWidgets('방장에게 버튼이 보인다', (WidgetTester tester) async {
      repo
        ..groupsOverride = <Group>[groupFixture(iAmOwner: true)]
        ..pending = <JoinRequest>[req('a'), req('b')];
      await pumpDetail(tester);

      expect(find.text('승인요청목록'), findsOneWidget);
      expect(find.text('2명이 참여를 기다리고 있어요'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('일반 멤버에게는 버튼이 아예 없다', (WidgetTester tester) async {
      repo
        ..groupsOverride = <Group>[groupFixture(iAmOwner: false)]
        ..pending = <JoinRequest>[req('a')];
      await pumpDetail(tester);

      // 멤버 목록은 떴는데(화면은 정상) 진입점만 없다 — 공허한 통과 방지.
      expect(find.text('멤버 2/10명'), findsOneWidget);
      expect(find.text('승인요청목록'), findsNothing);
    });

    testWidgets('대기 0건에도 버튼은 남고, 뱃지만 빠진다', (WidgetTester tester) async {
      // 버튼이 회귀하면 조용히 예전(인라인 섹션) 동작으로 돌아간다 — 방장은 "요청이
      // 없다"는 것조차 확인할 수 없고, 진입점이 건수에 따라 나타났다 사라져 구조가
      // 흔들린다. 뱃지 쪽은 반대 방향의 회귀를 막는다 — `0`은 부제가 이미 하는 말이고,
      // 회색 뱃지는 라이트 모드 대비가 3:1을 밑돈다.
      repo
        ..groupsOverride = <Group>[groupFixture(iAmOwner: true)]
        ..pending = const <JoinRequest>[];
      await pumpDetail(tester);

      expect(find.text('승인요청목록'), findsOneWidget);
      expect(find.text('대기 중인 요청이 없어요'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });

  group('뱃지는 로딩·에러를 0으로 접지 않는다', () {
    testWidgets('로딩 — 스피너를 보여주고 0이라고 하지 않는다', (WidgetTester tester) async {
      repo
        ..groupsOverride = <Group>[groupFixture(iAmOwner: true)]
        ..mode = _PendingMode.hang;
      await pumpDetail(tester, settle: false);

      // 본문이 그려진 상태여야 아래 단언이 의미를 갖는다(그룹 로딩 스피너와 혼동 방지).
      expect(find.text('승인요청목록'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('불러오는 중…'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('대기 중인 요청이 없어요'), findsNothing);
    });

    testWidgets('에러 — 0이 아니라 실패를 말하고, 버튼은 여전히 눌린다',
        (WidgetTester tester) async {
      repo
        ..groupsOverride = <Group>[groupFixture(iAmOwner: true)]
        ..mode = _PendingMode.error;
      await pumpDetail(tester);

      expect(find.text('불러오지 못했어요. 눌러서 다시 시도'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('대기 중인 요청이 없어요'), findsNothing);

      // 실패해도 진입은 막히지 않는다 — 안쪽 배너의 '다시 시도'가 복구 경로다.
      await tester.tap(find.text('승인요청목록'));
      await tester.pumpAndSettle();
      expect(find.byType(JoinRequestsDialog), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });
  });

  group('진입 → 결정', () {
    testWidgets('버튼을 누르면 팝업이 열리고 그룹 상세는 트리에 남는다', (WidgetTester tester) async {
      // 전체 화면 push로 되돌아가면 아래 두 단언이 깨진다 — 그룹 상세 라우트가
      // 비활성이 되어 `skipOffstage` 기본값에 걸려 검색에서 빠지기 때문이다.
      repo
        ..groupsOverride = <Group>[groupFixture(iAmOwner: true)]
        ..pending = <JoinRequest>[req('a', displayName: '지원')];
      await pumpDetail(tester);

      // 진입 전에는 목록이 없다(버튼이 목록을 인라인으로 펼치지 않는다).
      expect(find.byType(JoinRequestsDialog), findsNothing);
      expect(find.text('지원'), findsNothing);

      await tester.tap(find.text('승인요청목록'));
      await tester.pumpAndSettle();

      expect(find.byType(JoinRequestsDialog), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('지원'), findsOneWidget);
      // 뒤의 그룹 상세가 그대로 보인다 — 팝업의 존재 이유다.
      expect(find.byType(GroupDetailPage), findsOneWidget);
      expect(find.text('가족'), findsWidgets);
      expect(find.text('멤버 1/10명'), findsOneWidget);
    });

    testWidgets('승인이 계약 메서드를 부르고 결과가 팝업 안에서 사용자에게 닿는다',
        (WidgetTester tester) async {
      repo
        ..groupsOverride = <Group>[groupFixture(iAmOwner: true)]
        ..pending = <JoinRequest>[req('a', displayName: '지원')];
      await pumpDetail(tester);

      await tester.tap(find.text('승인요청목록'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '승인'));
      await tester.pumpAndSettle();

      expect(repo.approved, <String>['a']);
      expect(repo.rejected, isEmpty);
      // 스낵바가 아니라 팝업 안이다 — 스낵바는 배리어에 덮여 바랜다(픽셀 실측).
      expect(
          find.descendant(
              of: find.byType(Dialog), matching: find.text('지원님을 그룹에 추가했어요.')),
          findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('거절도 계약 메서드를 부른다 — 두 버튼이 뒤바뀌지 않았다',
        (WidgetTester tester) async {
      repo
        ..groupsOverride = <Group>[groupFixture(iAmOwner: true)]
        ..pending = <JoinRequest>[req('a', displayName: '지원')];
      await pumpDetail(tester);

      await tester.tap(find.text('승인요청목록'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '거절'));
      await tester.pumpAndSettle();

      expect(repo.rejected, <String>['a']);
      expect(repo.approved, isEmpty);
      expect(
          find.descendant(
              of: find.byType(Dialog), matching: find.text('참여 요청을 거절했어요.')),
          findsOneWidget);
    });

    testWidgets('팝업이 열린 채 그룹이 사라지면 팝업도 상세도 닫히고 호출부로 돌아온다',
        (WidgetTester tester) async {
      // ⚠️ 이 테스트는 **최종 상태 가드**이지 `popUntil` 한 줄의 회귀 가드가 아니다.
      // 그 줄을 지우는 뮤테이션으로도 통과한다 — 팝업이 닫히면 아래 라우트가 리빌드돼
      // postFrameCallback이 한 번 더 걸리고, 그 두 번째 기회가 상세까지 닫기 때문이다
      // (프레임 단위로 관측해 확인했다). 그래도 이 축을 남기는 이유는, 그 자기 치유가
      // Navigator 구현 세부에 기대는 것이라 **깨지면 사용자가 빈 화면에 갇힌다**는 데
      // 있다. 여기서 재는 것은 "무엇이 먼저 닫히는가"가 아니라 "결국 호출부로 돌아오는가"다.
      // 승인 대기 팝업은 방장이 열어 둔 채 기다리는 자리라 이 창이 특히 넓다.
      final StreamController<List<Group>> groups =
          StreamController<List<Group>>.broadcast();
      addTearDown(groups.close);
      repo
        ..groupsOverride = <Group>[groupFixture(iAmOwner: true)]
        ..groupsController = groups
        ..pending = <JoinRequest>[req('a')];

      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 상세를 **push된 라우트**로 띄운다 — `home:`으로 두면 최초 라우트라 pop 자체가
      // 성립하지 않아 이 결함을 잴 수 없다.
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authRepositoryProvider.overrideWithValue(auth),
            gifticonRepositoryProvider.overrideWithValue(gifticons),
            shareRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const GroupDetailPage(groupId: 'g1'),
                    )),
                    child: const Text('상세 열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('상세 열기'));
      await tester.pumpAndSettle();
      expect(find.byType(GroupDetailPage), findsOneWidget);

      await tester.tap(find.text('승인요청목록'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget, reason: '팝업이 떠 있는 것이 전제');

      // 다른 기기의 그룹 삭제·소유권 이전 → 내 그룹에서 빠진다.
      groups.add(const <Group>[]);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(GroupDetailPage), findsNothing,
          reason: '팝업만 닫히고 상세가 남으면 빈 화면에 갇힌다');
      expect(find.text('상세 열기'), findsOneWidget, reason: '호출부로 복귀해야 한다');
    });

    testWidgets('exit 애니메이션 중 그룹이 사라져도 아래 화면을 닫지 않는다',
        (WidgetTester tester) async {
      // 이 분기는 빌드마다 post-frame 콜백을 새로 등록해 **라우트가 닫히는 도중에도**
      // 다시 돈다. 그런데 `_RouteEntry.handlePop`은 `didPop`보다 먼저 상태를 `popping`
      // 으로 옮기므로, exit 애니메이션이 도는 동안 `context.mounted`는 참인데
      // `isActive`는 거짓이다. 그때 pop하면 **호출부가 대신 닫힌다.**
      //
      // 이론적 레이스가 아니다 — 방장 소유권 이전(`_onLeave`)이 `navigator.pop()`을
      // 부른 직후 스트림이 `group == null`을 흘리는 순서가 정확히 이것이고, Firestore
      // 스냅샷 지연은 300ms 애니메이션 창 안에 들어온다.
      //
      // ⚠️ **지금 코드에서는 `!route.isActive` 가드를 지워도 이 테스트가 통과한다**
      // (뮤테이션으로 확인). 맨 `maybePop()`은 이 라우트가 popping이면 호출부(=`isFirst`)
      // 에 걸려 bubble로 끝나기 때문이다 — 즉 가드는 **현재 스택 깊이에서만** 무해하다.
      // 이 테스트가 잡는 것은 `popUntil` 같은 **무제한 pop을 다시 들여오는 변경**이다
      // (가드 없이 그것을 넣으면 여기서 `HOST=0`으로 깨진다). 가드 자체는 스택이
      // 깊어질 때를 대비한 보험이고, 그 축은 아직 어떤 테스트도 재지 않는다.
      final StreamController<List<Group>> groups =
          StreamController<List<Group>>.broadcast();
      addTearDown(groups.close);
      repo
        ..groupsOverride = <Group>[groupFixture(iAmOwner: true)]
        ..groupsController = groups
        ..pending = <JoinRequest>[req('a')];

      final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authRepositoryProvider.overrideWithValue(auth),
            gifticonRepositoryProvider.overrideWithValue(gifticons),
            shareRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const GroupDetailPage(groupId: 'g1'),
                    )),
                    child: const Text('상세 열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('상세 열기'));
      await tester.pumpAndSettle();
      expect(find.byType(GroupDetailPage), findsOneWidget);

      // 뒤로가기 — 애니메이션이 도는 동안 라우트는 mounted지만 isActive는 거짓이다.
      navKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 그 창 안에 그룹 소멸이 도착한다.
      groups.add(const <Group>[]);
      await tester.pumpAndSettle();

      expect(find.byType(GroupDetailPage), findsNothing);
      expect(find.text('상세 열기'), findsOneWidget,
          reason: '호출부까지 pop되면 루트 Navigator가 비어 검은 화면이 된다');
    });
  });
}
