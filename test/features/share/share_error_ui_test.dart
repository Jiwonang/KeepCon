/// share 화면의 **스트림 에러 표시 / 수동 재시도** 위젯 테스트.
///
/// 배경(크로스페이지 주의점 #13): 모든 소비 지점이 `valueOrNull ?? []`로 폴딩하므로
/// 에러가 "빈 상태"와 구분되지 않았다. 이 파일은 그 폴딩을 유지한 채 얹은 에러 UI가
/// 실제로 동작하는지를 고정한다:
///
/// - (a) **알림 읽음 가드** — 에러 상태로 진입하면 `markNotificationsRead`가 호출되지
///   않아 `readAt`이 그대로고(알림 보존), 스트림이 회복되어 목록이 보인 뒤에 1회 갱신된다.
/// - (b) **배너 + 재시도** — 에러면 배너가 뜨고, '다시 시도'를 누르면 원천 provider가
///   invalidate되어 **재구독**된다(구독 카운터로 확인). 자동 재시도는 없다.
/// - (c) **공유 상세: 에러 vs 항목 없음** — 조회 실패는 배너, 진짜 없음은 '찾을 수 없어요'.
///
/// 계측을 위해 [ShareRepository]를 [_FlakyShareRepository]로 override 한다. 읽음 시각은
/// 실제 계약 구현([InMemoryShareRepository])에 위임해, 테스트가 "호출됐는가"가 아니라
/// **실제 readAt이 갱신됐는가**를 단언하도록 했다. 세션은 계약 mock
/// [InMemoryAuthRepository](기본 = 로그인 상태)를 그대로 쓴다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/pages/group_notifications_page.dart';
import 'package:keepcon/features/share/pages/shared_gifticon_detail_page.dart';
import 'package:keepcon/features/share/pages/usage_log_page.dart';
import 'package:keepcon/features/share/share_page.dart';
import 'package:keepcon/features/share/widgets/share_error_banner.dart';
import 'package:keepcon/features/share/widgets/share_sheets.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// 스트림별로 "실패/성공"을 토글할 수 있고 **구독 횟수를 세는** 테스트용 [ShareRepository].
///
/// 재시도의 정의가 "원천 스트림 재구독"이므로, 단언 대상은 구독 카운터다. 읽음 상태
/// (`watchNotificationsReadAt`/`markNotificationsRead`)만 실제 계약 구현에 위임한다.
/// 그 밖의 메서드는 [noSuchMethod]로 막아, 예상 밖 호출이 조용히 통과하지 않게 한다.
class _FlakyShareRepository implements ShareRepository {
  _FlakyShareRepository({required this.inner, required this.groups});

  /// 읽음 상태 위임 대상(계약 구현).
  final InMemoryShareRepository inner;

  /// `watchGroups`가 방출할 그룹 목록.
  final List<Group> groups;

  /// `watchSharedGifticons`가 방출할 공유 항목(그룹 id별).
  final Map<String, List<SharedGifticon>> sharedByGroup =
      <String, List<SharedGifticon>>{};

  bool notificationsFail = false;
  bool sharedFail = false;
  bool usageLogsFail = false;

  /// 내 그룹 목록(계약 정본이 구독하는 스트림)을 실패시킨다.
  /// 이 에러는 페이지에서 재시도할 수 없는 유일한 계층이다(#13).
  bool groupsFail = false;

  /// 그룹 목록을 **한 번 방출한 뒤** 실패시킨다 — Riverpod이 `copyWithPrevious`로
  /// 이전 값을 보존하는 "순단" 상태(hasError=true && valueOrNull=목록) 재현용.
  bool groupsFailAfterData = false;

  /// 그룹 목록 스트림을 첫 방출 없이 매달아 둔다(콜드 로딩 상태 재현용).
  bool groupsHang = false;

  /// 알림 스트림을 첫 방출 없이 매달아 둔다(콜드 로딩 상태 재현용).
  bool notificationsHang = false;

  /// 특정 그룹의 공유 스트림만 실패시킨다(스코프 재시도 검증용 — [sharedFail]은 전체).
  final Set<String> sharedFailGroups = <String>{};

