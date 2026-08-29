/// scan — '저장할 그룹 선택' 실연동 테스트.
///
/// 검증 대상:
/// 1. 선택한 groupId가 폼 세션으로 전달되고('내 지갑'=null), reset이 그것을 비운다.
/// 2. 저장(addGifticon) 성공 후, 대상 그룹이 있으면 `ShareRepository.shareGifticon`이
///    호출되고 '내 지갑'이면 호출되지 않는다.
/// 3. 그룹 공유가 실패해도(예: 사라진 그룹) 저장은 성공으로 유지된다(부분 실패 정책).
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
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

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
}
