// 승인요청목록 **팝업**의 모달 규약을 고정한다 — 목록 본문이 아니라 "팝업다움"이 축이다.
//
//  ① **스크림이 실제로 어둡다.** 뒤의 그룹 상세가 어두워진 채 보이는 것이 이 화면을
//     전체 화면 push에서 팝업으로 바꾼 이유다. `showDialog`의 기본
//     `barrierColor`(`Colors.black54`)에 기대고 있으므로, 앱 테마나 상위가 그것을
//     투명으로 덮어쓰면 팝업은 "테두리만 둥근 전체 화면"이 된다 — 조용한 회귀라
//     값을 못박는다. 테마는 앱 정본(`AppTheme.light`)을 쓴다: 맨 `MaterialApp`으로
//     재면 "앱 테마가 안 덮어쓴다"는 바로 그 명제를 검증하지 못한다.
//  ② **닫는 길이 셋 다 열려 있다** — 배리어 탭 / 헤더의 X / 뒤로가기.
//  ③ **크기가 화면을 다 먹지 않고, 어떤 건수·화면에서도 넘치지 않는다.** 0건·2건·12건을
//     좁은 세로(360x640)와 가로 모드(640x360)에서, 그리고 데스크톱 폭에서 잰다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/share/widgets/join_requests_dialog.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

/// 대기 목록만 흘리는 최소 스텁 — 나머지 호출은 오면 곧바로 터뜨린다.
class _PendingOnlyShareRepository implements ShareRepository {
  _PendingOnlyShareRepository(this.pending);

  final List<JoinRequest> pending;

  @override
  Stream<List<JoinRequest>> watchPendingJoinRequests(String groupId) =>
      Stream<List<JoinRequest>>.value(pending);

  /// 팝업이 방장 여부 이중 방어를 위해 내 그룹을 watch한다. 빈 목록 = "그룹을 모름"
  /// → 막지 않고 통과(팝업 머리말의 판단).
  @override
  Stream<List<Group>> watchGroups(String userId) =>
      Stream<List<Group>>.value(const <Group>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('기대하지 않은 호출: ${invocation.memberName}');
}

JoinRequest _req(int i) => JoinRequest(
      id: 'r$i',
      groupId: 'g1',
      userId: 'u$i',
      displayName: '요청자$i',
      avatarEmoji: '🙂',
      requestedAt: DateTime(2026, 1, 1),
    );

void main() {
  late InMemoryAuthRepository auth;

  setUp(() => auth = InMemoryAuthRepository());
  tearDown(() => auth.dispose());

  /// 호스트 화면(그룹 상세 자리) 위에 팝업을 연다.
  Future<void> open(
    WidgetTester tester, {
    required int count,
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          shareRepositoryProvider.overrideWithValue(
            _PendingOnlyShareRepository(
              List<JoinRequest>.generate(count, _req),
            ),
          ),
        ],
        child: MaterialApp(
          // 앱 정본 테마 — ①의 명제를 재려면 맨 테마로는 안 된다.
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showJoinRequestsDialog(ctx, 'g1'),
                  child: const Text('호스트 화면'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('호스트 화면'));
    await tester.pumpAndSettle();
  }

  /// 팝업의 **표면**(둥근 카드) 크기. `Dialog` 위젯 자체는 바깥 여백까지 포함한
  /// 화면 전체 크기라 그것으로는 잴 수 없다.
  Size surfaceOf(WidgetTester tester) => tester.getSize(
        find
            .descendant(
                of: find.byType(Dialog), matching: find.byType(Material))
            .first,
      );

  group('스크림', () {
    testWidgets('배리어가 실제로 어둡다 — 앱 테마가 기본값을 덮어쓰지 않는다',
        (WidgetTester tester) async {
      await open(tester, count: 2, size: const Size(360, 640));

      final Iterable<ModalBarrier> barriers =
          tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
      final Iterable<Color> colors = barriers
          .map((ModalBarrier b) => b.color)
          .whereType<Color>()
          .where((Color c) => c.a > 0);

      expect(colors, isNotEmpty, reason: '색 있는 배리어가 없다 = 스크림이 사라졌다');
      // 값까지 못박는다 — `black54`가 이 변경이 기대는 기본값이다.
      expect(colors.first, Colors.black54);
    });

    testWidgets('스크림이 호스트 화면을 덮는다 — 팝업 표면보다 크다', (WidgetTester tester) async {
      await open(tester, count: 2, size: const Size(360, 640));

      final Rect barrier = tester.getRect(find
          .byWidgetPredicate((Widget w) => w is ModalBarrier && w.color != null)
          .first);
      expect(barrier.size, const Size(360, 640));
      // 호스트가 살아 있다(=덮기만 하고 지우지 않았다).
      expect(find.text('호스트 화면'), findsOneWidget);
    });
  });

  group('닫는 길', () {
    testWidgets('배리어 바깥을 탭하면 닫힌다', (WidgetTester tester) async {
      await open(tester, count: 2, size: const Size(360, 640));
      expect(find.byType(JoinRequestsDialog), findsOneWidget);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.byType(JoinRequestsDialog), findsNothing);
      expect(find.text('호스트 화면'), findsOneWidget);
    });

    testWidgets('헤더의 X를 누르면 닫힌다', (WidgetTester tester) async {
      await open(tester, count: 2, size: const Size(360, 640));

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(JoinRequestsDialog), findsNothing);
    });

    testWidgets('뒤로가기로도 닫힌다 — 막는 PopScope를 두지 않았다',
        (WidgetTester tester) async {
      await open(tester, count: 2, size: const Size(360, 640));

      // 플랫폼 뒤로가기(Android back / 브라우저 back)와 같은 경로.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(JoinRequestsDialog), findsNothing);
      expect(find.text('호스트 화면'), findsOneWidget);
    });
  });

