/// share 페이지 — 멤버 초대(전체 화면, KeepCon 틀 재디자인).
///
/// 초대 URL + 초대코드(각 복사 버튼), 만료시간 선택(프로토타입 UI), "방장만 초대"
/// 권한 토글. 권한 토글은 [ShareRepository.setInviteOwnerOnly]로 그룹 정책에 반영되며
/// 방장만 편집할 수 있다(그룹 상세의 초대 진입점은 [Group.canInvite]로 게이팅).
/// 하단 CTA는 OS 공유 시트를 띄워 설치된 앱(카카오톡·디스코드·LINE 등)으로 초대 링크를
/// 보낸다. 색 하드코딩 없음. 실제 초대 발송/만료는 후속 계약에서 연동한다.
library;

import 'package:flutter/material.dart';
import '../../../shared/theme/theme_tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/models/group.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/providers/session_provider.dart';
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
  /// 만료 설정 요청 진행 중 여부(중복 탭 방지).
  bool _applyingExpiry = false;

  /// 마지막으로 탭한 만료 선택지(버튼 하이라이트용 로컬 상태).
  ///
  /// 계약의 [Group.inviteExpiresAt]는 절대 시각이라 유한 만료를 특정 버킷으로 되돌릴 수
  /// 없으므로, 방금 적용한 선택지를 즉시 강조하기 위한 표시 전용 값이다(진실은 "현재:" 텍스트).
  InviteExpiry? _pendingSelection;

  /// 버튼 하이라이트 대상. 방금 탭한 값이 있으면 그것을, 없고 만료가 없으면(무제한)
  /// [InviteExpiry.never]를, 유한 만료면 `null`(강조 없음)을 반환한다.
  InviteExpiry? _selectedExpiryFor(Group g) {
    if (_pendingSelection != null) return _pendingSelection;
    if (g.inviteExpiresAt == null) return InviteExpiry.never;
    return null;
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
  Future<void> _share(Group g) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '"${g.name}" 그룹에 초대합니다.\n${g.inviteUrl}',
          subject: '"${g.name}" 그룹 초대',
          mailToFallbackEnabled: false,
        ),
      );
    } catch (_) {
      // 시트 미지원·실패 — 링크만 클립보드에 넣고 이유를 알린다.
      await Clipboard.setData(ClipboardData(text: g.inviteUrl));
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
    } on StateError {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('방장만 이 설정을 바꿀 수 있어요.')));
    }
  }

  /// 초대코드 만료 기간을 계약에 반영한다(방장 전용). 성공/거부를 스낵바로 알린다.
  Future<void> _setExpiry(String groupId, InviteExpiry expiry) async {
    if (_applyingExpiry) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _applyingExpiry = true;
      _pendingSelection = expiry; // 즉시 하이라이트.
    });
    try {
      await ref.read(shareRepositoryProvider).setInviteExpiry(
            groupId: groupId,
            expiry: expiry,
          );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(expiry == InviteExpiry.never
              ? '초대코드 만료를 해제했어요.'
              : '초대코드 만료를 ${expiry.label}(으)로 설정했어요.'),
        ));
    } on StateError {
      // 설정이 실제로 바뀌지 않았으므로 하이라이트도 되돌린다.
      if (mounted) setState(() => _pendingSelection = null);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('방장만 이 설정을 바꿀 수 있어요.')));
    } catch (_) {
      // 네트워크 등 기타 오류도 실패를 알리고 선택 상태를 복구한다.
      if (mounted) setState(() => _pendingSelection = null);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('만료 설정을 변경하지 못했어요. 다시 시도해 주세요.')),
        );
    } finally {
      if (mounted) setState(() => _applyingExpiry = false);
    }
  }

  /// 초대코드를 재발급한다(방장 전용). 기존 코드/링크가 무효화됨을 확인 후 진행한다.
  Future<void> _regenerate(String groupId) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('초대코드 재발급'),
            content: const Text('재발급하면 기존 코드와 링크는 더 이상 사용할 수 없어요. 계속할까요?'),
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
          .regenerateInviteCode(groupId: groupId);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('새 초대코드를 발급했어요.')));
    } on StateError {
      // StateError는 권한 외에 그룹 없음(삭제됨)도 포함하므로 중립적으로 안내한다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('그룹이 없거나 재발급 권한이 없어요.')),
        );
    } catch (_) {
      // 네트워크 등 기타 오류.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('초대코드를 재발급하지 못했어요. 다시 시도해 주세요.')),
        );
    }
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
            Text('아래 링크나 코드를 공유하세요.', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 28),

            // 초대 링크 / 초대코드.
            _CopyField(
              label: '초대 링크',
              value: g.inviteUrl,
              onCopy: () => _copy(g.inviteUrl, '초대 링크'),
            ),
            const SizedBox(height: 16),
            _CopyField(
              label: '초대코드',
              value: g.inviteCode,
              emphasize: true,
              onCopy: () => _copy(g.inviteCode, '초대코드'),
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

            // 초대코드 만료.
            Row(
              children: <Widget>[
                Text('초대코드 만료', style: context.itemTitleStyle),
                const Spacer(),
                Text(
                  g.inviteExpiresAt == null
                      ? '현재: 무제한'
                      : '현재: ${formatInviteExpiry(g.inviteExpiresAt!)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              iAmOwner
                  ? '선택한 기간이 지나면 이 코드로 참여할 수 없어요.'
                  : '방장만 만료 기간을 바꿀 수 있어요.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                for (int i = 0;
                    i < InviteExpiry.values.length;
                    i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _ExpiryButton(
                      label: InviteExpiry.values[i].label,
                      selected: _selectedExpiryFor(g) == InviteExpiry.values[i],
                      // 방장만 변경 가능. 적용 중엔 중복 탭 방지로 비활성.
                      onTap: (iAmOwner && !_applyingExpiry)
                          ? () => _setExpiry(g.id, InviteExpiry.values[i])
                          : null,
                    ),
                  ),
                ],
              ],
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: ElevatedButton.icon(
            onPressed: () => _share(g),
            icon: const Icon(Icons.ios_share, size: 20),
            label: const Text('어플로 공유하기'),
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
class _CopyField extends StatelessWidget {
  const _CopyField({
    required this.label,
    required this.value,
    required this.onCopy,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
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
                          ? context.inviteCodeStyle
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
    );
  }
}

/// 만료 선택 버튼 한 칸 — 선택 시 brand 채움+체크, 아니면 서피스.
///
/// [onTap]이 `null`이면 비활성(방장 아님/적용 중) — 흐리게 표시하고 탭을 막는다.
class _ExpiryButton extends StatelessWidget {
  const _ExpiryButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool enabled = onTap != null;
    final Color bg = selected ? scheme.primary : scheme.surfaceContainerHighest;
    final Color fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Opacity(
      opacity: enabled || selected ? 1 : 0.5,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.action),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.action),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (selected) ...<Widget>[
                  Icon(Icons.check, size: 15, color: fg),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
