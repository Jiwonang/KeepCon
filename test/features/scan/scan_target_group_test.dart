/// scan — '저장할 그룹 선택' 실연동 테스트.
///
/// 검증 대상:
/// 1. 선택한 groupId가 폼 세션으로 전달되고('내 지갑'=null), '저장 후 계속 등록' 시에도
///    같은 대상 그룹이 유지된다.
/// 2. 저장(addGifticon) 성공 후, 대상 그룹이 있으면 `ShareRepository.shareGifticon`이
///    호출되고 '내 지갑'이면 호출되지 않는다.
/// 3. 그룹 공유가 실패해도(예: 사라진 그룹) 저장은 성공으로 유지된다(부분 실패 정책).
///
/// 계약 소비만으로 검증한다 — 리포지토리는 `lib/shared`의 InMemory 구현 조합
/// (기본 provider = 같은 인스턴스 공유)을 쓰고, 페이지는 계약을 재정의하지 않는다.
///
/// **시드 상수에 하드 결합하지 않는다.** 시드(그룹 id·이름·이모지)는 share 소유의
/// 데모 데이터일 뿐 계약이 아니므로, 테스트는 [myGroups]로 현재 사용자의 그룹을
/// **동적으로 읽어** 그 id·이름을 사용한다 — share 담당이 시드를 바꿔도 이 테스트는
/// 깨지지 않는다. 유일한 전제는 "기본 사용자가 둘 이상의 그룹에 속한다"이며,
/// 전제가 깨지면 reason 메시지로 원인이 바로 드러난다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/scan_page.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/features/scan/state/scan_target_group_state.dart';
import 'package:keepcon/features/scan/widgets/gifticon_form.dart'
    hide
        GifticonFormController,
        gifticonFormControllerProvider,
        ScanSource,
        GifticonFormState,
        ScanSubmitState,
        ScanSubmitSuccess,
        ScanSubmitIdle,
        ScanSubmitFailure;
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

