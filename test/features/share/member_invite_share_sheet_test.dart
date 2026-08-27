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
/// - (c) **만료된 초대** — 24시간이 지난 코드는 받는 쪽이 요청조차 할 수 없으므로
///   (`requestToJoin` 가드) 내보내는 경로(복사·공유 시트)를 전부 막는다.
///   죽은 링크를 배포하는 회귀 고정.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/pages/member_invite_page.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/diagnostics/error_reporter.dart';
import 'package:keepcon/shared/providers/error_reporter_provider.dart';
import 'package:keepcon/shared/providers/invite_link_providers.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';
import 'package:keepcon/shared/util/invite_link.dart';

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

/// 보고된 라벨을 기록하는 리포터.
///
/// 기본 구현은 콘솔에 쓰므로 이 테스트가 일부러 태우는 실패가 스택 트레이스째
/// CI 로그에 쏟아진다 — 진짜 실패와 섞인다. 겸사겸사 배선도 고정한다.
class _SpyErrorReporter implements ErrorReporter {
  final List<String> contexts = <String>[];

  @override
  void report(Object error, StackTrace stack, {required String context}) {
    contexts.add(context);
  }
}

/// 테스트가 쓰는 초대 링크 origin. 화면은 `inviteOriginProvider`로 이 값을 받는다 —
/// 예전처럼 모델이 prod 도메인을 들고 있지 않으므로 여기서 정해 주입해야 한다.
const String testInviteOrigin = 'https://keepcon-dev.web.app';

