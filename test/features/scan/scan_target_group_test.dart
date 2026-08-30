/// scan — '저장할 그룹 선택' 실연동 테스트.
///
/// 검증 대상:
/// 1. 선택한 groupId가 폼 세션으로 전달되고('내 지갑'=null), reset이 그것을 비운다.
/// 2. 저장(addGifticon) 성공 후, 대상 그룹이 있으면 `ShareRepository.shareGifticon`이
///    호출되고 '내 지갑'이면 호출되지 않는다.
/// 3. 그룹 공유가 실패해도(예: 사라진 그룹) 저장은 성공으로 유지된다(부분 실패 정책).
///    반대로 **공유는 성공했는데 그룹 이름 조회만** 실패한 경우는 공유 실패가
///    아니다 — 그렇게 알리면 사용자가 성공한 공유를 다시 해서 중복이 생긴다.
/// 4. **선택 UI** — `내 지갑` 아래에 내 그룹 타일이 그려지고, 고르면 그 groupId가
///    폼 세션으로 넘어가며, 목록에서 사라진 그룹은 '내 지갑'으로 되돌아간다.
/// 5. **저장 결과 안내** — 지갑/그룹 공유가 스낵바 문구로 구분된다. 문구 조립 자체는
///    `save_result_message_test.dart`가 덮고, 여기서는 **화면이 그것을 쓰는지**를 본다.

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/scan_page.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/features/scan/state/scan_target_group_state.dart';
import 'package:keepcon/features/scan/util/save_result_message.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

/// 공유는 성공시키되 **그룹 이름 조회만** 실패시키는 저장소.
///
/// 이름 조회는 `watchGroups`의 첫 방출에서 대상 그룹을 찾는다. 실제로는 느린
/// 네트워크(5초 상한)나 그 그룹이 아직 실리지 않은 첫 방출로 실패할 수 있는데,
/// 그 시점에는 **공유가 이미 끝나 있다.** 그것을 '공유 실패'로 알리면 사용자가
/// 성공한 공유를 다시 해서 같은 기프티콘을 두 번 넣는다.
class _NameLookupFailingShareRepository extends InMemoryShareRepository {
  _NameLookupFailingShareRepository({
    required super.authRepository,
    required super.gifticonRepository,
  });

  /// 대상 그룹이 실리지 않은 첫 방출. `shareGifticon`은 계약 구현 그대로 성공한다.
  @override
  Stream<List<Group>> watchGroups(String userId) =>
      Stream<List<Group>>.value(const <Group>[]);
}

/// 그룹 목록 스트림을 **껐다 켤 수 있는** 저장소 — 에러 배너와 재시도를 계측한다.
///
/// `watchGroups`가 첫 구독에서 에러를 던지면 정본 [myGroupsProvider]는 값 없는
/// `AsyncError`가 되고, 그때만 배너가 뜬다(`hasError && !hasValue`). `groupsFail`을
/// 끄고 '다시 시도'를 누르면 계약 훅이 그 계층만 재구독해 회복된다 — 구독 카운터로
/// 실제 재구독을 확인한다(자동 재시도가 없다는 것도 같은 카운터가 지킨다).
class _FlakyGroupsShareRepository extends InMemoryShareRepository {
  _FlakyGroupsShareRepository({
    required super.authRepository,
    required super.gifticonRepository,
    super.seed,
  });

  bool groupsFail = false;
  int groupsSubscriptions = 0;

  @override
  Stream<List<Group>> watchGroups(String userId) {
    groupsSubscriptions++;
    if (groupsFail) {
      return Stream<List<Group>>.error(StateError('groups down'));
    }
    return super.watchGroups(userId);
  }
}

/// 이름 조회가 **영영 응답하지 않는** 저장소 — 5초 상한 자체를 검증한다.
///
/// 위 [_NameLookupFailingShareRepository]는 동기 빈 방출이라 `orElse` 갈래만
/// 치고 `.timeout()`을 한 번도 발화시키지 않는다. 그래서 상한을 지워도 테스트가
/// 전부 통과했다(리뷰에서 뮤테이션으로 확인됐다). 상한이 지키는 것은 화면이
/// `ScanSubmitInProgress`로 영영 멈추는 것 — 저장 버튼이 잠긴 채다 — 이라
/// 무방비로 둘 수 없다.
class _NameLookupHangingShareRepository extends InMemoryShareRepository {
  _NameLookupHangingShareRepository({
    required super.authRepository,
    required super.gifticonRepository,
  });