void main() {
  final String myId = InMemoryAuthRepository.defaultUser.id;

  /// 현재 사용자의 시드 그룹을 동적으로 읽는다(시드 상수 비결합 — 파일 doc 참조).
  Future<List<Group>> myGroups(ProviderContainer container) async {
    final List<Group> groups =
        await container.read(shareRepositoryProvider).getGroups(myId);

    expect(
      groups.length,
      greaterThanOrEqualTo(2),
      reason: '테스트 전제: 기본 사용자가 둘 이상의 시드 그룹에 속해야 한다 — '
          'InMemoryShareRepository 시드에서 기본 사용자의 그룹 소속이 줄었다면 '
          '이 전제부터 확인할 것',
    );

    return groups;
  }

  /// 폼을 유효한 상태로 채운다(계약 필수 필드).
  void fillValidForm(GifticonFormController controller) {
    controller.setBrand('스타벅스');
    controller.setProductName('아메리카노 T');
    controller.setPrice('4,500');
    controller.setCategory('카페');
    controller.setExpiryDate(DateTime(2027, 1, 31));
  }

  /// 선택 목록 provider를 실제 화면처럼 "떠 있는 상태"로 만든다.
  ///
  /// 컨트롤러는 스낵바 문구용 그룹명을 [scanTargetGroupsProvider]에서 동기
  /// 캡처한다(원격 재조회 없음). 실제 앱에서는 선택 UI가 이 provider를 구독 중인
  /// 상태에서만 submit이 일어나므로(autoDispose — 화면에 떠 있는 동안 유지),
  /// 테스트도 listen으로 같은 전제를 재현하고 스트림 첫 방출을 기다린다.
  Future<void> warmGroupList(ProviderContainer container) async {
    container.listen<List<Group>>(scanTargetGroupsProvider, (_, __) {});

    for (int i = 0;
        i < 10 && container.read(scanTargetGroupsProvider).isEmpty;
        i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// 대상 그룹을 지정해 한 건 저장한다. 반환값은 [GifticonFormController.submit] 결과.
  Future<Gifticon?> saveOnce(
    ProviderContainer container, {
    String? targetGroupId,
  }) async {
    // 실제 흐름과 동일하게, 선택 UI가 목록을 구독 중인 상태를 만든다.
    await warmGroupList(container);

    final GifticonFormController controller =
        container.read(gifticonFormControllerProvider.notifier);

    controller.startWith(ScanSource.manual, targetGroupId: targetGroupId);
    fillValidForm(controller);

    return controller.submit();
  }

  ProviderContainer makeContainer() {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('targetGroupId 전달', () {
    test('startWith가 대상 그룹을 폼 세션에 기록한다', () {
      final ProviderContainer container = makeContainer();
      final GifticonFormController controller =
          container.read(gifticonFormControllerProvider.notifier);

      // 기본값('내 지갑') — 그룹 공유 없음.
      controller.startWith(ScanSource.manual);
      expect(
        container.read(gifticonFormControllerProvider).targetGroupId,
        isNull,
      );

      // 그룹 선택 시 그 id가 세션에 담긴다.
      controller.startWith(ScanSource.camera, targetGroupId: 'g_family');

      final GifticonFormState state =
          container.read(gifticonFormControllerProvider);

      expect(state.targetGroupId, 'g_family');

      // 입력 경로 기록은 기존과 동일하게 유지된다.
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
      final Group target = (await myGroups(container)).first;

      final Gifticon? saved = await saveOnce(
        container,
        targetGroupId: target.id,
      );

      expect(saved, isNotNull);
      expect(saved!.ownerId, myId);

      // 저장은 계약 그대로 내 목록에 반영된다.
      final List<Gifticon> mine =
          await container.read(gifticonRepositoryProvider).getGifticons(myId);
      expect(mine.any((Gifticon g) => g.id == saved.id), isTrue);

      // 그룹에는 공유 항목(원본 참조 = gifticonId)이 추가된다.
      final List<SharedGifticon> shared = await container
          .read(shareRepositoryProvider)
          .getSharedGifticons(target.id);

      final SharedGifticon added = shared.firstWhere(
        (SharedGifticon s) => s.gifticonId == saved.id,
      );

      expect(added.sharedByUserId, myId);
      expect(added.brand, '스타벅스');

      // 공유는 원본 상태를 바꾸지 않는다(계약).
      expect(saved.status, GifticonStatus.available);

      // 제출 상태에 공유 결과가 담긴다(스낵바 문구용).
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
      final List<Group> groups = await myGroups(container);

      // 저장 전 그룹별 공유 항목 수를 기억해 둔다(시드 항목이 있으므로 증감으로 비교).
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

      // 선택 후 탈퇴/삭제로 사라진 그룹 상황을 재현한다 → 계약상 StateError.
      final Gifticon? saved = await saveOnce(
        container,
        targetGroupId: 'g_gone',
      );

      // 저장은 되돌리지 않는다.
      expect(saved, isNotNull);

      final List<Gifticon> mine =
          await container.read(gifticonRepositoryProvider).getGifticons(myId);
      expect(mine.any((Gifticon g) => g.id == saved!.id), isTrue);

      // 제출 결과는 성공이지만 공유 실패 사유가 담긴다.
      final ScanSubmitState submitState =
          container.read(gifticonFormControllerProvider).submit;

      expect(submitState, isA<ScanSubmitSuccess>());

      final ScanSubmitSuccess success = submitState as ScanSubmitSuccess;

      expect(success.sharedToGroup, isFalse);
      expect(success.sharedGroupId, 'g_gone');

      // 사용자 안내 문구는 내부 메시지(영문 StateError·raw groupId)를
      // 노출하지 않는 한국어 중립 문구다(share 페이지 규약과 동일).
      expect(success.shareError, isNotNull);
      expect(success.shareError, isNot(contains('g_gone')));
      expect(success.shareError, contains('그룹에 공유하지 못했어요'));
    });
  });

  group('_GroupSelector 위젯', () {
    /// 스캔 화면을 넉넉한 뷰포트에 띄운다(그룹 선택 영역까지 화면에 들어오도록).
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

      // 그룹 스트림의 첫 방출을 반영한다.
      await tester.pumpAndSettle();

      return container;
    }

    testWidgets("'내 지갑'과 실제 그룹 타일이 함께 표시된다", (WidgetTester tester) async {
      final ProviderContainer container = await pumpScanPage(tester);
      final List<Group> groups = await myGroups(container);

      // '내 지갑 (개인 소장)'으로 텍스트 변경 및 화면 스크롤 보장
      final myWalletFinder = find.text('내 지갑 (개인 소장)');
      await tester.ensureVisible(myWalletFinder);
      expect(myWalletFinder, findsOneWidget);

      for (final Group g in groups) {
        final groupFinder = find.text(g.name);
        await tester.ensureVisible(groupFinder);
        expect(groupFinder, findsOneWidget);
      }
    });

    testWidgets('그룹 타일을 고르면 폼 세션에 그 groupId가 전달된다',
        (WidgetTester tester) async {
      final ProviderContainer container = await pumpScanPage(tester);
      final Group target = (await myGroups(container)).first;

      // 1. 그룹 선택
      final targetFinder = find.text(target.name);
      await tester.ensureVisible(targetFinder);
      await tester.tap(targetFinder);
      await tester.pumpAndSettle();

      // 2. '직접 입력하기'로 텍스트 변경
      final inputButtonFinder = find.text('직접 입력하기');
      await tester.ensureVisible(inputButtonFinder);
      await tester.tap(inputButtonFinder);
      await tester.pumpAndSettle();

      // 3. 검증
      expect(find.byType(GifticonForm), findsOneWidget);
      expect(
        container.read(gifticonFormControllerProvider).targetGroupId,
        target.id,
      );
    });

    testWidgets("'내 지갑'을 고르면 대상 그룹이 없다", (WidgetTester tester) async {
      final ProviderContainer container = await pumpScanPage(tester);

      // '내 지갑 (개인 소장)'으로 텍스트 변경
      final myWalletFinder = find.text('내 지갑 (개인 소장)');
      await tester.ensureVisible(myWalletFinder);
      await tester.tap(myWalletFinder);
      await tester.pumpAndSettle();

      expect(
        container.read(gifticonFormControllerProvider).targetGroupId,
        isNull,
      );
    });
  });

  group('저장 후 계속 등록', () {
    /// 그룹 선택 상태로 폼 세션을 시작하고 GifticonForm만 띄운다.
    ///
    /// (뷰포트·pump 설정을 두 테스트가 복붙하지 않도록 로컬 헬퍼로 접는다)
    Future<ProviderContainer> pumpForm(
      WidgetTester tester, {
      String? targetGroupId,
    }) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ProviderContainer container = makeContainer();

      // 실제 흐름과 동일하게, 선택 UI가 목록을 구독 중인 상태를 만든다
      // (컨트롤러의 그룹명 동기 캡처 전제 — warmGroupList doc 참조).
      container.listen<List<Group>>(scanTargetGroupsProvider, (_, __) {});

      // 폼 세션을 시작한다(스캔 화면에서 넘어온 상태).
      final GifticonFormController controller =
          container.read(gifticonFormControllerProvider.notifier);

      controller.startWith(ScanSource.manual, targetGroupId: targetGroupId);
      fillValidForm(controller);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: GifticonForm()),
          ),
        ),
      );

      // 그룹 스트림 첫 방출을 반영한다(빈 목록이면 몇 프레임 더 진행).
      for (int i = 0;
          i < 10 && container.read(scanTargetGroupsProvider).isEmpty;
          i++) {
        await tester.pump();
      }

      return container;
    }

    testWidgets('대상 그룹을 유지하고 공유 결과를 안내한다', (WidgetTester tester) async {
      // 대상 그룹은 시드에서 동적으로 얻는다(별도 컨테이너로 미리 조회 —
      // 시드는 결정적이라 pump용 컨테이너와 같은 그룹이 나온다).
      final Group target = (await myGroups(makeContainer())).first;

      final ProviderContainer container =
          await pumpForm(tester, targetGroupId: target.id);

      await tester.tap(find.widgetWithText(OutlinedButton, '저장 후 계속 등록'));
      await tester.pumpAndSettle();

      // 스낵바가 공유된 그룹명을 알려준다.
      expect(
        find.textContaining('${target.name} 그룹에 공유됨'),
        findsOneWidget,
      );

      final GifticonFormState next =
          container.read(gifticonFormControllerProvider);

      // 다음 세션은 빈 폼이지만 대상 그룹은 그대로 유지된다(공유 성공 시).
      expect(next.targetGroupId, target.id);
      expect(next.brand, '');
      expect(next.source, ScanSource.manual);
      expect(next.submit, isA<ScanSubmitIdle>());
    });

    testWidgets('공유가 실패했으면 다음 세션에 그 그룹을 물려주지 않는다(내 지갑 폴백)',
        (WidgetTester tester) async {
      // 존재하지 않는 그룹 → 공유 실패(저장은 성공).
      final ProviderContainer container =
          await pumpForm(tester, targetGroupId: 'g_gone');

      await tester.tap(find.widgetWithText(OutlinedButton, '저장 후 계속 등록'));
      await tester.pumpAndSettle();

      // 실패 사유가 회수 경로 안내와 함께 표시된다(완결 문장 — 이중 라벨 없음).
      expect(find.textContaining('그룹에 공유하지 못했어요'), findsOneWidget);

      // 죽은 그룹을 다음 세션에 상속하면 이후 저장마다 실패가 반복되므로
      // '내 지갑'으로 폴백한다.
      expect(
        container.read(gifticonFormControllerProvider).targetGroupId,
        isNull,
      );
    });

    testWidgets("'내 지갑' 저장은 공유 안내 문구가 붙지 않는다", (WidgetTester tester) async {
      await pumpForm(tester);

      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();

      expect(find.textContaining('저장됨: 스타벅스 아메리카노 T'), findsOneWidget);
      expect(find.textContaining('공유됨'), findsNothing);
      expect(find.textContaining('공유하지 못했어요'), findsNothing);
    });
  });
}