  /// [markNotificationsRead]를 비-[StateError] 예외로 실패시킨다
  /// (실서버 Firestore 쓰기 실패 계열 재현용).
  bool markReadFails = false;

  int notificationSubscriptions = 0;
  int sharedSubscriptions = 0;
  int usageLogSubscriptions = 0;

  /// 그룹 id별 공유 스트림 구독 횟수(스코프 재시도 단언용).
  final Map<String, int> sharedSubscriptionsByGroup = <String, int>{};

  static Stream<List<Group>> _dataThenError(List<Group> data) async* {
    yield data;
    throw StateError('boom');
  }

  @override
  Stream<List<Group>> watchGroups(String userId) {
    if (groupsHang) return StreamController<List<Group>>().stream;
    if (groupsFail) return Stream<List<Group>>.error(StateError('boom'));
    if (groupsFailAfterData) return _dataThenError(groups);
    return Stream<List<Group>>.value(groups);
  }

  @override
  Stream<List<UsageLog>> watchUsageLogs(String userId) {
    usageLogSubscriptions++;
    if (usageLogsFail) {
      return Stream<List<UsageLog>>.error(StateError('boom'));
    }
    return Stream<List<UsageLog>>.value(<UsageLog>[
      UsageLog(
        id: 'l1',
        groupId: 'g1',
        sharedGifticonId: 's1',
        userId: userId,
        brand: '스타벅스',
        productName: '아메리카노',
        usedAt: DateTime.now(),
      ),
    ]);
  }

  @override
  Stream<List<GroupNotification>> watchNotifications(String userId) {
    notificationSubscriptions++;
    if (notificationsHang) {
      return StreamController<List<GroupNotification>>().stream;
    }
    if (notificationsFail) {
      return Stream<List<GroupNotification>>.error(StateError('boom'));
    }
    return Stream<List<GroupNotification>>.value(<GroupNotification>[
      GroupNotification(
        id: 'n1',
        groupId: 'g1',
        type: GroupNotificationType.registered,
        title: '새 기프티콘',
        message: '아메리카노가 공유됐어요.',
        createdAt: DateTime.now(),
      ),
    ]);
  }

  @override
  Stream<List<SharedGifticon>> watchSharedGifticons(String groupId) {
    sharedSubscriptions++;
    sharedSubscriptionsByGroup[groupId] =
        (sharedSubscriptionsByGroup[groupId] ?? 0) + 1;
    if (sharedFail || sharedFailGroups.contains(groupId)) {
      return Stream<List<SharedGifticon>>.error(StateError('boom'));
    }
    return Stream<List<SharedGifticon>>.value(
      sharedByGroup[groupId] ?? const <SharedGifticon>[],
    );
  }

  @override
  Stream<DateTime?> watchNotificationsReadAt(String userId) =>
      inner.watchNotificationsReadAt(userId);

  @override
  Future<void> markNotificationsRead() {
    if (markReadFails) {
      throw Exception('simulated write failure'); // 비-StateError 실패 계열.
    }
    return inner.markNotificationsRead();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트가 쓰지 않는 계약 메서드가 호출됐다: ${invocation.memberName}',
      );
}

/// 공유 시트(`showShareGifticonSheet`)를 여는 최소 호스트 — 시트는 함수형 API라
/// 위젯을 직접 pump할 수 없어 진입점 버튼을 둔다.
class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (BuildContext ctx) => ElevatedButton(
            onPressed: () => showShareGifticonSheet(ctx, groupId),
            child: const Text('공유 시트 열기'),
          ),
        ),
      ),
    );
  }
}

