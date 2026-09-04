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
///
/// ℹ️ **위치를 `test/shared/widgets/`로 옮기지 않는 이유.** 배너가 `lib/shared`로 승격됐지만
/// 이 파일이 고정하는 것은 위젯 자체가 아니라 **share 화면들의 에러 UI 배선**이다 — (a)(b)(c)
/// 전부 share 페이지를 pump해 provider 폴딩·재구독·읽음 가드를 검증하고, 위젯 단독 케이스는
/// '배너 위젯 규약' 그룹 하나뿐이다. 그 한 그룹 때문에 파일을 옮기면 나머지가 소유자에서
/// 멀어진다. 위젯 단독 계약(접미 문구·버튼 유무)을 소비자와 무관하게 고정할 필요가 커지면
/// 그때 그 그룹만 `test/shared/widgets/`로 분리한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/pages/notification_center_page.dart';
import 'package:keepcon/features/share/pages/shared_gifticon_detail_page.dart';
import 'package:keepcon/features/share/pages/usage_log_page.dart';
import 'package:keepcon/features/share/share_page.dart';
import 'package:keepcon/features/share/widgets/share_sheets.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/session_provider.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';
import 'package:keepcon/shared/widgets/inline_error_banner.dart';

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
  /// v2.6부터 이 계층도 계약 훅 `retryMyGroups`로 되살릴 수 있다(#13).
  bool groupsFail = false;

  /// `watchGroups` 구독 횟수(그룹 축 재시도 = 재구독 단언용).
  int groupSubscriptions = 0;

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

  /// 참여 요청 축은 이 파일의 관심 밖이지만 share 메인이 **항상** 이 스트림을
  /// watch한다 — noSuchMethod에 맡기면 모든 테스트에서 이 축이 에러가 되어, 참여
  /// 요청 배너의 '다시 시도'가 다른 축의 배너 단언(개수·유무)에 끼어든다. 건강한
  /// 빈 스트림으로 고정한다(에러 배선 자체는 join_request_ui_test가 고정한다).
  @override
  Stream<List<JoinRequest>> watchMyJoinRequests(String userId) =>
      Stream<List<JoinRequest>>.value(const <JoinRequest>[]);

  @override
  Stream<List<Group>> watchGroups(String userId) {
    groupSubscriptions++;
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

/// 세션 스트림을 **"데이터 방출 뒤 에러"(순단)** 로 만드는 [AuthRepository] 래퍼.
///
/// Riverpod이 `copyWithPrevious`로 이전 user를 보존하는 상태(hasError=true인데
/// `valueOrNull`은 그 user)를 재현한다 — share 파생들이 정본 [myGroupsProvider]와
/// **같은 방향**으로 반응하는지(목록 유지)를 고정하기 위한 계측이다. 세션 이외의 계약
/// 메서드는 전부 실제 구현([inner])에 위임한다.
class _SessionBlipAuthRepository implements AuthRepository {
  _SessionBlipAuthRepository(this.inner);

  final InMemoryAuthRepository inner;

  @override
  Stream<User?> watchCurrentUser() async* {
    yield inner.currentUser; // 확정 방출(= 이후 보존될 값).
    throw StateError('session blip'); // 순단.
  }

  @override
  User? get currentUser => inner.currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('이 테스트가 쓰지 않는 계약 메서드: ${invocation.memberName}');
}

/// 세션 스트림을 **"값 없이 에러 → 재시도하면 응답 없음(행)"** 으로 만드는 래퍼.
///
/// 재시도(invalidate) 직후의 리프레시 상태(로딩 + 이전 에러 보존, 값 없음)를 화면에
/// 고정해, 배너가 사라졌다 재등장하는 왕복 깜빡임이 없는지(정본 [foldSessionUser]의
/// 에러-우선 분기)를 검증하기 위한 계측이다.
class _ErrorThenHangAuthRepository implements AuthRepository {
  int watchCalls = 0;

  @override
  Stream<User?> watchCurrentUser() {
    watchCalls++;
    if (watchCalls == 1) {
      return Stream<User?>.error(StateError('session down'));
    }
    return StreamController<User?>().stream; // 재시도 결과 미정 상태를 유지.
  }

  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('이 테스트가 쓰지 않는 계약 메서드: ${invocation.memberName}');
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

  /// `authRepositoryProvider`에 주입할 세션 구현. 기본은 계약 mock([auth])이고,
  /// 순단 재현 테스트만 [_SessionBlipAuthRepository]로 갈아끼운다.
  late AuthRepository sessionAuth;

  /// 방장 1명(=현재 사용자)만 있는 최소 유효 그룹(`Group`의 owner 불변식 충족).
  Group groupFixture({String id = 'g1', String name = '가족'}) => Group(
        id: id,
        name: name,
        emoji: '🏠',
        inviteToken: '123456',
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
    sessionAuth = auth;
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
          authRepositoryProvider.overrideWithValue(sessionAuth),
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
    sessionAuth = auth;
  }

  group('(a) 알림 읽음 가드 — 본 뒤에만 읽음 처리', () {
    testWidgets('스트림 에러 상태로 진입하면 readAt이 갱신되지 않는다',
        (WidgetTester tester) async {
      repo.notificationsFail = true;

      await pumpPage(tester, const NotificationCenterPage());

      // 목록을 한 줄도 못 본 상태 — 읽음 처리가 일어나면 회복 후 알림이 유실된다.
      expect(await readAt(), isNull, reason: '에러 중 진입은 읽음 처리를 보류해야 한다(알림 보존)');
      // "알림이 없어요"로 존재를 은폐하지도 않는다.
      expect(find.text('알림이 없어요.'), findsNothing);
    });

    testWidgets('스트림이 회복되어 목록이 보이면 그때 1회 읽음 처리된다', (WidgetTester tester) async {
      repo.notificationsFail = true;
      await pumpPage(tester, const NotificationCenterPage());
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

      await pumpPage(tester, const NotificationCenterPage());
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

      await pumpPage(tester, const NotificationCenterPage());

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

      await pumpPage(tester, const NotificationCenterPage());
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

      await pumpPage(tester, const NotificationCenterPage());

      expect(find.byType(InlineErrorBanner), findsOneWidget);
      expect(find.text('알림을 불러오지 못했어요.'), findsOneWidget);
      expect(repo.notificationSubscriptions, 1,
          reason: '자동 재시도 금지 — 사용자가 누르기 전에는 재구독하지 않는다(retry storm 방어)');

      // 프레임이 더 흘러도 재구독이 없다.
      await tester.pump(const Duration(seconds: 1));
      expect(repo.notificationSubscriptions, 1);
    });

    testWidgets('재시도를 누르면 알림 스트림을 재구독하고 배너가 사라진다', (WidgetTester tester) async {
      repo.notificationsFail = true;
      await pumpPage(tester, const NotificationCenterPage());
      expect(repo.notificationSubscriptions, 1);

      repo.notificationsFail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.notificationSubscriptions, 2,
          reason: '원천 provider가 invalidate돼야 한다');
      expect(find.byType(InlineErrorBanner), findsNothing);
      expect(find.text('새 기프티콘'), findsOneWidget);
    });

    testWidgets('공유 기프티콘 재시도도 원천(sharedGifticonsProvider)을 재구독한다',
        (WidgetTester tester) async {
      repo.sharedFail = true;

      await pumpPage(tester, const SharedGifticonDetailPage(itemId: 'missing'));
      expect(find.byType(InlineErrorBanner), findsOneWidget);
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
      expect(find.byType(InlineErrorBanner), findsNothing);
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

  // v2.6 이전에는 이 4곳이 "재시도 불가"였다 — 그룹 목록 에러가 계약 정본의 private
  // 체인에 캐시돼 페이지에서 되살릴 수 없었고(#13), 배너들은 `onRetry: null`로 버튼을
  // 감췄다. 계약이 `retryMyGroups`(세션+그룹 중 **에러인 계층만** 재구독)를 제공하면서
  // 그 강등이 전부 사라졌다 — 아래 그룹이 "버튼이 없다"는 옛 단언을 대체한다.
  group('내 그룹 목록 에러도 재시도할 수 있다(계약 훅 retryMyGroups)', () {
    testWidgets('share 메인 — 그룹 배너의 재시도가 watchGroups를 재구독하고 목록이 돌아온다',
        (WidgetTester tester) async {
      repo.groupsFail = true;

      await pumpPage(tester, const SharePage());

      expect(find.textContaining('그룹 목록을 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget,
          reason: '되살릴 경로가 생겼으므로 그룹 배너도 버튼을 갖는다');
      final int before = repo.groupSubscriptions;
      expect(before, greaterThanOrEqualTo(1));

      repo.groupsFail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.groupSubscriptions, greaterThan(before),
          reason: '정본의 그룹 스트림 인스턴스가 재구독돼야 한다');
      expect(find.byType(InlineErrorBanner), findsNothing);
      expect(find.text('가족'), findsOneWidget, reason: '회복되면 그룹 목록이 표시된다');
    });

    testWidgets('공유 상세 — 버튼이 있고, 회복되면 배너 대신 확정 안내가 뜬다',
        (WidgetTester tester) async {
      repo.groupsFail = true;

      await pumpPage(tester, const SharedGifticonDetailPage(itemId: 'missing'));

      expect(find.byType(InlineErrorBanner), findsOneWidget);
      expect(find.text('기프티콘을 찾을 수 없어요.'), findsNothing);
      expect(find.text('다시 시도'), findsOneWidget);
      final int before = repo.groupSubscriptions;

      repo.groupsFail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.groupSubscriptions, greaterThan(before));
      expect(find.byType(InlineErrorBanner), findsNothing);
      // 조회 경로가 살아났고 항목은 실제로 없다 → 비로소 "없음"을 확정할 수 있다.
      expect(find.text('기프티콘을 찾을 수 없어요.'), findsOneWidget);
    });

    testWidgets('공유 시트 — 버튼이 있고, 누르면 그룹 스트림을 재구독한다',
        (WidgetTester tester) async {
      repo.groupsFail = true;

      await pumpPage(tester, const _SheetHost(groupId: 'g1'));
      await tester.tap(find.text('공유 시트 열기'));
      await tester.pumpAndSettle();

      expect(find.byType(InlineErrorBanner), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      final int before = repo.groupSubscriptions;

      repo.groupsFail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.groupSubscriptions, greaterThan(before),
          reason: 'retryShareCandidates가 그룹 축(내 그룹 목록)도 되살려야 한다');
      expect(find.byType(InlineErrorBanner), findsNothing);
    });

    testWidgets('사용 이력 — 그룹 배너 재시도로 필터 칩이 돌아온다', (WidgetTester tester) async {
      repo.groupsFail = true;

      await pumpPage(tester, const UsageLogPage());

      expect(find.textContaining('그룹 목록을 불러오지 못했어요.'), findsOneWidget,
          reason: '그룹 필터가 사라지고 전체 폴백된 원인을 감사 화면이 알려야 한다');
      expect(find.text('다시 시도'), findsOneWidget,
          reason: '이력 스트림은 정상이므로 그룹 배너의 버튼 하나뿐이다');
      final int before = repo.groupSubscriptions;

      repo.groupsFail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.groupSubscriptions, greaterThan(before));
      expect(find.byType(InlineErrorBanner), findsNothing);
      expect(find.text('가족'), findsOneWidget, reason: '그룹 필터 칩이 복구된다');
    });

    testWidgets('멀쩡한 그룹 스트림은 다른 축의 재시도로 재구독되지 않는다',
        (WidgetTester tester) async {
      // 스코프 원칙(에러인 계층만) — 공유 스트림만 실패한 상황에서 상세의 재시도가
      // 정상인 그룹 스트림까지 되살리면 문서 읽기·과금이 늘고 화면이 깜빡인다.
      repo.sharedFail = true;

      await pumpPage(tester, const SharedGifticonDetailPage(itemId: 'missing'));
      final int groupsBefore = repo.groupSubscriptions;
      final int sharedBefore = repo.sharedSubscriptions;

      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.sharedSubscriptions, greaterThan(sharedBefore));
      expect(repo.groupSubscriptions, groupsBefore,
          reason: '에러가 아닌 그룹 스트림은 건드리지 않는다');
    });
  });

  // QA [medium 1] 회귀 고정. 세션이 값을 방출한 뒤 순단하면 Riverpod은
  // `copyWithPrevious`로 이전 user를 보존한다(hasError=true, valueOrNull=user).
  // 계약 정본 `myGroupsProvider`는 그 보존 user로 그룹 스트림을 계속 반환하는데,
  // share의 세 파생(`usageLogs`/`notifications`/`shareableGifticons`)은 `.when`으로
  // 분기해 error 분기를 타는 바람에 **같은 순단에 정반대로** 목록을 버렸다. 폴딩을
  // 정본과 동형(`_bySession` — `valueOrNull` 기반)으로 통일한 뒤의 동작을 고정한다.
  group('세션 순단(보존 user) — 파생이 정본과 같은 방향으로 반응한다', () {
    testWidgets('share 메인: 그룹도 사용 이력도 유지되고 배너가 없다',
        (WidgetTester tester) async {
      sessionAuth = _SessionBlipAuthRepository(auth);

      await pumpPage(tester, const SharePage());

      // 양성 대조(positive control): 순단이 실제로 재현됐는지 먼저 확인한다 —
      // 이 단언이 없으면 아래 '배너 없음'류 단언은 완전히 건강한 세션에서도
      // 통과하는 공허한 테스트가 된다(blip 배선이 끊겨도 영원히 green).
      final ProviderContainer container =
          ProviderScope.containerOf(tester.element(find.byType(SharePage)));
      expect(container.read(sessionUserProvider).hasError, isTrue,
          reason: '세션이 실제로 순단(에러) 상태여야 한다');
      expect(container.read(sessionUserProvider).valueOrNull, isNotNull,
          reason: '이전 user가 보존된 순단이어야 한다');

      expect(find.text('가족'), findsOneWidget, reason: '정본 축(그룹)은 원래 유지된다');
      // 이력 타일은 Text.rich라 textContaining으로 찾는다.
      expect(find.textContaining('아메리카노'), findsWidgets,
          reason: '같은 순단에 사용 이력만 사라지는 비대칭이 없어야 한다');
      expect(find.text('사용 이력이 없어요.'), findsNothing);
      expect(find.byType(InlineErrorBanner), findsNothing,
          reason: '보존된 값으로 계속 표시 중이므로 실패를 알릴 이유가 없다');
    });

    testWidgets('알림 화면: 보고 있던 목록이 사라지지 않는다', (WidgetTester tester) async {
      sessionAuth = _SessionBlipAuthRepository(auth);

      await pumpPage(tester, const NotificationCenterPage());

      // 양성 대조 — 순단이 실제로 재현된 상태에서의 단언인지 확인.
      final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(NotificationCenterPage)));
      expect(container.read(sessionUserProvider).hasError, isTrue);

      expect(find.text('새 기프티콘'), findsOneWidget);
      expect(find.byType(InlineErrorBanner), findsNothing);
      expect(find.text('알림이 없어요.'), findsNothing);
    });

    testWidgets('공유 시트: 세션 순단만으로 배너가 뜨지 않는다', (WidgetTester tester) async {
      // shareCandidatesHaveErrorProvider가 shareableGifticons의 에러를 포함하므로,
      // 세션 순단이 곧바로 시트 배너로 새던 경로(QA [medium 1] ③).
      sessionAuth = _SessionBlipAuthRepository(auth);

      await pumpPage(tester, const _SheetHost(groupId: 'g1'));
      await tester.tap(find.text('공유 시트 열기'));
      await tester.pumpAndSettle();

      // 양성 대조 — 순단이 실제로 재현된 상태에서의 단언인지 확인.
      final ProviderContainer container =
          ProviderScope.containerOf(tester.element(find.byType(_SheetHost)));
      expect(container.read(sessionUserProvider).hasError, isTrue);

      expect(find.byType(InlineErrorBanner), findsNothing);
      expect(find.text('공유할 수 있는 기프티콘이 없어요.'), findsOneWidget,
          reason: '후보 계산은 보존 user로 계속되고, 실제로 후보가 0개다');
    });

    testWidgets('값 없는 세션 에러 — 재시도 응답이 오기 전까지 배너가 유지된다(왕복 깜빡임 금지)',
        (WidgetTester tester) async {
      // invalidate(refresh)는 이전 에러를 보존한 로딩 상태를 만든다. 폴딩이 로딩을
      // 에러보다 먼저 보면 재시도를 누르는 순간 배너가 사라졌다(스피너/빈 화면) 실패
      // 시 재등장하는 왕복이 생긴다 — 정본 [foldSessionUser]의 에러-우선 분기가 구
      // `.when(skipLoadingOnRefresh: true)`처럼 배너를 유지하는지 고정한다.
      final _ErrorThenHangAuthRepository hangAuth =
          _ErrorThenHangAuthRepository();
      sessionAuth = hangAuth;

      await pumpPage(tester, const SharePage());
      expect(find.textContaining('그룹 목록을 불러오지 못했어요.'), findsOneWidget,
          reason: '값 없는 세션 에러는 그룹 축 배너로 표면화된다');

      // 그룹 배너의 '다시 시도'(목록 최상단)를 누른다 — 재시도 응답은 오지 않는다(행).
      await tester.tap(find.text('다시 시도').first);
      await tester.pump();
      await tester.pump();

      expect(hangAuth.watchCalls, 2, reason: '재시도가 실제로 세션을 재구독해야 한다');
      expect(find.textContaining('그룹 목록을 불러오지 못했어요.'), findsOneWidget,
          reason: '재시도 결과가 오기 전에 배너가 사라지는 왕복이 없어야 한다');
    });
  });

  group('배너 위젯 규약 — onRetry가 null인 사이트는 share에 더 없다(규약은 휴면 유지)', () {
    testWidgets('null이면 버튼 없이 복구 안내 접미가 붙는다', (WidgetTester tester) async {
      // share의 모든 배너가 실제 재시도를 넘기게 되어 이 분기를 타는 화면이 없어졌다.
      // 승격 대상(main·scan)에는 재시도 경로 없는 지점이 남아 있어 안전망으로 유지하며,
      // 규약이 조용히 썩지 않도록 위젯 단위로 직접 고정한다.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InlineErrorBanner(message: '문제가 생겼어요.')),
        ),
      );

      expect(find.text('다시 시도'), findsNothing);
      // 접미를 상수 보간으로 기대하면 **문구를 바꿔도 기대값이 함께 바뀌어 통과한다**
      // (뮤테이션으로 확인: 상수를 아무 문자열로 바꿔도 전 케이스 green이었다).
      // 표시 문자열은 리터럴로 고정한다.
      expect(
        find.text('문제가 생겼어요. 연결 상태를 확인한 뒤 앱을 다시 열어 주세요.'),
        findsOneWidget,
      );
      // 그리고 상수와 실제 표시가 갈라지지 않는지도 함께 못박는다 — 호출부(`lib`)는
      // 접미를 조립하지 않고 이 상수를 참조하므로, 상수가 바뀌면 화면 문구가 바뀐다.
      expect(
        InlineErrorBanner.retryUnavailableGuide,
        '연결 상태를 확인한 뒤 앱을 다시 열어 주세요.',
      );
    });
  });

  group('share 메인 — 그룹 목록 에러가 다른 섹션의 false-empty로 새지 않는다', () {
    testWidgets('그룹 에러 시 "공유된 기프티콘이 없어요"를 띄우지 않는다',
        (WidgetTester tester) async {
      repo.groupsFail = true;

      await pumpPage(tester, const SharePage());

      // 그룹 섹션은 실패를 표시하고(재시도 버튼은 위 그룹에서 따로 고정),
      expect(find.textContaining('그룹 목록을 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('아직 참여한 그룹이 없어요.\n그룹을 만들거나 받은 초대 링크로 참여를 요청해 보세요.'),
          findsNothing);
      // 공유 섹션도 "없음"으로 위장하지 않는다(그룹이 0개라 순회가 없어
      // sharedHaveError가 false여도 빈 안내가 나오면 안 된다 — 회귀 고정).
      expect(find.text('공유된 기프티콘이 없어요.'), findsNothing);
    });

    testWidgets('그룹이 정상이고 공유가 비어 있으면 기존 빈 안내를 유지한다',
        (WidgetTester tester) async {
      repo.groupsFail = false; // 그룹 1개, 공유 0개.

      await pumpPage(tester, const SharePage());

      expect(find.text('공유된 기프티콘이 없어요.'), findsOneWidget);
      expect(find.byType(InlineErrorBanner), findsNothing);
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

      await pumpPage(tester, const NotificationCenterPage(), settle: false);

      expect(find.text('알림이 없어요.'), findsNothing,
          reason: '아직 모르는 상태를 확정 부재로 표기하면 안 된다');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('share 메인은 로딩 중 빈 안내를 띄우지 않는다', (WidgetTester tester) async {
      repo.groupsHang = true;

      await pumpPage(tester, const SharePage());

      expect(
        find.text('아직 참여한 그룹이 없어요.\n그룹을 만들거나 받은 초대 링크로 참여를 요청해 보세요.'),
        findsNothing,
      );
      expect(find.text('공유된 기프티콘이 없어요.'), findsNothing);
      expect(find.byType(InlineErrorBanner), findsNothing);
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
      expect(find.byType(InlineErrorBanner), findsNothing);
    });
  });
}
