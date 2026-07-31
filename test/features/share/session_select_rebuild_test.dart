/// share의 **세션 소비 리빌드 축** 고정 테스트(크로스페이지 주의점 #13).
///
/// 배경: share는 세션 정본 `sessionUserProvider`를 직수입한다(경과 조치였던 페이지 별칭
/// `shareCurrentUserProvider` 제거). 그 별칭은 `Provider`라 `updateShouldNotify`가
/// `previous != next`였고 `AsyncValue`는 `==`를 구현하므로 **같은 값의 재방출을 흡수하는
/// 필터**였다. 정본은 `StreamProvider`라 로딩 전이가 아니면 data→data 재방출도 무조건
/// 통지한다(riverpod 2.6.1 `FutureHandlerProviderElementMixin.handleUpdateShouldNotify`).
/// Firebase 구현은 `authStateChanges()`가 아니라 `userChanges()`를 쓰므로 **토큰 갱신·프로필
/// 갱신에서 값이 사실상 같은 세션이 재방출**된다 — 그래서 `user?.id`만 읽는 소비 지점은
/// `select((s) => s.valueOrNull?.id)`로 좁혀 별칭이 하던 필터를 되살렸다.
///
/// 이 파일은 그 `select`를 **테스트로 고정**한다("구독 수는 테스트가 고정한다"는 세션
/// 슬라이스의 원칙을 리빌드 축에도 적용 — QA [medium 2]). 계측은 같은 uid·다른 표시명
/// 재방출이고, 대표 3지점을 잡는다:
/// - 파생: `memberNamesProvider`(반환 `MemberNames`에 `==`가 없어 **재계산 = 새 인스턴스 =
///   소비 위젯 리빌드**라 영향이 가장 크다)
/// - 화면: `SharePage`, `GroupDetailPage`(`_GroupDetailBody`)
///
/// 화면 축의 단언은 **위젯 인스턴스 동일성**이다 — 위젯은 불변 객체라 build가 다시 돌면
/// 반드시 새 인스턴스가 만들어지므로, `identical`이 곧 "이 subtree가 리빌드됐는가"다.
/// 각 테스트는 "정본에는 새 값이 도착했다"를 함께 단언해, 아무 일도 안 일어나서 통과하는
/// 공허한 테스트가 되지 않게 한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/pages/group_detail_page.dart';
import 'package:keepcon/features/share/share_page.dart';
import 'package:keepcon/features/share/state/share_providers.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/session_provider.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

/// 세션 스트림에 임의의 사용자를 **재방출**할 수 있는 계측용 [AuthRepository].
///
/// Firebase `userChanges()`처럼 로그인/로그아웃뿐 아니라 프로필 갱신·토큰 갱신으로도
/// 이벤트가 오는 스트림을 재현한다. 세션 외 계약 메서드는 [noSuchMethod]로 막아 예상 밖
/// 호출이 조용히 통과하지 않게 한다(단, [currentUser]는 `createGroup` 등 계약 구현이
/// 행위자를 판독하는 경로라 실제 값을 돌려준다).
class _ScriptedAuthRepository implements AuthRepository {
  _ScriptedAuthRepository(this._user);

  User? _user;
  final StreamController<User?> _controller =
      StreamController<User?>.broadcast();

  @override
  User? get currentUser => _user;