/// [g]의 초대 링크(화면이 만드는 것과 같은 규칙).
String inviteUrlOf(Group g) =>
    inviteUrlFrom(origin: testInviteOrigin, inviteToken: g.inviteToken);

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

  late _SpyErrorReporter reporter;

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
    reporter = _SpyErrorReporter();

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
          errorReporterProvider.overrideWithValue(reporter),
          shareRepositoryProvider.overrideWithValue(share),
          inviteOriginProvider.overrideWithValue(testInviteOrigin),
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
    expect(shareCalls.single['text'], contains(inviteUrlOf(group)));
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

    expect(clipboardWrites, <String>[inviteUrlOf(group)]);
    expect(find.text('공유 시트를 열 수 없어 초대 링크를 복사했어요.'), findsOneWidget);
    // 폴백으로 넘어간 이유도 개발자에게 남는다 — 웹에서 실제로 타는 경로다.
    expect(reporter.contexts, <String>['MemberInvitePage.shareInvite']);
  });

  testWidgets('origin이 없는 실행은 링크 대신 초대코드를 안내한다', (WidgetTester tester) async {
    // 안드로이드 + 로컬 에뮬레이터 — assetlinks.json을 서빙할 도메인이 없어
    // 만들 수 있는 링크가 없다. 빈 칸이나 그럴듯한 가짜 링크를 보여주면 눌렀을 때
    // 아무 일도 안 일어나거나 다른 백엔드로 간다.
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          errorReporterProvider.overrideWithValue(reporter),
          shareRepositoryProvider.overrideWithValue(share),
          inviteOriginProvider.overrideWithValue(null),
        ],
        child: MaterialApp(home: MemberInvitePage(groupId: group.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('이 환경에서는 초대 링크를 만들 수 없어요'), findsOneWidget);
    // 링크 복사 필드가 없다.
    expect(find.textContaining('/invite/'), findsNothing);
    // 링크가 없을 때 남는 경로는 **6자리 초대코드**다. 예전에는 22자 토큰을
    // '초대코드'라는 이름으로 그대로 보여줬는데, 그 값은 불러줄 수도 없고 진짜
    // 초대코드와 이름이 겹쳐 어느 쪽을 부르는 건지 알 수 없었다.
    expect(find.text(group.inviteToken), findsNothing);
    expect(find.text('초대코드'), findsOneWidget);
    expect(
      find.textContaining('아직 발급된 초대코드가 없어요'),
      findsOneWidget,
    );
    // 공유 CTA는 비활성이고 이유를 말한다.
    final ElevatedButton cta = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '이 환경에서는 링크를 공유할 수 없어요'),
    );
    expect(cta.onPressed, isNull);
  });

  testWidgets('로컬 전용 링크는 공유 시트로 내보낼 수 없다', (WidgetTester tester) async {
    // 웹 + 로컬 에뮬레이터는 `http://localhost:<포트>` 링크를 만든다. 캡션으로 사실을
    // 적어 두는 것만으로는 **공유 시트로 내보내는 경로**가 열려 있어, 받는 사람은
    // 열 수 없는 링크를 받는다.
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          errorReporterProvider.overrideWithValue(reporter),
          shareRepositoryProvider.overrideWithValue(share),
          inviteOriginProvider.overrideWithValue('http://localhost:8082'),
        ],
        child: MaterialApp(home: MemberInvitePage(groupId: group.id)),
      ),
    );
    await tester.pumpAndSettle();

    // 링크 자체는 보인다(딥링크 개발 루프에 필요하다).
    expect(find.textContaining('localhost:8082/invite/'), findsOneWidget);
    // 다만 공유하라고 말하지 않고, 내보내는 경로를 잠근다.
    // 캡션과 CTA 라벨을 따로 센다 — `findsWidgets`(≥1)면 CTA 하나로 충족돼
    // **캡션이 통째로 사라져도 통과한다**(뮤테이션으로 확인).
    expect(find.textContaining('초대코드도 마찬가지예요'), findsOneWidget);
    final ElevatedButton cta = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '이 링크는 이 PC에서만 열려요'),
    );
    expect(cta.onPressed, isNull);
  });

  testWidgets('상단 "초대 링크" 필드의 복사는 그대로다(공유와 별개 경로)',
      (WidgetTester tester) async {
    await pumpInvitePage(tester);

    await tester.tap(find.text(inviteUrlOf(group)));
    await tester.pumpAndSettle();

    expect(clipboardWrites, <String>[inviteUrlOf(group)]);
    expect(shareCalls, isEmpty);
  });

  /// 방장 1명(=현재 사용자)짜리 최소 그룹. [expiresAt]로 초대 유효기간을 직접 정한다.
  Group groupExpiringAt(DateTime expiresAt) => Group(
        id: 'g_expiry',
        name: '만료집',
        emoji: '🏠',
        inviteToken: '654321',
        inviteExpiresAt: expiresAt,
        members: <GroupMember>[
          GroupMember(
            userId: InMemoryAuthRepository.defaultUser.id,
            displayName: InMemoryAuthRepository.defaultUser.displayName,
            avatarEmoji: '🙂',
            role: MemberRole.owner,
          ),
        ],
      );

  /// 고정 그룹 스텁을 주입해 초대 화면을 띄운다.
  Future<void> pumpWithGroup(WidgetTester tester, Group g) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          errorReporterProvider.overrideWithValue(reporter),
          shareRepositoryProvider
              .overrideWithValue(_FixedGroupsShareRepository(<Group>[g])),
          inviteOriginProvider.overrideWithValue(testInviteOrigin),
        ],
        child: MaterialApp(home: MemberInvitePage(groupId: g.id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('화면을 열어 둔 채 유효기간이 끝나면 복사·공유가 잠긴다', (WidgetTester tester) async {
    // 곧 만료되는 초대(진입 시점엔 아직 유효).
    final Group g =
        groupExpiringAt(DateTime.now().add(const Duration(milliseconds: 800)));
    await pumpWithGroup(tester, g);

    expect(find.text('어플로 공유하기'), findsOneWidget);

    // 실제 시각이 만료를 넘기게 두고(runAsync = 실 클럭), 가상 시각을 밀어 예약된
    // 타이머를 발화시킨다. 둘 다 필요하다 — 만료 판정은 DateTime.now()를 본다.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('만료됨'), findsOneWidget);
    expect(find.text('만료된 초대는 공유할 수 없어요'), findsOneWidget);

    await tester.tap(find.text(inviteUrlOf(g)));
    await tester.tap(find.text('만료된 초대는 공유할 수 없어요'));
    await tester.pumpAndSettle();
    expect(clipboardWrites, isEmpty);
    expect(shareCalls, isEmpty);
  });

  testWidgets('이미 만료된 초대로 진입하면 복사도 공유도 되지 않는다', (WidgetTester tester) async {
    // 24시간이 지난 상태(발급 시점이 과거) — 레거시 문서를 epoch로 읽는 경우도 여기 해당.
    final Group g =
        groupExpiringAt(DateTime.now().subtract(const Duration(minutes: 1)));
    await pumpWithGroup(tester, g);

    expect(find.text('만료됨'), findsOneWidget);

    // 링크 필드 탭 → 복사되지 않는다.
    //
    // 초대코드는 여기서 보지 않는다 — **링크 만료와 무관한 별개 자격증명**이라
    // (5분 vs 24시간) 링크가 죽었다고 코드까지 잠글 이유가 없다. 코드 쪽 만료는
    // `share_repository_invite_code_test.dart`가 자기 시계로 검증한다.
    await tester.tap(find.text(inviteUrlOf(g)));
    await tester.pumpAndSettle();
    expect(clipboardWrites, isEmpty);

    // 하단 CTA도 비활성 — 죽은 링크를 공유 시트로 내보내지 않는다.
    await tester.tap(find.text('만료된 초대는 공유할 수 없어요'));
    await tester.pumpAndSettle();
    expect(shareCalls, isEmpty);
    expect(clipboardWrites, isEmpty);
  });
}
