/// share 페이지 — 멤버 초대(전체 화면, KeepCon 틀 재디자인).
///
/// 초대 링크(복사 버튼) + 6자리 초대코드(발급·카운트다운), 링크 유효기간 안내,
/// "방장만 초대" 권한 토글.
/// 권한 토글은 [ShareRepository.setInviteOwnerOnly]로 그룹 정책에 반영되며
/// 방장만 편집할 수 있다(그룹 상세의 초대 진입점은 [Group.canInvite]로 게이팅).
/// 하단 CTA는 OS 공유 시트를 띄워 설치된 앱(카카오톡·디스코드·LINE 등)으로 초대 링크를
/// 보낸다. 색 하드코딩 없음.
///
/// **만료는 고르는 값이 아니다** — 모든 초대는 발급 시점부터 [Group.inviteValidity](24시간)
/// 동안만 유효한 고정 정책이라, 이 화면은 남은 유효기간을 **표시만** 한다. 만료된 초대를
/// 되살리는 경로는 방장의 "링크 재발급"([ShareRepository.regenerateInviteToken])이다.
///
/// **초대코드는 별개 자격증명이다** — 6자리·5분이고 [ShareRepository.issueInviteCode]로
/// 발급하며, 링크 재발급과 서로를 무효화하지 않는다. 두 이름을 섞지 말 것:
/// 이 화면에서 '초대코드'는 오직 6자리를 가리킨다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/theme/theme_tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/models/group.dart';
import '../../../shared/models/user.dart';
import '../../../shared/diagnostics/report_handled_failure.dart';
import '../../../shared/providers/invite_link_providers.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/providers/session_provider.dart';
import '../../../shared/util/invite_link.dart';
import '../../../shared/util/korean_particle.dart';
import '../state/share_providers.dart';
import '../widgets/share_format.dart';

/// 멤버 초대 화면. 그룹 상세에서 push 한다.
class MemberInvitePage extends ConsumerStatefulWidget {
  const MemberInvitePage({super.key, required this.groupId});

  /// 초대 대상 그룹 id.
  final String groupId;

  @override
  ConsumerState<MemberInvitePage> createState() => _MemberInvitePageState();
}

class _MemberInvitePageState extends ConsumerState<MemberInvitePage> {
  /// 유효기간이 끝나는 순간 화면을 만료 상태로 되돌리는 타이머.
  ///
  /// 만료를 build 시점에만 계산하면, 화면을 열어 둔 채 24시간 경계를 넘겼을 때 복사·공유
  /// 버튼이 계속 살아 있어 이미 죽은 링크를 내보낼 수 있다.
  Timer? _expiryTimer;

  /// 타이머가 걸려 있는 만료 시각 — 같은 값에 중복 등록하지 않기 위한 키.
  /// 재발급으로 [Group.inviteExpiresAt]가 밀리면 값이 달라져 자동으로 다시 건다.
  DateTime? _scheduledFor;

  /// [expiresAt] 도달 시 1회 리빌드를 예약한다(이미 지났으면 걸지 않는다 — 만료는
  /// 재발급 없이는 되돌아가지 않으므로 더 볼 경계가 없다).
  void _scheduleExpiryRefresh(DateTime expiresAt) {
    if (_scheduledFor == expiresAt) return;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _scheduledFor = expiresAt;

    final Duration remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return;
    _expiryTimer = Timer(remaining, () {
      if (mounted) setState(() {});
    });
  }

  /// 초대코드 카운트다운용 1초 틱.
  ///
  /// 링크 만료([_expiryTimer])와 달리 **반복**이어야 한다. 링크는 24시간 뒤 한 번
  /// 경계를 넘을 뿐이라 그 시각에 한 번만 리빌드하면 되지만, 코드는 5분을 초 단위로
  /// 세어 보여주므로 매초 다시 그려야 한다("2:47 후 만료").
  Timer? _codeTicker;

  /// 초대코드를 발급하는 중(버튼 중복 탭 차단).
  bool _issuingCode = false;

  /// 활성 코드가 있는 동안에만 1초 틱을 돌린다.
  ///
  /// 코드가 없거나 만료된 뒤에도 계속 돌면 이 화면을 열어 둔 내내 매초 리빌드가
  /// 일어난다 — 보여줄 것이 바뀌지도 않는데 배터리만 쓴다.
  void _syncCodeTicker({required bool active}) {
    if (active == (_codeTicker != null)) return;
    if (!active) {
      _codeTicker?.cancel();
      _codeTicker = null;
      return;
    }
    _codeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _codeTicker?.cancel();
    super.dispose();
  }