  /// 구독 **즉시**(동기적으로) 원천에 붙고 현재 값을 시드한다 — `async*`로 쓰면 첫
  /// 방출을 소비할 때까지 원천 구독이 미뤄져, 그 사이의 [emit]이 조용히 유실된다
  /// (계측이 아니라 타이밍을 시험하는 테스트가 된다).
  @override
  Stream<User?> watchCurrentUser() {
    late final StreamController<User?> out;
    StreamSubscription<User?>? sub;
    out = StreamController<User?>(
      onListen: () {
        out.add(_user);
        sub = _controller.stream.listen(out.add, onError: out.addError);
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  /// 세션 스트림에 [user]를 재방출한다.
  void emit(User? user) {
    _user = user;
    _controller.add(user);
  }

  void dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('이 테스트가 쓰지 않는 계약 메서드: ${invocation.memberName}');
}

void main() {
  const User me = User(
    id: 'user-1',
    email: 'me@keepcon.app',
    displayName: '나',
  );

  /// **같은 uid**, 다른 표시명 — 토큰 갱신·프로필 갱신 재방출 재현(`==`는 다르다).
  const User meRenamed = User(
    id: 'user-1',
    email: 'me@keepcon.app',
    displayName: '나(이름 변경)',
  );

  /// 양성 대조용 — uid가 바뀌면 반드시 재계산·리빌드돼야 한다.
  const User other = User(
    id: 'user-2',
    email: 'other@keepcon.app',
    displayName: '다른 사람',
  );

  late _ScriptedAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late InMemoryShareRepository share;

  setUp(() {
    auth = _ScriptedAuthRepository(me);
    gifticons = InMemoryGifticonRepository();
    share = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      seed: false,
    );
  });

  tearDown(() {
    share.dispose();
    gifticons.dispose();
    auth.dispose();
  });

  List<Override> overrides() => <Override>[
        authRepositoryProvider.overrideWithValue(auth),
        gifticonRepositoryProvider.overrideWithValue(gifticons),
        shareRepositoryProvider.overrideWithValue(share),
      ];

  ProviderContainer containerOf(WidgetTester tester, Finder page) =>
      ProviderScope.containerOf(tester.element(page), listen: false);

  test('memberNamesProvider — 같은 uid 재방출에는 재계산되지 않는다(uid가 바뀌면 재계산)', () async {
    final ProviderContainer container =
        ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);

    int notifications = 0;
    container.listen<MemberNames>(
      memberNamesProvider,
      (MemberNames? _, MemberNames __) => notifications++,
    );
    await container.read(sessionUserProvider.future);
    await pumpEventQueue(); // 콜드 로딩(세션·그룹 첫 방출)까지 흘려보낸 뒤 계측을 시작한다.
    final MemberNames before = container.read(memberNamesProvider);
    final int baseline = notifications;
    expect(before.isMe(me.id), isTrue, reason: '세션이 먼저 반영돼 있어야 한다');

    auth.emit(meRenamed);
    await pumpEventQueue();

    expect(
      container.read(sessionUserProvider).valueOrNull?.displayName,
      meRenamed.displayName,
      reason: '정본에는 새 값이 도착했어야 한다(공허한 통과 방지)',
    );
    expect(notifications - baseline, 0,
        reason: 'select(uid)가 같은 uid 재방출을 걸러야 한다 — 걸러지지 않으면 소비 위젯이 함께 리빌드된다');
    expect(
      identical(container.read(memberNamesProvider), before),
      isTrue,
      reason: 'MemberNames는 ==가 없어 재계산이 곧 새 인스턴스(= 리빌드)다',
    );

    auth.emit(other);
    await pumpEventQueue();

    expect(notifications - baseline, greaterThan(0),
        reason: '양성 대조 — uid가 바뀌면 반드시 재계산된다');
    expect(container.read(memberNamesProvider).isMe(other.id), isTrue);
  });

  testWidgets('SharePage — 같은 uid 재방출에는 리빌드되지 않는다(uid가 바뀌면 리빌드)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: SharePage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder page = find.byType(SharePage);
    final Scaffold before = tester.widget<Scaffold>(find.byType(Scaffold));

    auth.emit(meRenamed);
    await tester.pumpAndSettle();

    expect(
      containerOf(tester, page)
          .read(sessionUserProvider)
          .valueOrNull
          ?.displayName,
      meRenamed.displayName,
      reason: '정본에는 새 값이 도착했어야 한다(공허한 통과 방지)',
    );
    expect(
      identical(tester.widget<Scaffold>(find.byType(Scaffold)), before),
      isTrue,
      reason: '위젯은 불변이라 build가 다시 돌면 새 인스턴스가 된다 — 같은 uid엔 리빌드가 없어야 한다',
    );

    auth.emit(other);
    await tester.pumpAndSettle();

    expect(
      identical(tester.widget<Scaffold>(find.byType(Scaffold)), before),
      isFalse,
      reason: '양성 대조 — uid가 바뀌면 리빌드된다',
    );
  });

  testWidgets('GroupDetailPage(_GroupDetailBody) — 같은 uid 재방출에는 리빌드되지 않는다',
      (WidgetTester tester) async {
    final Group g = await share.createGroup(name: '가족', emoji: '🏠');

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(home: GroupDetailPage(groupId: g.id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '로딩 분기가 아니라 본문(_GroupDetailBody)이 렌더된 상태여야 한다');

    final Finder page = find.byType(GroupDetailPage);
    final Scaffold before = tester.widget<Scaffold>(find.byType(Scaffold));

    auth.emit(meRenamed);
    await tester.pumpAndSettle();

    expect(
      containerOf(tester, page)
          .read(sessionUserProvider)
          .valueOrNull
          ?.displayName,
      meRenamed.displayName,
      reason: '정본에는 새 값이 도착했어야 한다(공허한 통과 방지)',
    );
    expect(
      identical(tester.widget<Scaffold>(find.byType(Scaffold)), before),
      isTrue,
      reason: '본인 판별에 쓰는 uid가 그대로면 상세 본문은 리빌드되지 않아야 한다',
    );
  });
}