  group('크기 — 0건 / 2건 / 12건', () {
    for (final (String label, Size size) in <(String, Size)>[
      ('좁은 세로 360x640', const Size(360, 640)),
      ('가로 모드 640x360', const Size(640, 360)),
    ]) {
      for (final int count in <int>[0, 2, 12]) {
        testWidgets('$label · $count건 — 넘치지 않고 화면을 다 먹지 않는다',
            (WidgetTester tester) async {
          await open(tester, count: count, size: size);

          expect(tester.takeException(), isNull, reason: '오버플로가 났다');

          final Size surface = surfaceOf(tester);
          // 좌우에 스크림이 보여야 모달로 읽힌다(바깥 여백 24 × 2).
          expect(surface.width, lessThanOrEqualTo(size.width - 48 + 0.01));
          // 세로 상한 70%를 넘지 않는다.
          expect(surface.height, lessThanOrEqualTo(size.height * 0.7 + 0.01));
          // 팝업이 내용을 담기는 한다(0건에도 헤더 + 안내가 있다).
          expect(find.text('승인요청목록'), findsOneWidget);
          if (count == 0) {
            expect(find.text('대기 중인 참여 요청이 없어요.'), findsOneWidget);
          } else {
            expect(find.text('대기 중 $count명'), findsOneWidget);
          }
        });
      }
    }

    testWidgets('적은 건수에서는 상한까지 늘어나지 않는다 — 내용만큼만 차지한다',
        (WidgetTester tester) async {
      // `shrinkWrap`이 빠지면 0건·2건에도 팝업이 상한(70%)까지 차올라 아래가 텅 빈다.
      await open(tester, count: 0, size: const Size(360, 640));
      final double empty = surfaceOf(tester).height;
      expect(empty, lessThan(640 * 0.7),
          reason: '0건인데 상한까지 늘어났다 = 높이가 내용을 따르지 않는다');

      // 다시 열기 전에 닫는다 — 열린 채로 `pumpWidget`을 다시 부르면 Navigator가
      // 앞 팝업을 그대로 들고 있어 호스트 버튼이 배리어에 가린다.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await open(tester, count: 2, size: const Size(360, 640));
      final double two = surfaceOf(tester).height;
      expect(two, greaterThan(empty), reason: '건수가 늘었는데 높이가 그대로다');
      expect(two, lessThan(640 * 0.7));
    });

    testWidgets('12건에서는 목록만 스크롤되고 헤더는 고정이다', (WidgetTester tester) async {
      await open(tester, count: 12, size: const Size(360, 640));

      final double headerBefore = tester.getTopLeft(find.text('승인요청목록')).dy;
      expect(find.text('요청자0'), findsOneWidget);
      // 12건이 다 보이지는 않는다(= 스크롤이 필요한 상태인 것이 이 테스트의 전제).
      expect(find.text('요청자11'), findsNothing);

      await tester.drag(find.text('요청자0'), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('요청자11'), findsOneWidget);
      expect(tester.getTopLeft(find.text('승인요청목록')).dy, headerBefore,
          reason: '헤더가 목록과 함께 스크롤됐다');
      expect(tester.takeException(), isNull);
    });

    testWidgets('데스크톱 폭에서 가로로 늘어나지 않는다', (WidgetTester tester) async {
      // 이 저장소는 웹으로도 뜬다 — 상한이 없으면 팝업이 페이지처럼 읽힌다.
      await open(tester, count: 2, size: const Size(1400, 900));

      expect(surfaceOf(tester).width, lessThanOrEqualTo(400.01));
    });
  });
}