  /// 6자리 초대코드를 발급한다(방장 전용 — 버튼 자체를 방장에게만 노출한다).
  Future<void> _issueCode(String groupId) async {
    if (_issuingCode) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _issuingCode = true);
    try {
      await ref.read(shareRepositoryProvider).issueInviteCode(groupId: groupId);
    } catch (e, s) {
      reportHandledFailure(ref, e, s,
          context: 'MemberInvitePage.issueInviteCode');
      // `on StateError`로 좁히지 않는다 — 백엔드가 던지는 예외(권한 거부·네트워크)가
      // 그대로 빠져나가면 버튼이 죽은 것처럼 보인다(안내가 아예 안 뜬다).
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('초대코드를 발급하지 못했어요. 다시 시도해 주세요.'),
          ));
      }
      return;
    } finally {
      if (mounted) setState(() => _issuingCode = false);
    }
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label${label.eulReul} 복사했어요.')));
  }

  /// OS 공유 시트를 띄워 초대 링크를 보낸다 — 설치된 앱(카카오톡·디스코드·LINE·메시지
  /// 등)이 시트에 나열되고, 사용자가 고른 앱으로 문구+링크가 전달된다.
  ///
  /// 시트를 열 수 없으면 클립보드 복사로 폴백한다. 웹은 Web Share API가 있는
  /// 브라우저에서만 시트가 뜨므로(로컬 개발은 대부분 `web-server` 실행) 이 경로가
  /// 실제로 자주 쓰인다. 패키지 기본 폴백인 메일 앱 실행은 초대 경로로 맞지 않아
  /// [ShareParams.mailToFallbackEnabled]를 꺼서 예외로 받아낸다.
  ///
  /// iPad 팝오버 기준점([ShareParams.sharePositionOrigin])은 이번 범위에서 다루지 않는다.
  Future<void> _share(Group g, String inviteUrl) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '"${g.name}" 그룹에 초대합니다.\n$inviteUrl',
          subject: '"${g.name}" 그룹 초대',
          mailToFallbackEnabled: false,
        ),
      );
    } catch (e, s) {
      reportHandledFailure(ref, e, s, context: 'MemberInvitePage.shareInvite');
      // 시트 미지원·실패 — 링크만 클립보드에 넣고 이유를 알린다.
      await Clipboard.setData(ClipboardData(text: inviteUrl));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('공유 시트를 열 수 없어 초대 링크를 복사했어요.')),
        );
    }
  }

  Future<void> _setOwnerOnly(String groupId, bool value) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shareRepositoryProvider).setInviteOwnerOnly(
            groupId: groupId,
            ownerOnly: value,
          );
    } catch (e, s) {
      reportHandledFailure(ref, e, s,
          context: 'MemberInvitePage.setInviteOwnerOnly');
      // `on StateError`로 좁히면 백엔드 예외(권한 거부·네트워크 등)가 그대로 빠져나가
      // **아무 안내도 없이 스위치만 되돌아간다** — 실패 원인과 무관하게 항상 알린다.
      // 문구도 원인을 특정하지 않는다 — 스위치는 방장에게만 활성화되므로(`iAmOwner`)
      // 권한은 오히려 원인일 가능성이 낮다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('초대 설정을 바꾸지 못했어요. 다시 시도해 주세요.')),
        );
    }
  }

  /// 초대 **링크**를 재발급한다(방장 전용). 기존 링크가 무효화됨을 확인 후 진행한다.
  ///
  /// 6자리 초대코드는 건드리지 않는다 — 아래 다이얼로그 문구가 그것을 명시한다.
  Future<void> _regenerate(String groupId) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('초대 링크 재발급'),
            content: const Text(
              '재발급하면 기존 초대 링크는 더 이상 사용할 수 없어요. 새 링크는 발급 시점부터 '
              '24시간 동안 유효해요. (6자리 초대코드는 영향을 받지 않아요.) 계속할까요?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('닫기'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('재발급'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(shareRepositoryProvider)
          .regenerateInviteToken(groupId: groupId);
    } on StateError catch (e, s) {
      reportHandledFailure(ref, e, s,
          context: 'MemberInvitePage.regenerateInviteToken(guard)');
      // 계약 위반(권한 없음·그룹 삭제됨)은 재시도해도 소용없으니 원인을 알린다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('그룹이 없거나 재발급 권한이 없어요.')),
        );
      return;
    } catch (e, s) {
      reportHandledFailure(ref, e, s,
          context: 'MemberInvitePage.regenerateInviteToken');
      // 네트워크 등 기타 오류 — 재시도가 통할 수 있다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('초대 링크를 재발급하지 못했어요. 다시 시도해 주세요.')),
        );
      return;
    }
    // 성공 처리는 try 밖에서 — 발급은 됐는데 스낵바에서 예외가 나면 실패 안내가 떠 오해한다.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('새 초대 링크를 발급했어요. 24시간 동안 유효해요.')),
      );
  }

  AppBar _navBar() => AppBar(
        centerTitle: true,
        title: Text('멤버 초대', style: context.navTitleStyle),
      );

  @override
  Widget build(BuildContext context) {
    return ref.watch(groupByIdProvider(widget.groupId)).when(
          // 세션/그룹 로딩 중엔 pop 하지 않고 대기(스피너).
          loading: () => Scaffold(
            appBar: _navBar(),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (Object e, StackTrace _) => Scaffold(
            appBar: _navBar(),
            body: const Center(child: Text('그룹을 불러오지 못했어요.')),
          ),
          data: (Group? g) {
            if (g == null) {
              // 로딩이 끝났는데도 그룹이 없다 = 나가기/삭제로 소멸 → 복귀.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) Navigator.of(context).maybePop();
              });
              return const Scaffold(body: SizedBox.shrink());
            }
            return _buildContent(context, g);
          },
        );
  }

  Widget _buildContent(BuildContext context, Group g) {
    final ThemeData theme = Theme.of(context);
    // 세션 정본 직접 소비 — 쓰는 값이 id 뿐이라 `select`로 좁힌다.
    final String? uid = ref.watch(
      sessionUserProvider.select((AsyncValue<User?> s) => s.valueOrNull?.id),
    );
    final bool iAmOwner = uid != null && g.isOwnedBy(uid);
    // 링크 만료와 코드 카운트다운이 **같은 시각**을 봐야 한다. build 안에서 두 번
    // `DateTime.now()`를 부르면 그 사이에 경계를 넘는 조합이 생긴다(드물지만, 두 값이
    // 서로 모순된 화면이 한 프레임 뜬다).
    final DateTime now = DateTime.now();
    final bool expired = g.isInviteExpired(now);
    // 활성 코드가 있는 동안에만 1초 틱을 돌린다(없으면 그릴 것이 바뀌지 않는다).
    _syncCodeTicker(active: g.hasActiveInviteCode(now));
    // 초대 링크의 도메인은 백엔드마다 다르고, 없는 실행도 있다(안드로이드 + 로컬
    // 에뮬레이터). `null`이면 링크 없이 코드만 공유한다.
    final String? origin = ref.watch(inviteOriginProvider);
    final String? inviteUrl = origin == null
        ? null
        : inviteUrlFrom(origin: origin, inviteToken: g.inviteToken);
    // 링크가 **있어도** 이 PC 밖에서는 안 열리는 조합이 있다(웹 + 로컬 에뮬레이터).
    // 딥링크 개발 루프에 필요하니 링크는 남기되, 공유하라고 말하지는 않는다 —
    // 그러지 않으면 이 화면이 스스로 금지한 '그럴듯한 가짜 링크'를 내미는 셈이 된다.
    final bool localOnlyLink = origin != null && !isSharableOrigin(origin);
    // 화면을 열어 둔 채 유효기간이 끝나도 복사·공유가 살아 있지 않게, 만료 시각에
    // 리빌드를 예약한다(재발급으로 만료가 밀리면 새 시각으로 다시 건다).
    _scheduleExpiryRefresh(g.inviteExpiresAt);

    return Scaffold(
      appBar: _navBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: <Widget>[
            Text(
              '"${g.name}" 그룹으로 초대',
              style: context.inviteTitleStyle,
            ),
            const SizedBox(height: 8),
            Text(
              (inviteUrl == null || localOnlyLink)
                  ? '아래 코드를 공유하세요.'
                  : '아래 링크나 코드를 공유하세요.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),

            // 초대 링크 / 초대코드. 만료된 코드는 배포해봐야 참여가 거부되므로
            // 복사 자체를 막는다(재발급이 유일한 유효 경로).
            //
            // 링크 자체가 없는 실행도 있다(안드로이드 + 로컬 에뮬레이터 — App Links를
            // 검증해 줄 도메인이 없다). 그때 빈 칸이나 그럴듯한 가짜 링크를 보여주면
            // 눌렀을 때 아무 일도 안 일어나거나 **다른 백엔드로 간다.** 사실을 적는다.
            if (inviteUrl == null)
              _NoInviteLinkNotice(theme: theme)
            else
              _CopyField(
                label: '초대 링크',
                value: inviteUrl,
                // 로컬 전용 링크에서도 **복사는 남긴다** — 바로 아래 캡션이 경고하고,
                // 링크 텍스트가 선택 불가라 딥링크 개발 루프에서 값을 얻을 유일한
                // 수단이다. 하단 CTA(공유 시트)는 캡션에서 멀고 한 번에 밖으로
                // 나가므로 그쪽만 잠근다.
                onCopy: expired ? null : () => _copy(inviteUrl, '초대 링크'),
              ),
            if (localOnlyLink)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '이 링크는 이 PC에서만 열려요(로컬 에뮬레이터). 초대코드도 마찬가지예요 '
                  '— 에뮬레이터 데이터는 이 PC 안에만 있어요. 다른 기기에서 참여하려면 '
                  'dev 백엔드로 실행하세요.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            // 방장만 재발급 가능 — 기존 링크 무효화.
            if (iAmOwner)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _regenerate(g.id),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('링크 재발급'),
                ),
              ),
            const SizedBox(height: 28),

            // ── 초대코드(6자리 OTP) ─────────────────────────────────
            //
            // 링크와 **다른 전달 수단**이다: 링크는 카카오톡으로 보내는 것, 코드는
            // 옆사람에게 불러주는 것. 그래서 수명도 다르다(24시간 vs 5분) — 6자리는
            // 열거 가능한 공간이라 짧은 노출 창이 방어의 전부다.
            //
            // ⚠️ 여기에 예전처럼 `g.inviteToken`을 "초대코드"라는 이름으로 두면 안 된다.
            //    22자 토큰은 불러줄 수 없는 값이고, 진짜 코드와 이름이 겹쳐 사용자가
            //    어느 쪽을 부르는지 알 수 없게 된다. 토큰은 링크가 이미 싣고 있다.
            _InviteCodeSection(
              group: g,
              now: now,
              iAmOwner: iAmOwner,
              issuing: _issuingCode,
              onIssue: () => _issueCode(g.id),
              onCopy: (String code) => _copy(code, '초대코드'),
            ),
            const SizedBox(height: 32),

            // 초대 유효기간 — 24시간 고정 정책이라 선택지 없이 상태만 보여준다.
            Row(
              children: <Widget>[
                Text('링크 유효기간', style: context.itemTitleStyle),
                const Spacer(),
                Text(
                  expired
                      ? '만료됨'
                      : '${formatInviteExpiry(g.inviteExpiresAt)}까지',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              expired
                  ? (iAmOwner
                      ? '초대 링크가 만료됐어요. 링크를 재발급하면 24시간 동안 다시 쓸 수 있어요.'
                      : '초대 링크가 만료됐어요. 방장에게 링크 재발급을 요청하세요.')
                  : '초대 링크는 발급 후 24시간 동안만 쓸 수 있어요.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),

            // 방장만 초대 가능 토글.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadii.panel),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '방장만 초대 가능',
                          style: context.itemTitleStyle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          iAmOwner
                              ? '켜면 방장 외 멤버는 초대할 수 없어요.'
                              : '방장만 이 설정을 바꿀 수 있어요.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Switch(
                    value: g.inviteOwnerOnly,
                    // 정책 변경은 방장만. 일반 멤버에게는 비활성(현재 정책만 표시).
                    onChanged:
                        iAmOwner ? (bool v) => _setOwnerOnly(g.id, v) : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // 하단 고정 CTA — OS 공유 시트로 초대 링크 전달(상단 필드는 복사 전용).
      // 만료된 초대는 받는 쪽이 참여할 수 없으므로 내보내는 경로를 함께 막는다.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: ElevatedButton.icon(
            // 로컬 전용 링크도 잠근다 — 캡션으로 사실을 적어 두는 것만으로는
            // **공유 시트로 내보내는 경로**가 열려 있다. 받는 사람은 열 수 없다.
            onPressed: (expired || inviteUrl == null || localOnlyLink)
                ? null
                : () => _share(g, inviteUrl),
            icon: const Icon(Icons.share, size: 20),
            label: Text(switch ((expired, inviteUrl, localOnlyLink)) {
              (true, _, _) => '만료된 초대는 공유할 수 없어요',
              (_, null, _) => '이 환경에서는 링크를 공유할 수 없어요',
              (_, _, true) => '이 링크는 이 PC에서만 열려요',
              _ => '어플로 공유하기',
            }),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.button),
              ),
              padding: const EdgeInsets.symmetric(vertical: 17),
              textStyle:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

/// 라벨 + 값 + 복사 버튼 필드(아웃라인). [emphasize]면 값이 코드처럼 크게(자간 포함).
///
/// [onCopy]가 `null`이면 비활성(만료된 초대) — 흐리게 표시하고 탭·복사 버튼을 막는다.
/// 초대 링크를 만들 수 없는 실행에서 그 사실과 대안을 알린다.
///
/// 빈 칸이나 그럴듯한 가짜 링크 대신 이걸 보여주는 이유: 링크가 없다는 것은 결함이 아니라
/// 이 조합(안드로이드 + 로컬 에뮬레이터)의 성질이고, 코드 공유라는 대안이 실제로 있다.
class _NoInviteLinkNotice extends StatelessWidget {
  const _NoInviteLinkNotice({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.link_off,
              size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '이 환경에서는 초대 링크를 만들 수 없어요.\n'
              '같은 백엔드에 붙은 기기끼리는 아래 초대코드로 참여할 수 있어요.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 6자리 초대코드 구역 — 발급 버튼, 코드 표시, 남은 시간 카운트다운.
///
/// 상태는 셋뿐이고 [Group.hasActiveInviteCode] 하나로 갈린다:
/// - **활성** — 코드와 "N:NN 후 만료"를 보여주고, 방장에게는 다시 발급 버튼을 준다.
/// - **비활성(방장)** — 발급 버튼과 정책 안내.
/// - **비활성(멤버)** — 방장에게 요청하라는 안내(발급 권한이 없다).
///
/// 코드 값 자체를 `null` 여부로 판정하지 않는 이유는 만료된 값이 그대로 남아 있기
/// 때문이다([Group.inviteCode] 참조) — 판정은 항상 시각과 함께 한다.
class _InviteCodeSection extends StatelessWidget {
  const _InviteCodeSection({
    required this.group,
    required this.now,
    required this.iAmOwner,
    required this.issuing,
    required this.onIssue,
    required this.onCopy,
  });

  final Group group;
  final DateTime now;
  final bool iAmOwner;
  final bool issuing;
  final VoidCallback onIssue;
  final void Function(String code) onCopy;

  /// 남은 시간을 `M:SS`로. 초 단위 올림이라 "0:00"이 뜨지 않는다 —
  /// 0을 보여주면 아직 쓸 수 있는 코드가 만료된 것처럼 읽힌다.
  static String _countdown(Duration d) {
    final int total =
        d.inMilliseconds <= 0 ? 0 : (d.inMilliseconds / 1000).ceil();
    final int m = total ~/ 60;
    final int s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Duration? left = group.inviteCodeRemaining(now);
    final String? code = left == null ? null : group.inviteCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('초대코드', style: context.itemTitleStyle),
            const Spacer(),
            if (left != null)
              Text(
                '${_countdown(left)} 후 만료',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (code != null)
          _CopyField(
            label: '옆에 있는 사람에게 불러주세요',
            value: code,
            emphasize: true,
            onCopy: () => onCopy(code),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.panel),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
            ),
            child: Text(
              iAmOwner
                  ? '아직 발급된 초대코드가 없어요. 발급하면 5분 동안 쓸 수 있어요.'
                  : '아직 발급된 초대코드가 없어요. 방장에게 발급을 요청하세요.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        // 발급은 방장만 — 교체할 때 옛 코드의 조회 문서를 지워야 하는데 그 권한이
        // 방장에게만 있다(계약 참조). 멤버는 링크로 초대한다.
        if (iAmOwner)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: issuing ? null : onIssue,
              icon: issuing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.password_outlined, size: 18),
              label: Text(code != null ? '새 코드 발급' : '초대코드 발급하기'),
            ),
          ),
        const SizedBox(height: 2),
        Text(
          '초대코드는 발급 후 5분 동안만 쓸 수 있어요. 새로 발급하면 이전 코드는 바로 만료돼요.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _CopyField extends StatelessWidget {
  const _CopyField({
    required this.label,
    required this.value,
    required this.onCopy,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Opacity(
      opacity: onCopy == null ? 0.5 : 1,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        child: InkWell(
          onTap: onCopy,
          borderRadius: BorderRadius.circular(AppRadii.panel),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.panel),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(label, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      Text(
                        value,
                        style: emphasize
                            ? context.inviteTokenStyle
                            : theme.textTheme.bodyLarge?.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: '복사',
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
