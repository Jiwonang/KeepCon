/// 멤버 초대 화면의 **하단 CTA = OS 공유 시트** 고정 테스트.
///
/// 배경: 이 CTA는 라벨·아이콘("공유", [Icons.ios_share])이 공유 시트를 약속하면서
/// 실제로는 상단 "초대 링크" 필드와 **똑같은 클립보드 복사**를 하고 있었다. 화면 안에
/// 같은 동작이 두 벌 있었고, 버튼이 하는 말과 하는 일이 달랐다. 이 파일은 그 복귀를 막는다.
///
/// 계측 지점은 share_plus의 플랫폼 채널(`dev.fluttercommunity.plus/share`)이다. 테스트
/// 바인딩에서 `SharePlatform.instance`는 기본값인 `MethodChannelShare`라, 채널을 mock
/// 하면 "정말 공유 시트를 호출했는가"를 단언할 수 있다. 클립보드(`flutter/platform`의
/// `Clipboard.setData`)도 함께 감시해 **두 경로가 섞이지 않음**을 고정한다:
///
/// - (a) 정상 — 공유 채널이 그룹명+초대 링크를 담아 1회 호출되고, 클립보드는 그대로다.
/// - (b) 시트 실패 — 채널이 던지면 클립보드 복사로 폴백하고 이유를 스낵바로 알린다.
///   웹(Web Share API 미지원 브라우저)에서 실제로 타는 경로라 공허한 방어가 아니다.
/// - (c) **만료된 초대** — 24시간이 지난 코드는 받는 쪽이 참여할 수 없으므로(`joinGroup`
///   가드) 내보내는 경로(복사·공유 시트)를 전부 막는다. 죽은 링크를 배포하는 회귀 고정.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/pages/member_invite_page.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// `watchGroups`만 지원하는 최소 스텁 — 만료된 초대를 가진 그룹을 주입한다.
///
/// [InMemoryShareRepository]로는 만료 상태를 만들 수 없다(24시간 고정 정책이라 만료를
/// 앞당기는 API가 없다 — 그게 이 정책의 핵심이다). 그 밖의 호출은 [noSuchMethod]로 막아
/// 예상 밖 경로가 조용히 통과하지 않게 한다.
class _FixedGroupsShareRepository implements ShareRepository {
  _FixedGroupsShareRepository(this.groups);

  final List<Group> groups;

  @override
  Stream<List<Group>> watchGroups(String userId) =>
      Stream<List<Group>>.value(groups);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        '이 테스트는 watchGroups만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// share_plus가 네이티브 시트를 부를 때 쓰는 채널.
  const MethodChannel shareChannel =
      MethodChannel('dev.fluttercommunity.plus/share');

  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late InMemoryShareRepository share;
  late Group group;

  /// 공유 채널이 받은 인자(호출될 때마다 누적).
  late List<Map<Object?, Object?>> shareCalls;

  /// 클립보드에 실제로 들어간 값(누적) — 복사 경로가 탔는지 판별한다.
  late List<String> clipboardWrites;

  /// 공유 채널이 실패를 던질지 여부(웹 미지원 브라우저 재현).
  late bool shareFails;

  setUp(() async {
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    share = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
    );
    group = await share.createGroup(name: '우리집', emoji: '🏠');

    shareCalls = <Map<Object?, Object?>>[];
    clipboardWrites = <String>[];
    shareFails = false;

    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(shareChannel, (MethodCall call) async {
      if (call.method != 'share') return null;
      if (shareFails) {
        throw PlatformException(code: 'unavailable');
      }
      shareCalls.add(call.arguments as Map<Object?, Object?>);
      return 'dev.fluttercommunity.plus/share/success';
    });

    // 클립보드는 감시만 하고 기본 동작(읽기 등)은 방해하지 않는다.
    messenger.setMockMethodCallHandler(SystemChannels.platform,
        (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardWrites.add(
          (call.arguments as Map<Object?, Object?>)['text']! as String,
        );
      }
      return null;
    });
  });

  tearDown(() {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(shareChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    share.dispose();
    gifticons.dispose();
    auth.dispose();
  });

  Future<void> pumpInvitePage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(share),
        ],
        child: MaterialApp(home: MemberInvitePage(groupId: group.id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('하단 CTA를 누르면 공유 시트가 열리고 클립보드는 건드리지 않는다',
      (WidgetTester tester) async {
    await pumpInvitePage(tester);

    await tester.tap(find.text('어플로 공유하기'));
    await tester.pumpAndSettle();

    expect(shareCalls, hasLength(1));
    // 링크만이 아니라 "어느 그룹인지"까지 전달한다 — 받는 쪽 맥락.
    expect(shareCalls.single['text'], contains(group.inviteUrl));
    expect(shareCalls.single['text'], contains('우리집'));
    // 복사 경로가 함께 타면 CTA가 다시 복사 버튼이 된 것이다(회귀 고정).
    expect(clipboardWrites, isEmpty);
  });

  testWidgets('공유 시트를 열 수 없으면 초대 링크를 복사하고 이유를 알린다',
      (WidgetTester tester) async {
    shareFails = true;
    await pumpInvitePage(tester);

    await tester.tap(find.text('어플로 공유하기'));
    await tester.pumpAndSettle();

    expect(clipboardWrites, <String>[group.inviteUrl]);
    expect(find.text('공유 시트를 열 수 없어 초대 링크를 복사했어요.'), findsOneWidget);
  });

  testWidgets('상단 "초대 링크" 필드의 복사는 그대로다(공유와 별개 경로)',
      (WidgetTester tester) async {
    await pumpInvitePage(tester);

    await tester.tap(find.text(group.inviteUrl));
    await tester.pumpAndSettle();

    expect(clipboardWrites, <String>[group.inviteUrl]);
    expect(shareCalls, isEmpty);
  });

  testWidgets('만료된 초대는 복사도 공유도 되지 않는다', (WidgetTester tester) async {
    final Group expiredGroup = Group(
      id: 'g_expired',
      name: '만료집',
      emoji: '🏠',
      inviteCode: '654321',
      // 24시간이 지난 상태(발급 시점이 과거).
      inviteExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      members: <GroupMember>[
        GroupMember(
          userId: InMemoryAuthRepository.defaultUser.id,
          displayName: InMemoryAuthRepository.defaultUser.displayName,
          avatarEmoji: '🙂',
          role: MemberRole.owner,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(
            _FixedGroupsShareRepository(<Group>[expiredGroup]),
          ),
        ],
        child: MaterialApp(home: MemberInvitePage(groupId: expiredGroup.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('만료됨'), findsOneWidget);

    // 링크·코드 필드 탭 → 복사되지 않는다.
    await tester.tap(find.text(expiredGroup.inviteUrl));
    await tester.tap(find.text(expiredGroup.inviteCode));
    await tester.pumpAndSettle();
    expect(clipboardWrites, isEmpty);

    // 하단 CTA도 비활성 — 죽은 링크를 공유 시트로 내보내지 않는다.
    await tester.tap(find.text('만료된 초대는 공유할 수 없어요'));
    await tester.pumpAndSettle();
    expect(shareCalls, isEmpty);
    expect(clipboardWrites, isEmpty);
  });
}
