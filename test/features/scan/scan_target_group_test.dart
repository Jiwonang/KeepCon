/// scan — '저장할 그룹 선택' 실연동 테스트.
///
/// 검증 대상:
/// 1. 선택한 groupId가 폼 세션으로 전달되고('내 지갑'=null), '저장 후 계속 등록' 시에도
///    같은 대상 그룹이 유지된다.
/// 2. 저장(addGifticon) 성공 후, 대상 그룹이 있으면 `ShareRepository.shareGifticon`이
///    호출되고 '내 지갑'이면 호출되지 않는다.
/// 3. 그룹 공유가 실패해도(예: 사라진 그룹) 저장은 성공으로 유지된다(부분 실패 정책).

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

  group('_GroupSelector 위젯', () {
    Future<ProviderContainer> pumpScanPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ProviderContainer container = makeContainer();

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
      final List<Group> groups = dummyGroups();

      expect(find.text('내 지갑'), findsWidgets);

      for (final Group g in groups) {
        expect(find.text(g.name), findsNothing);
      }
    });

    testWidgets('그룹 타일을 고르면 폼 세션에 그 groupId가 전달된다',
        (WidgetTester tester) async {
      await pumpScanPage(tester);
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