void main() {
  final String me = InMemoryAuthRepository.defaultUser.id; // 'user-1'

  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late InMemoryShareRepository inner;
  late _FlakyShareRepository repo;

  /// 방장 1명(=현재 사용자)만 있는 최소 유효 그룹(`Group`의 owner 불변식 충족).
  Group groupFixture({String id = 'g1', String name = '가족'}) => Group(
        id: id,
        name: name,
        emoji: '🏠',
        inviteCode: '123456',
        members: <GroupMember>[
          GroupMember(
            userId: me,
            displayName: InMemoryAuthRepository.defaultUser.displayName,
            avatarEmoji: '🙂',
            role: MemberRole.owner,
          ),
        ],
      );

  setUp(() {
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    inner = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      seed: false,
    );
    repo = _FlakyShareRepository(
      inner: inner,
      groups: <Group>[groupFixture()],
    );
  });

  tearDown(() {
    inner.dispose();
    gifticons.dispose();
    auth.dispose();
  });

  /// [settle]=false는 로딩(스피너 애니메이션) 상태를 검사하는 테스트용 —
  /// `pumpAndSettle`은 무한 애니메이션에서 타임아웃한다.
  Future<void> pumpPage(WidgetTester tester, Widget page,
      {bool settle = true}) async {
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
    if (settle) {
      // 세션 → 스트림 방출 → 첫 프레임 뒤 postFrameCallback까지 흘려보낸다.
      await tester.pumpAndSettle();
    } else {
      await tester.pump(); // 세션 방출.
      await tester.pump(); // 파생 재계산 프레임.
    }
  }

  Future<DateTime?> readAt() => inner.watchNotificationsReadAt(me).first;

  /// 세션이 먼저 `null`을 방출하는 상황으로 갈아끼운다
  /// (실서버 `authStateChanges()`가 복원 전 null을 먼저 내보내는 패턴).
  void useSignedOutSession() {
    inner.dispose();
    gifticons.dispose();
    auth.dispose();
    auth = InMemoryAuthRepository(initialUser: null);
    gifticons = InMemoryGifticonRepository();
    inner = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      seed: false,
    );
    repo = _FlakyShareRepository(inner: inner, groups: <Group>[groupFixture()]);
  }

  group('(a) 알림 읽음 가드 — 본 뒤에만 읽음 처리', () {
    testWidgets('스트림 에러 상태로 진입하면 readAt이 갱신되지 않는다',
        (WidgetTester tester) async {
      repo.notificationsFail = true;

      await pumpPage(tester, const GroupNotificationsPage());

      // 목록을 한 줄도 못 본 상태 — 읽음 처리가 일어나면 회복 후 알림이 유실된다.
      expect(await readAt(), isNull, reason: '에러 중 진입은 읽음 처리를 보류해야 한다(알림 보존)');
      // "알림이 없어요"로 존재를 은폐하지도 않는다.
      expect(find.text('알림이 없어요.'), findsNothing);
    });

    testWidgets('스트림이 회복되어 목록이 보이면 그때 1회 읽음 처리된다', (WidgetTester tester) async {
      repo.notificationsFail = true;
      await pumpPage(tester, const GroupNotificationsPage());
      expect(await readAt(), isNull);

      // 사용자가 '다시 시도'를 눌러 재구독 → 이번엔 성공 방출.
      repo.notificationsFail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('새 기프티콘'), findsOneWidget, reason: '목록이 실제로 보여야 한다');
      final DateTime? after = await readAt();
      expect(after, isNotNull, reason: '데이터가 도착해 목록을 본 뒤에는 읽음 처리한다');

      // 이후 재빌드가 있어도 중복 호출하지 않는다(1회 가드).
      await tester.pump();
      expect(await readAt(), after);
    });

    testWidgets('미로그인 AsyncData(빈 목록)가 1회 가드를 소모하지 않는다',
        (WidgetTester tester) async {
      // 세션이 data(null)이면 notificationsProvider는 AsyncData(<GroupNotification>[])다.
      // 이것도 AsyncData라 가드를 통과하지만 markNotificationsRead는 StateError로
      // 실패한다 — 이때 가드를 그대로 소모해 버리면 진짜 세션이 도착해 목록을 보여줘도
      // 읽음 처리가 영영 일어나지 않는다(뱃지 잔존).
      useSignedOutSession();

      await pumpPage(tester, const GroupNotificationsPage());
      expect(await readAt(), isNull);

      // 세션이 뒤늦게 복원되면 그때 목록을 보고 읽음 처리해야 한다.
      await auth.signIn(
        email: InMemoryAuthRepository.defaultUser.email,
        password: InMemoryAuthRepository.defaultPassword,
      );
      await tester.pumpAndSettle();

      expect(find.text('새 기프티콘'), findsOneWidget);
      expect(await readAt(), isNotNull, reason: '실패한 읽음 처리는 가드를 소모하지 않아야 한다');
    });

    testWidgets('정상 진입(데이터 방출)이면 기존대로 읽음 처리된다', (WidgetTester tester) async {
      repo.notificationsFail = false;

      await pumpPage(tester, const GroupNotificationsPage());

      expect(find.text('새 기프티콘'), findsOneWidget);
      expect(await readAt(), isNotNull, reason: '정상 경로의 기존 동작은 그대로다');
    });

    testWidgets('비-StateError 쓰기 실패도 가드를 되돌린다(unhandled로 새지 않는다)',
        (WidgetTester tester) async {
      // 실서버(Firestore) markNotificationsRead는 네트워크·권한 실패 시 StateError가
      // 아닌 예외를 던진다 — 이 경로가 unhandled async error로 새거나 가드를 소모한
      // 채 남으면 안 된다(catch가 StateError 전용이면 이 테스트 자체가 미포획 예외로
      // 실패한다 — 회귀 고정).
      repo.markReadFails = true;

      await pumpPage(tester, const GroupNotificationsPage());
      expect(find.text('새 기프티콘'), findsOneWidget);
      expect(await readAt(), isNull, reason: '쓰기 실패면 읽음 처리가 안 된 것이다');

      // 가드가 복원됐으므로 다음 성공 방출(재로그인)에서 재시도된다.
      repo.markReadFails = false;
      await auth.signOut();
      await tester.pumpAndSettle();
      await auth.signIn(
        email: InMemoryAuthRepository.defaultUser.email,
        password: InMemoryAuthRepository.defaultPassword,
      );
      await tester.pumpAndSettle();

      expect(await readAt(), isNotNull, reason: '실패한 읽음 처리는 가드를 소모하지 않아야 한다');
    });
  });

  group('(b) 배너 표시 + 재시도 = 원천 재구독', () {
    testWidgets('알림 에러면 배너가 뜨고, 자동 재시도는 하지 않는다', (WidgetTester tester) async {
      repo.notificationsFail = true;

      await pumpPage(tester, const GroupNotificationsPage());

      expect(find.byType(ShareErrorBanner), findsOneWidget);
      expect(find.text('알림을 불러오지 못했어요.'), findsOneWidget);
      expect(repo.notificationSubscriptions, 1,
          reason: '자동 재시도 금지 — 사용자가 누르기 전에는 재구독하지 않는다(retry storm 방어)');

      // 프레임이 더 흘러도 재구독이 없다.
      await tester.pump(const Duration(seconds: 1));
      expect(repo.notificationSubscriptions, 1);
    });

    testWidgets('재시도를 누르면 알림 스트림을 재구독하고 배너가 사라진다', (WidgetTester tester) async {
      repo.notificationsFail = true;
      await pumpPage(tester, const GroupNotificationsPage());
      expect(repo.notificationSubscriptions, 1);

      repo.notificationsFail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.notificationSubscriptions, 2,
          reason: '원천 provider가 invalidate돼야 한다');
      expect(find.byType(ShareErrorBanner), findsNothing);
      expect(find.text('새 기프티콘'), findsOneWidget);
    });

    testWidgets('공유 기프티콘 재시도도 원천(sharedGifticonsProvider)을 재구독한다',
        (WidgetTester tester) async {
      repo.sharedFail = true;

      await pumpPage(tester, const SharedGifticonDetailPage(itemId: 'missing'));
      expect(find.byType(ShareErrorBanner), findsOneWidget);
      final int before = repo.sharedSubscriptions;
      expect(before, greaterThanOrEqualTo(1));

      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.sharedSubscriptions, greaterThan(before));
    });
  });

  group('(b-2) 나머지 재시도 진입점 실증', () {
    testWidgets('사용 이력 배너의 재시도가 usageLogs 스트림을 재구독한다',
        (WidgetTester tester) async {
      repo.usageLogsFail = true;

      await pumpPage(tester, const UsageLogPage());

      expect(find.text('사용 이력을 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('아직 사용 이력이 없어요.'), findsNothing,
          reason: '감사 화면에서 실패를 "이력 없음"으로 위장하면 안 된다');
      final int before = repo.usageLogSubscriptions;

      repo.usageLogsFail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.usageLogSubscriptions, greaterThan(before));
      expect(find.byType(ShareErrorBanner), findsNothing);
    });

    testWidgets('공유 시트 배너의 재시도가 후보 원천을 재구독한다', (WidgetTester tester) async {
      repo.sharedFail = true;

      await pumpPage(tester, const _SheetHost(groupId: 'g1'));
      await tester.tap(find.text('공유 시트 열기'));
      await tester.pumpAndSettle();

      expect(find.text('공유할 기프티콘 목록을 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('공유할 수 있는 기프티콘이 없어요.'), findsNothing);
      final int before = repo.sharedSubscriptions;

      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.sharedSubscriptions, greaterThan(before),
          reason: 'retryShareCandidates가 공유 목록 원천을 되살려야 한다');
    });
  });

  group('재시도 불가 원인(내 그룹 목록)일 때는 버튼을 감춘다', () {
    testWidgets('공유 상세 — 배너는 뜨되 "다시 시도" 버튼이 없다', (WidgetTester tester) async {
      repo.groupsFail = true;

      await pumpPage(tester, const SharedGifticonDetailPage(itemId: 'missing'));

      expect(find.byType(ShareErrorBanner), findsOneWidget);
      expect(find.text('기프티콘을 찾을 수 없어요.'), findsNothing);
      expect(find.text('다시 시도'), findsNothing,
          reason: 'myGroups 에러는 페이지에서 되살릴 수 없다 — 동작하지 않는 버튼을 두지 않는다');
    });

    testWidgets('공유 시트 — 배너는 뜨되 "다시 시도" 버튼이 없다', (WidgetTester tester) async {
      repo.groupsFail = true;

      await pumpPage(tester, const _SheetHost(groupId: 'g1'));
      await tester.tap(find.text('공유 시트 열기'));
      await tester.pumpAndSettle();

      expect(find.byType(ShareErrorBanner), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);
    });

    testWidgets('사용 이력 — 그룹 목록 사용 불가를 무음으로 넘기지 않는다(필터 소실 안내)',
        (WidgetTester tester) async {
      repo.groupsFail = true;

      await pumpPage(tester, const UsageLogPage());

      expect(find.textContaining('그룹 목록을 불러오지 못했어요.'), findsOneWidget,
          reason: '그룹 필터가 사라지고 전체 폴백된 원인을 감사 화면이 알려야 한다');
      expect(find.text('다시 시도'), findsNothing,
          reason: '그룹 목록은 재시도 불가 원천이다(#13)');
    });
  });

  group('share 메인 — 그룹 목록 에러가 다른 섹션의 false-empty로 새지 않는다', () {
    testWidgets('그룹 에러 시 "공유된 기프티콘이 없어요"를 띄우지 않는다',
        (WidgetTester tester) async {
      repo.groupsFail = true;

      await pumpPage(tester, const SharePage());

      // 그룹 섹션은 실패를 표시하고(재시도 불가라 버튼 없음),
      expect(find.textContaining('그룹 목록을 불러오지 못했어요.'), findsOneWidget);
      expect(
          find.text('아직 참여한 그룹이 없어요.\n그룹을 만들거나 초대코드로 참여해 보세요.'), findsNothing);
      // 공유 섹션도 "없음"으로 위장하지 않는다(그룹이 0개라 순회가 없어
      // sharedHaveError가 false여도 빈 안내가 나오면 안 된다 — 회귀 고정).
      expect(find.text('공유된 기프티콘이 없어요.'), findsNothing);
    });

    testWidgets('그룹이 정상이고 공유가 비어 있으면 기존 빈 안내를 유지한다',
        (WidgetTester tester) async {
      repo.groupsFail = false; // 그룹 1개, 공유 0개.

      await pumpPage(tester, const SharePage());

      expect(find.text('공유된 기프티콘이 없어요.'), findsOneWidget);
      expect(find.byType(ShareErrorBanner), findsNothing);
    });
  });

  group('그룹 순단(이전 값 보존) — 배너 영구화·재시도 은닉 금지', () {
    testWidgets('보존된 그룹 목록은 유지되고 그룹 배너는 뜨지 않으며, 공유 에러의 재시도 버튼도 가려지지 않는다',
        (WidgetTester tester) async {
      // 데이터 방출 후 에러 → copyWithPrevious 보존(hasError=true, 목록은 그대로).
      // 이때 그룹 배너를 띄우면 재시도 훅이 없어 앱 재시작 전까지 영구 표시되고,
      // "값 없는 에러" 판정을 쓰는 상세·시트의 재시도 버튼까지 부당하게 사라진다.
      repo.groupsFailAfterData = true;
      repo.sharedFail = true; // 함께 발생한, 재시도 가능한 공유 스트림 에러.

      await pumpPage(tester, const SharePage());

      expect(find.text('가족'), findsOneWidget, reason: '보존된 그룹 목록은 계속 렌더된다');
      expect(find.textContaining('그룹 목록을 불러오지 못했어요.'), findsNothing,
          reason: '해소 경로 없는 배너를 멀쩡한 목록 위에 영구 표시하지 않는다');
      expect(find.text('공유 기프티콘을 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget,
          reason: '그룹 순단이 공유 스트림 에러의 재시도 경로를 가리면 안 된다');
    });
  });

  group('스코프 재시도 — 실패한 원천만 재구독한다', () {
    testWidgets('전-그룹 재시도가 실패한 그룹 인스턴스만 재구독한다', (WidgetTester tester) async {
      repo = _FlakyShareRepository(
        inner: inner,
        groups: <Group>[groupFixture(), groupFixture(id: 'g2', name: '회사')],
      );
      repo.sharedFailGroups.add('g1');

      await pumpPage(tester, const SharePage());
      expect(find.text('공유 기프티콘을 불러오지 못했어요.'), findsOneWidget);
      final int g1Before = repo.sharedSubscriptionsByGroup['g1'] ?? 0;
      final int g2Before = repo.sharedSubscriptionsByGroup['g2'] ?? 0;

      repo.sharedFailGroups.clear();
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.sharedSubscriptionsByGroup['g1'], g1Before + 1,
          reason: '실패한 그룹 스트림은 재구독된다');
      expect(repo.sharedSubscriptionsByGroup['g2'], g2Before,
          reason: '멀쩡한 그룹 스트림은 재구독하지 않는다(문서 읽기·과금 절약)');
    });
  });

  group('콜드 로딩 — 첫 방출 전을 "없음"으로 위장하지 않는다', () {
    testWidgets('알림 화면은 로딩 중 스피너를 보여 준다', (WidgetTester tester) async {
      repo.notificationsHang = true;

      await pumpPage(tester, const GroupNotificationsPage(), settle: false);

      expect(find.text('알림이 없어요.'), findsNothing,
          reason: '아직 모르는 상태를 확정 부재로 표기하면 안 된다');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('share 메인은 로딩 중 빈 안내를 띄우지 않는다', (WidgetTester tester) async {
      repo.groupsHang = true;

      await pumpPage(tester, const SharePage());

      expect(
        find.text('아직 참여한 그룹이 없어요.\n그룹을 만들거나 초대코드로 참여해 보세요.'),
        findsNothing,
      );
      expect(find.text('공유된 기프티콘이 없어요.'), findsNothing);
      expect(find.byType(ShareErrorBanner), findsNothing);
    });
  });

  group('(c) 공유 상세 — 에러와 "항목 없음" 구분', () {
    testWidgets('조회 실패면 배너를 띄우고 "찾을 수 없어요"로 확정하지 않는다',
        (WidgetTester tester) async {
      repo.sharedFail = true;

      await pumpPage(tester, const SharedGifticonDetailPage(itemId: 'missing'));

      expect(find.text('공유 기프티콘 정보를 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('기프티콘을 찾을 수 없어요.'), findsNothing,
          reason: '공유취소(확정 소멸)와 조회 실패를 혼동시키면 안 된다');
    });

    testWidgets('스트림이 정상인데 항목이 없으면 기존 "찾을 수 없어요"를 유지한다',
        (WidgetTester tester) async {
      repo.sharedFail = false; // 정상 방출, 다만 목록이 비어 있다.

      await pumpPage(tester, const SharedGifticonDetailPage(itemId: 'missing'));

      expect(find.text('기프티콘을 찾을 수 없어요.'), findsOneWidget);
      expect(find.byType(ShareErrorBanner), findsNothing);
    });
  });
}