  /// 하루에 한 번 방출 = 테스트 시간 안에서는 무응답이고, 닫히지도 않는다.
  @override
  Stream<List<Group>> watchGroups(String userId) =>
      Stream<List<Group>>.periodic(
        const Duration(days: 1),
        (_) => const <Group>[],
      );
}

void main() {
  final String myId = InMemoryAuthRepository.defaultUser.id;

  List<Group> dummyGroups() {
    return <Group>[
      Group(
        id: 'g_family',
        name: '가족',
        emoji: '🏠',
        members: <GroupMember>[
          GroupMember(
            userId: myId,
            displayName: '테스터',
            avatarEmoji: '😀',
            role: MemberRole.owner,
          ),
        ],
        inviteToken: 'FAM123',
      ),
      Group(
        id: 'g_friends',
        name: '친구',
        emoji: '🎉',
        members: <GroupMember>[
          GroupMember(
            userId: myId,
            displayName: '테스터',
            avatarEmoji: '😀',
            role: MemberRole.owner,
          ),
        ],
        inviteToken: 'FRI123',
      ),
    ];
  }

  void fillValidForm(GifticonFormController controller) {
    controller.setBrand('스타벅스');
    controller.setProductName('아메리카노 T');
    controller.setPrice('4,500');
    controller.setCategory('카페');
    controller.setExpiryDate(DateTime(2027, 1, 31));
  }

  Future<Gifticon?> saveOnce(
    ProviderContainer container, {
    String? targetGroupId,
  }) async {
    final GifticonFormController controller =
        container.read(gifticonFormControllerProvider.notifier);

    controller.startWith(ScanSource.manual, targetGroupId: targetGroupId);
    fillValidForm(controller);

    return controller.submit();
  }

  ProviderContainer makeContainer() {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        scanTargetGroupsProvider.overrideWith((Ref ref) => dummyGroups()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('targetGroupId 전달', () {
    test('startWith가 대상 그룹을 폼 세션에 기록한다', () {
      final ProviderContainer container = makeContainer();
      final GifticonFormController controller =
          container.read(gifticonFormControllerProvider.notifier);

      controller.startWith(ScanSource.manual);
      expect(
        container.read(gifticonFormControllerProvider).targetGroupId,
        isNull,
      );

      controller.startWith(ScanSource.camera, targetGroupId: 'g_family');

      final GifticonFormState state =
          container.read(gifticonFormControllerProvider);

      expect(state.targetGroupId, 'g_family');
      expect(state.source, ScanSource.camera);
    });

    test('reset은 대상 그룹까지 비운다', () {
      final ProviderContainer container = makeContainer();
      final GifticonFormController controller =
          container.read(gifticonFormControllerProvider.notifier);

      controller.startWith(ScanSource.manual, targetGroupId: 'g_family');
      controller.reset();

      expect(
        container.read(gifticonFormControllerProvider).targetGroupId,
        isNull,
      );
    });
  });

  group('submit — 대상 그룹 공유', () {
    test('그룹을 고르면 저장 후 그 그룹에 공유된다', () async {
      final ProviderContainer container = makeContainer();
      final Group target = dummyGroups().first;

      final Gifticon? saved = await saveOnce(
        container,
        targetGroupId: target.id,
      );

      expect(saved, isNotNull);
      expect(saved!.ownerId, myId);

      final List<Gifticon> mine =
          await container.read(gifticonRepositoryProvider).getGifticons(myId);
      expect(mine.any((Gifticon g) => g.id == saved.id), isTrue);

      final List<SharedGifticon> shared = await container
          .read(shareRepositoryProvider)
          .getSharedGifticons(target.id);

      final SharedGifticon added = shared.firstWhere(
        (SharedGifticon s) => s.gifticonId == saved.id,
      );

      expect(added.sharedByUserId, myId);
      expect(added.brand, '스타벅스');
      expect(saved.status, GifticonStatus.available);

      final ScanSubmitState submitState =
          container.read(gifticonFormControllerProvider).submit;

      expect(submitState, isA<ScanSubmitSuccess>());

      final ScanSubmitSuccess success = submitState as ScanSubmitSuccess;

      expect(success.sharedToGroup, isTrue);
      expect(success.sharedGroupId, target.id);
      expect(success.sharedGroupName, target.name);
      expect(success.shareError, isNull);
    });

    test("'내 지갑'이면 공유하지 않는다", () async {
      final ProviderContainer container = makeContainer();
      final List<Group> groups = dummyGroups();

      final Map<String, int> before = <String, int>{
        for (final Group g in groups)
          g.id: (await container
                  .read(shareRepositoryProvider)
                  .getSharedGifticons(g.id))
              .length,
      };

      final Gifticon? saved = await saveOnce(container);

      expect(saved, isNotNull);

      for (final Group g in groups) {
        final List<SharedGifticon> after = await container
            .read(shareRepositoryProvider)
            .getSharedGifticons(g.id);

        expect(after.length, before[g.id]);
        expect(
          after.any((SharedGifticon s) => s.gifticonId == saved!.id),
          isFalse,
        );
      }

      final ScanSubmitSuccess success = container
          .read(gifticonFormControllerProvider)
          .submit as ScanSubmitSuccess;

      expect(success.sharedGroupId, isNull);
      expect(success.sharedToGroup, isFalse);
      expect(success.shareError, isNull);
      expect(success.sharedGroupName, isNull);
    });

    test('공유가 실패해도 저장은 성공으로 유지된다(부분 실패)', () async {
      final ProviderContainer container = makeContainer();

      final Gifticon? saved = await saveOnce(
        container,
        targetGroupId: 'g_gone',
      );

      expect(saved, isNotNull);

      final List<Gifticon> mine =
          await container.read(gifticonRepositoryProvider).getGifticons(myId);
      expect(mine.any((Gifticon g) => g.id == saved!.id), isTrue);

      final ScanSubmitState submitState =
          container.read(gifticonFormControllerProvider).submit;

      expect(submitState, isA<ScanSubmitSuccess>());

      final ScanSubmitSuccess success = submitState as ScanSubmitSuccess;

      expect(success.sharedToGroup, isFalse);
      expect(success.sharedGroupId, 'g_gone');
      expect(success.shareError, isNotNull);
    });

    test('공유는 성공했는데 그룹 이름만 못 읽으면 공유 실패로 알리지 않는다', () async {
      final InMemoryAuthRepository auth = InMemoryAuthRepository();
      final InMemoryGifticonRepository gifticons = InMemoryGifticonRepository();
      final _NameLookupFailingShareRepository repo =
          _NameLookupFailingShareRepository(
        authRepository: auth,
        gifticonRepository: gifticons,
      );

      addTearDown(() {
        repo.dispose();
        gifticons.dispose();
        auth.dispose();
      });

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(repo),
          scanTargetGroupsProvider.overrideWith((Ref ref) => dummyGroups()),
        ],
      );
      addTearDown(container.dispose);

      final Gifticon? saved =
          await saveOnce(container, targetGroupId: 'g_family');

      expect(saved, isNotNull);

      // 공유는 **실제로 일어났다** — 이 사실이 이 테스트의 전제다.
      final List<SharedGifticon> shared =
          await repo.getSharedGifticons('g_family');
      expect(
        shared.any((SharedGifticon s) => s.gifticonId == saved!.id),
        isTrue,
      );

      final ScanSubmitSuccess success = container
          .read(gifticonFormControllerProvider)
          .submit as ScanSubmitSuccess;

      // 핵심: 이름을 못 읽었을 뿐이므로 shareError는 비어 있어야 한다.
      // (예전에는 이름 조회가 공유와 한 try에 묶여 있어 여기가 isNotNull이었다.)
      expect(success.shareError, isNull);
      expect(success.sharedGroupName, isNull);
      expect(success.sharedToGroup, isTrue);

      // 그래서 사용자가 보는 문구는 '공유 실패'가 아니고, **지갑 저장과도
      // 달라야 한다** — 같으면 자기가 고른 그룹에 들어갔는지 알 수 없다.
      final String message = saveResultMessage(
        shareError: success.shareError,
        sharedGroupName: success.sharedGroupName,
        sharedToGroup: success.sharedToGroup,
      );

      // 어간으로 본다 — 안내 경로 문구가 바뀌어도 이 테스트가 지키려는 것
      // ("공유 실패라고 말하지 않는다")은 그대로다.
      expect(message, isNot(contains('공유하지 못했')));
      // 공유됐다는 사실은 말해야 한다. 이 단언이 없으면 지갑 문구도 통과한다.
      expect(message, contains('공유'));
      expect(
        message,
        isNot(saveResultMessage(shareError: null, sharedGroupName: null)),
      );
    });

    test('이름 조회가 응답하지 않아도 5초 상한이 저장을 끝내 준다', () async {
      // 상한이 없으면 `.first`가 영영 기다려 폼이 ScanSubmitInProgress에 갇힌다
      // (저장 버튼도 잠긴 채). 그 상한을 지우면 이 테스트는 통과가 아니라
      // **프레임워크 타임아웃으로 죽는다** — 그게 이 테스트의 존재 이유다.
      //
      // ⚠️ 실시간 5초를 그대로 쓴다. `testWidgets` + `tester.pump(6초)`로 가짜
      // 시계를 넘기는 방법을 먼저 시도했는데 **테스트가 그대로 멈췄다**(300초
      // 무응답 확인). 여기서 기다리는 것은 위젯 프레임이 아니라 저장소 스트림이라
      // 바인딩의 가짜 시계가 닿지 않는다. 느린 대신 확실한 쪽을 택했다.
      final InMemoryAuthRepository auth = InMemoryAuthRepository();
      final InMemoryGifticonRepository gifticons = InMemoryGifticonRepository();
      final _NameLookupHangingShareRepository repo =
          _NameLookupHangingShareRepository(
        authRepository: auth,
        gifticonRepository: gifticons,
      );

      addTearDown(() {
        repo.dispose();
        gifticons.dispose();
        auth.dispose();
      });

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(repo),
          scanTargetGroupsProvider.overrideWith((Ref ref) => dummyGroups()),
        ],
      );
      addTearDown(container.dispose);

      final Gifticon? saved =
          await saveOnce(container, targetGroupId: 'g_family');

      expect(saved, isNotNull);

      final ScanSubmitSuccess success = container
          .read(gifticonFormControllerProvider)
          .submit as ScanSubmitSuccess;

      // 상한에 걸린 것은 이름 조회일 뿐 — 공유 실패가 아니다.
      expect(success.shareError, isNull);
      expect(success.sharedGroupName, isNull);
    });
  });

  group('저장 대상 선택 UI', () {
    /// 화면이 보는 그룹 목록. 테스트 도중 바꿀 수 있어야 "그룹이 사라지는" 상황을
    /// 재현할 수 있다(`updateOverrides`는 이미 마운트된 화면을 다시 그리지 않았다).
    late List<Group> visibleGroups;

    setUp(() => visibleGroups = dummyGroups());

    Future<ProviderContainer> pumpScanPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          scanTargetGroupsProvider.overrideWith((Ref ref) => visibleGroups),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ScanPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      return container;
    }

    testWidgets("'내 지갑'과 실제 그룹 타일이 함께 표시된다", (WidgetTester tester) async {
      await pumpScanPage(tester);

      expect(find.text('내 지갑'), findsWidgets);

      // ⚠️ 이 단언은 예전에 `findsNothing`이었다 — 이름은 "함께 표시된다"인데
      // 실제로는 그룹 타일이 **아예 그려지지 않는 상태**를 고정하고 있었다.
      // 그룹 선택 UI가 미구현이었기 때문이다.
      for (final Group g in dummyGroups()) {
        expect(find.text(g.name), findsOneWidget, reason: '그룹 타일: ${g.name}');
      }
    });

    testWidgets('그룹 타일을 고르면 폼 세션에 그 groupId가 전달된다',
        (WidgetTester tester) async {
      // ⚠️ 이 테스트는 예전에 **본문이 비어 있었다**(pump만 하고 단언 없음).
      final ProviderContainer container = await pumpScanPage(tester);
      final Group target = dummyGroups().first;

      await tester.tap(find.text(target.name));
      await tester.pumpAndSettle();

      // 선택은 폼을 열 때 세션으로 넘어간다 — 수동 입력이 그 경로 중 백엔드를
      // 타지 않는 유일한 것이라 여기서 쓴다.
      await tester.tap(find.text('직접 입력하기'));
      await tester.pumpAndSettle();

      expect(
        container.read(gifticonFormControllerProvider).targetGroupId,
        target.id,
      );
    });

    /// 스낵바 문구를 찾는다.
    ///
    /// `find.text`로는 **못 찾는다** — [KeepAllText]가 어절 보호를 위해 보이지
    /// 않는 WORD JOINER를 섞기 때문이다. 원문은 `semanticsLabel`에 남는다.
    Finder keepAllText(String plain) => find.byWidgetPredicate(
          (Widget w) => w is Text && (w.semanticsLabel ?? w.data) == plain,
        );

    /// 폼을 채우고 저장한다(수동 입력 경로 — 백엔드를 타지 않는 유일한 경로).
    Future<void> fillAndSave(WidgetTester tester) async {
      await tester.tap(find.text('직접 입력하기'));
      await tester.pumpAndSettle();

      Finder fieldByLabel(String label) => find.ancestor(
            of: find.text(label),
            matching: find.byType(TextFormField),
          );

      await tester.enterText(fieldByLabel('브랜드 / 사용처'), '스타벅스');
      await tester.enterText(fieldByLabel('상품명'), '아메리카노 T');
      await tester.enterText(fieldByLabel('바코드 번호'), '9001002003004');
      await tester.pumpAndSettle();

      await tester.tap(find.text('날짜를 선택해 주세요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, '저장하기'));
      await tester.pumpAndSettle();
    }

    testWidgets('그룹에 공유되면 스낵바가 그 그룹 이름을 말한다', (WidgetTester tester) async {
      // ⚠️ 예전에는 지갑에 넣든 그룹에 공유하든 **같은 문구**였다. 그래서
      // 사용자는 자기가 고른 그룹에 실제로 들어갔는지 알 수 없었다. 실제 앱으로
      // 세 번 저장해 스낵바가 매번 같은 것을 확인한 뒤 고쳤고, 이 테스트가
      // 그 회귀를 막는다(문구 조립은 save_result_message_test.dart가 따로 덮는다 —
      // 여기서 보는 것은 **화면이 그것을 실제로 쓰는가**다).
      await pumpScanPage(tester);

      await tester.tap(find.text(dummyGroups().first.name));
      await tester.pumpAndSettle();

      await fillAndSave(tester);

      expect(keepAllText('가족 그룹에 공유했어요.'), findsOneWidget);
      expect(keepAllText('기프티콘이 성공적으로 저장되었습니다.'), findsNothing);
    });

    testWidgets("'내 지갑'에 저장하면 스낵바가 공유를 언급하지 않는다", (WidgetTester tester) async {
      await pumpScanPage(tester);

      // '내 지갑'이 기본 선택이다 — 아무것도 고르지 않고 그대로 저장한다.
      await fillAndSave(tester);

      expect(keepAllText('기프티콘이 성공적으로 저장되었습니다.'), findsOneWidget);
    });

    testWidgets('목록에서 사라진 그룹을 골라 뒀으면 내 지갑으로 되돌린다', (WidgetTester tester) async {
      // 다른 기기에서 탈퇴·강퇴됐거나 그룹 스트림이 실패해 목록이 빈 경우.
      // 저장해 둔 id를 그대로 쓰면 **화면에는 아무것도 선택돼 있지 않은데 저장은
      // 그 그룹을 노려**, 표시되지 않는 부분 실패로 빠진다.
      final ProviderContainer container = await pumpScanPage(tester);
      final Group target = dummyGroups().first;

      await tester.tap(find.text(target.name));
      await tester.pumpAndSettle();

      // 그룹이 목록에서 사라진다.
      visibleGroups = const <Group>[];
      container.invalidate(scanTargetGroupsProvider);
      await tester.pumpAndSettle();

      expect(find.text(target.name), findsNothing);

      await tester.tap(find.text('직접 입력하기'));
      await tester.pumpAndSettle();

      expect(
        container.read(gifticonFormControllerProvider).targetGroupId,
        isNull,
      );
    });

    testWidgets("'내 지갑'을 고르면 대상 그룹이 없다", (WidgetTester tester) async {
      final ProviderContainer container = await pumpScanPage(tester);

      await tester.tap(find.text('내 지갑').first);
      await tester.pumpAndSettle();

      expect(
        container.read(gifticonFormControllerProvider).targetGroupId,
        isNull,
      );
    });
  });

  group('그룹 목록 에러 — 배너와 재시도', () {
    /// 여기서는 파생 provider를 override하지 **않는다.** 검증 대상이 정본
    /// (`myGroupsProvider`) → 파생 → 화면으로 이어지는 **실제 체인**이고, 재시도 훅
    /// `retryMyGroups`도 그 체인의 private 계층을 되살리는 것이라 파생을 갈아 끼우면
    /// 검증할 것이 남지 않는다. 저장소만 계측용으로 바꾼다.
    late InMemoryAuthRepository auth;
    late InMemoryGifticonRepository gifticons;
    late _FlakyGroupsShareRepository repo;

    /// ⚠️ [failGroups]는 **pump 전에** 켜야 한다. 화면이 마운트된 뒤에 켜면 정본이
    /// 이미 성공 방출을 갖고 있어(`hasValue`) 배너가 뜨지 않는다 — 그게 설계다
    /// (보존 값이 있으면 목록이 그대로 선택되므로 사용자가 할 일이 없다).
    Future<void> pumpScanPage(
      WidgetTester tester, {
      bool seed = true,
      bool failGroups = false,
    }) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      auth = InMemoryAuthRepository();
      gifticons = InMemoryGifticonRepository();
      repo = _FlakyGroupsShareRepository(
        authRepository: auth,
        gifticonRepository: gifticons,
        seed: seed,
      )..groupsFail = failGroups;
      addTearDown(() {
        repo.dispose();
        gifticons.dispose();
        auth.dispose();
      });

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light, home: const ScanPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('못 불러오면 배너를 띄운다 — "그룹 없음"으로 위장하지 않는다',
        (WidgetTester tester) async {
      // 이 배선의 존재 이유다. 배너가 없으면 사용자는 고를 그룹이 화면에 없다는
      // 사실만 보고 "그룹이 하나도 없구나"로 읽는다.
      await pumpScanPage(tester, failGroups: true);

      expect(find.text('그룹 목록을 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      // 저장 경로는 살아 있어야 한다 — 그룹을 못 불러온 것이 저장을 막지는 않는다.
      expect(find.text('내 지갑'), findsWidgets);
    });

    testWidgets('그룹이 정말 없을 때는 배너를 띄우지 않는다', (WidgetTester tester) async {
      // 배너의 값어치는 "못 불러옴"과 "없음"을 가르는 데 있다. 후자에까지 뜨면
      // 그 구분이 사라져 정상 상태를 오류처럼 보이게 한다.
      await pumpScanPage(tester, seed: false);

      expect(find.text('그룹 목록을 불러오지 못했어요.'), findsNothing);
      expect(find.text('다시 시도'), findsNothing);
      expect(find.text('내 지갑'), findsWidgets);
    });

    testWidgets("'다시 시도'가 계약 훅으로 실제 재구독시킨다", (WidgetTester tester) async {
      await pumpScanPage(tester, failGroups: true);

      final int before = repo.groupsSubscriptions;
      expect(find.text('그룹 목록을 불러오지 못했어요.'), findsOneWidget);

      repo.groupsFail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repo.groupsSubscriptions, greaterThan(before),
          reason: '재시도는 원천을 실제로 재구독해야 한다');
      expect(find.text('그룹 목록을 불러오지 못했어요.'), findsNothing);
      expect(find.text('가족'), findsOneWidget, reason: '회복하면 타일이 돌아온다');
    });

    testWidgets('자동 재시도는 없다 — 사용자가 누를 때만 재구독한다', (WidgetTester tester) async {
      // 장애 중 전 화면이 스스로 재구독하면 retry storm이 된다(#13).
      await pumpScanPage(tester, failGroups: true);

      final int settled = repo.groupsSubscriptions;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(repo.groupsSubscriptions, settled);
    });
  });
}
