/// share 페이지 — 멤버 초대(전체 화면, KeepCon 틀 재디자인).
///
/// 초대 URL + 초대코드(각 복사 버튼), 유효기간 안내, "방장만 초대" 권한 토글.
/// 권한 토글은 [ShareRepository.setInviteOwnerOnly]로 그룹 정책에 반영되며
/// 방장만 편집할 수 있다(그룹 상세의 초대 진입점은 [Group.canInvite]로 게이팅).
/// 하단 CTA는 OS 공유 시트를 띄워 설치된 앱(카카오톡·디스코드·LINE 등)으로 초대 링크를
/// 보낸다. 색 하드코딩 없음.
///
/// **만료는 고르는 값이 아니다** — 모든 초대는 발급 시점부터 [Group.inviteValidity](24시간)
/// 동안만 유효한 고정 정책이라, 이 화면은 남은 유효기간을 **표시만** 한다. 만료된 초대를
/// 되살리는 경로는 방장의 "코드 재발급"([ShareRepository.regenerateInviteToken])뿐이다.
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

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
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

  /// 초대코드를 재발급한다(방장 전용). 기존 코드/링크가 무효화됨을 확인 후 진행한다.
  Future<void> _regenerate(String groupId) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('초대코드 재발급'),
            content: const Text(
              '재발급하면 기존 코드와 링크는 더 이상 사용할 수 없어요. '
              '새 코드는 발급 시점부터 24시간 동안 유효해요. 계속할까요?',
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
          const SnackBar(content: Text('초대코드를 재발급하지 못했어요. 다시 시도해 주세요.')),
        );
      return;
    }
    // 성공 처리는 try 밖에서 — 발급은 됐는데 스낵바에서 예외가 나면 실패 안내가 떠 오해한다.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('새 초대코드를 발급했어요. 24시간 동안 유효해요.')),
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
    final bool expired = g.isInviteExpired(DateTime.now());
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
            const SizedBox(height: 16),
            _CopyField(
              label: '초대코드',
              value: g.inviteToken,
              emphasize: true,
              onCopy: expired ? null : () => _copy(g.inviteToken, '초대코드'),
            ),
            // 방장만 재발급 가능 — 기존 코드/링크 무효화.
            if (iAmOwner)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _regenerate(g.id),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('코드 재발급'),
                ),
              ),
            const SizedBox(height: 32),

            // 초대 유효기간 — 24시간 고정 정책이라 선택지 없이 상태만 보여준다.
            Row(
              children: <Widget>[
                Text('초대 유효기간', style: context.itemTitleStyle),
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
                      ? '초대 링크가 만료됐어요. 코드를 재발급하면 24시간 동안 다시 쓸 수 있어요.'
                      : '초대 링크가 만료됐어요. 방장에게 코드 재발급을 요청하세요.')
                  : '초대 링크와 초대코드는 발급 후 24시간 동안만 쓸 수 있어요.',
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
