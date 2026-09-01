/// share 페이지 — 짧은 입력용 바텀시트 모음.
///
/// 그룹 생성 / 그룹 참여 / 기프티콘 공유처럼 입력이 짧은 흐름은 전체 화면 push 대신
/// [showModalBottomSheet]로 처리한다. 상태는 계약 [ShareRepository]에 반영된다
/// (SSOT [shareRepositoryProvider] 소비). 색/라운드는 전부 `Theme.of(context)`에서 온다.
library;

import 'package:flutter/material.dart';
import '../../../shared/theme/theme_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/models/group.dart';
import '../../../shared/diagnostics/report_handled_failure.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/repositories/share_repository.dart';
import '../../../shared/util/korean_particle.dart';
import '../../../shared/widgets/inline_error_banner.dart';
import '../state/share_providers.dart';
import 'share_common.dart';
import 'share_format.dart';

/// 바텀시트 공통 컨테이너 — 키보드 인셋·핸들·패딩을 통일한다.
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// 그룹 생성 바텀시트 — 그룹명 + 이모지 선택. 생성 시 [ShareRepository]에 반영한다.
Future<void> showCreateGroupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (BuildContext ctx) => const _CreateGroupSheet(),
  );
}

class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet();

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  static const List<String> _emojis = <String>[
    '🏠',
    '👥',
    '💼',
    '🎓',
    '🎁',
    '⚽',
    '🍻',
    '✈️',
  ];
  final TextEditingController _nameCtrl = TextEditingController();
  String _emoji = _emojis.first;
  int _maxMembers = Group.defaultMaxMembers;

  /// 생성 중 — 버튼과 엔터를 함께 잠근다. 두 번 들어오면 **같은 이름의 그룹이 두 개**
  /// 만들어진다(Firebase 구현에서는 `inviteTokens` 문서도 두 벌). 진입점이 둘이라
  /// (버튼 · `onSubmitted`) 더 쉽게 겹친다.
  /// 형제 `_JoinGroupSheetState._sending`과 같은 규약이다.
  bool _sending = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String name = _nameCtrl.text.trim();
    if (name.isEmpty || _sending) return;
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    // try는 **저장소 호출만** 감싼다(참여 시트와 동일 규약 — `_JoinGroupSheetState._submit`).
    try {
      await ref
          .read(shareRepositoryProvider)
          .createGroup(name: name, emoji: _emoji, maxMembers: _maxMembers);
    } catch (e, s) {
      reportHandledFailure(ref, e, s, context: 'CreateGroupSheet.createGroup');
      if (mounted) setState(() => _sending = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 그룹을 만들 수 없어요.')));
      return;
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('"$name" 그룹을 만들었어요.')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _SheetScaffold(
      title: '그룹 만들기',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('아이콘', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final String e in _emojis)
                GestureDetector(
                  onTap: () => setState(() => _emoji = e),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _emoji == e
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 20)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('그룹 이름', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: '예) 우리 가족'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Text('최대 인원 (방장 포함)', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final int cap in Group.memberCapPresets)
                ChoiceChip(
                  label: Text('$cap명'),
                  selected: _maxMembers == cap,
                  onSelected: (_) => setState(() => _maxMembers = cap),
                ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _sending ? null : _submit,
            child: Text(_sending ? '만드는 중…' : '만들기'),
          ),
        ],
      ),
    );
  }
}

/// 그룹 참여 **요청** 바텀시트. [ShareRepository.requestToJoin]으로
/// **요청만** 보낸다 — 방장이 승인하기 전까지 멤버가 아니다(v3.8에서 즉시 합류 경로 삭제).
///
/// 진입 경로에 따라 두 모습을 갖는다:
///  - [initialToken]가 있으면(초대 딥링크) **확인 모드** — 버튼 하나만 보여준다.
///  - 없으면(공유 탭의 참여 버튼) **입력 모드** — 자격증명 입력란을 보여준다.
Future<void> showJoinGroupSheet(BuildContext context, {String? initialToken}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _JoinGroupSheet(initialToken: initialToken),
  );
}

class _JoinGroupSheet extends ConsumerStatefulWidget {
  const _JoinGroupSheet({this.initialToken});

  /// 딥링크로 전달된 **링크 토큰**. 있으면 확인 모드로 연다.
  ///
  /// 6자리 초대코드가 아니다 — 딥링크가 싣는 것은 항상 링크 쪽 자격증명이다.
  final String? initialToken;

  @override
  ConsumerState<_JoinGroupSheet> createState() => _JoinGroupSheetState();
}

class _JoinGroupSheetState extends ConsumerState<_JoinGroupSheet> {
  late final TextEditingController _codeCtrl = TextEditingController();

  /// 요청을 보내는 중(버튼 중복 탭 차단).
  bool _sending = false;

  /// 요청이 접수됐다 — 시트 내용을 대기 안내로 바꾼다.
  bool _requested = false;

  /// 확인 모드에서 코드 입력으로 갈아탔는지. **단방향이다**(돌아가는 버튼은 없다) —
  /// 전환은 링크가 실패한 뒤에만 뜨므로, 되돌아가 봐야 방금 거부당한 링크를 다시
  /// 보내는 길뿐이다.
  ///
  /// 모드를 [widget.initialToken]을 비우는 것으로 표현할 수 없어 플래그를 둔다
  /// (위젯 필드는 `final`이다).
  bool _manualEntry = false;

  /// 요청이 한 번이라도 실패했는지 — 확인 모드의 코드 입력 전환을 이때만 보여준다.
  ///
  /// 성공 경로를 버튼 하나로 유지하려는 것이다. 만료된 링크로 거절당한 사람에게
  /// 방장이 6자리 코드를 불러 주는 것이 정상 경로라(코드는 5분이라 만료가 잦다),
  /// 갈아탈 길은 **실패한 뒤에** 실제로 필요해진다.
  bool _failed = false;

  /// 딥링크로 받은 토큰을 그대로 보내는 모드인지.
  bool get _isConfirmMode => widget.initialToken != null && !_manualEntry;

  /// 요청에 쓸 자격증명 — 확인 모드면 딥링크 토큰, 입력 모드면 입력값.
  ///
  /// **두 갈래 모두 `trim`한다.** 딥링크 토큰은 지금은 파서가 이미 다듬어 주지만,
  /// 그건 호출부 한 곳의 구현 세부라 여기서 기대면 호출부가 늘 때 조용히 깨진다
  /// (공백이 섞인 토큰은 '없는 토큰'으로 거부된다).
  String get _credential =>
      (_isConfirmMode ? widget.initialToken! : _codeCtrl.text).trim();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String token = _credential;
    if (token.isEmpty || _sending) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    // try는 **저장소 호출만** 감싼다. 성공 뒤의 화면 전환까지 넣으면, 요청은 접수됐는데
    // 화면 정리에서 예외가 났을 때 실패 안내가 떠 사용자가 실패했다고 오해한다.
    try {
      await ref.read(shareRepositoryProvider).requestToJoin(token);
    } catch (e, s) {
      reportHandledFailure(ref, e, s, context: 'JoinGroupSheet.requestToJoin');
      // `on StateError`로 좁히면 백엔드가 던지는 예외(권한 거부·네트워크 등)가 그대로
      // 빠져나가 **아무 안내도 없이 시트가 멈춘다** — 사용자에겐 버튼이 죽은 것으로만
      // 보인다. 실패 원인과 무관하게 항상 결과를 알려준다.
      // (예외 타입으로 백엔드를 구분하지 않으므로 UI가 firebase에 의존하지 않는다.)
      //
      // ⚠️ 정원은 여기서 말하지 않는다 — 계약상 정원 검사는 **승인 시점**이라
      //    요청 단계의 실패 사유가 아니다(대기자가 자리를 선점하지 못하게 한 설계).
      //
      // **만료만은 구별해서 말한다.** 초대코드는 5분이라 만료가 정상 경로인데,
      // "잘못됐거나 만료됐을 수 있어요"로 뭉뚱그리면 사용자는 코드를 잘못 들었는지
      // 시간이 지난 것인지 알 수 없어 **같은 코드를 계속 다시 입력한다.** 만료라고
      // 말해 주면 다음 행동이 하나로 정해진다 — 방장에게 재발급을 요청한다.
      //
      // 판정은 메시지 문자열이 아니라 **타입**으로 한다([InviteExpiredException]) —
      // `contains('expired')` 같은 검사는 메시지를 다듬는 순간 조용히 깨진다.
      //
      // ⚠️ 그런데 그 예외는 **초대코드 전용이 아니다** — 계약이 `credential`을 "링크
      //    토큰 또는 6자리 코드"로 정의하므로 만료된 **링크**도 같은 예외를 던진다.
      //    하나로 뭉뚱그리면 링크가 만료된 사람에게 "새 **코드**를 요청하세요"라고
      //    말하게 된다 — 코드를 받아 와도 만료된 링크는 그대로라 다음 행동이 틀린
      //    안내다.
      //
      // **어느 쪽인지는 화면이 판단하지 않는다** — 예외가 싣고 온 `isCode`를 그대로
      // 쓴다. 저장소는 코드 조회 문서를 먼저 보고 없으면 링크 토큰으로 폴백하므로 이미
      // 답을 확정해 두었고, 화면이 `isWellFormedInviteCode(token)`으로 **모양**을 다시
      // 보면 v3.0 이전의 6자리 **링크 토큰**에서 답이 갈린다(팀 공용 시드 `482913`이
      // 그것이다) — 멀쩡한 링크가 '만료된 코드'로 안내된다. 같은 입력에 저장소는
      // '링크', 화면은 '코드'라고 답하던 어긋남이라, 판정을 한 곳으로 모은 것이다.
      final InviteExpiredException? expired =
          e is InviteExpiredException ? e : null;
      if (mounted) {
        setState(() {
          _sending = false;
          // 확인 모드에 코드 입력 전환을 띄우는 조건이다(성공 경로는 버튼 하나로 둔다).
          _failed = true;
        });
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          // 세 갈래가 정확히 세 상태다 — 만료 아님 / 만료된 코드 / 만료된 링크.
          // 튜플로 풀면 `(false, true)`(만료가 아닌데 코드)라는 있을 수 없는 조합이
          // 언어상 표현 가능해져, 뒤에 오는 사람이 도달하지 않는 분기를 더할 수 있다.
          content: Text(switch (expired) {
            null => '요청을 보낼 수 없어요. 링크나 코드가 잘못됐을 수 있어요.',
            InviteExpiredException(isCode: true) =>
              '만료된 초대코드예요. 방장에게 새 코드를 요청하세요.',
            InviteExpiredException() => '만료된 초대 링크예요. 방장에게 링크 재발급을 요청하세요.',
          }),
        ));
      return;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _requested = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (_requested) {
      return _SheetScaffold(
        title: '참여 요청을 보냈어요',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ⚠️ 그룹 이름·이모지·멤버 수를 **여기에 넣지 마세요.** 요청자는 아직 멤버가
            //    아니고, 링크는 유출될 수 있다. 링크만 쥐면 그룹 정보를 알 수 있게 되면
            //    승인제를 넣은 의미가 절반 사라진다(계약: `JoinRequest`가 그룹 표시
            //    정보를 담지 않는 것과 같은 이유).
            Icon(Icons.hourglass_top,
                size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              '방장이 승인하기 전까지는 참여할 수 없어요.\n승인되면 공유 탭에 그룹이 나타나요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }

    if (_isConfirmMode) return _buildConfirm(theme);

    return _SheetScaffold(
      title: '그룹 참여 요청',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 입력란은 하나다 — 사용자에게 "지금 넣는 것이 링크인지 코드인지" 고르게
          // 하는 것은 전달 수단의 차이를 사용자 몫으로 떠넘기는 것이다. 계약의
          // `requestToJoin(credential)`이 같은 이유로 하나이고, 어느 쪽인지는 저장소가
          // 조회로 확정해 `InviteExpiredException.isCode`로 알려준다(모양이 아니다 —
          // 6자리 링크 토큰에서 모양과 실제가 갈린다).
          Text('초대코드 또는 초대 링크', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _codeCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: '6자리 코드 또는 링크의 토큰'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _sending ? null : _submit,
            // 두 모드가 **같은 라벨**을 쓴다 — 하는 일이 하나(요청 보내기)인데 문구가
            // 갈리면 같은 동작을 다른 것으로 읽게 된다. 공유 탭의 진입 버튼
            // ('참여 요청하기')과는 문자열이 달라 테스트 finder도 섞이지 않는다.
            child: Text(_sending ? '보내는 중…' : '그룹 참여 요청하기'),
          ),
        ],
      ),
    );
  }

  /// 확인 모드 — 딥링크로 들어온 사람에게 버튼 하나만 보여준다.
  ///
  /// **링크 토큰을 화면에 싣지 않는다.** 22자 base64url은 사용자가 읽을 값도 고칠 값도
  /// 아니라서, 입력란에 담으면 ①의미 없는 문자열을 검토 대상으로 내밀고 ②`autofocus`로
  /// 키보드까지 띄운 채 ③전체선택 한 번에 토큰이 날아갈 여지를 준다. 대조할 원본이 없어
  /// 보여줘 봐야 판단 근거가 되지도 않는다.
  Widget _buildConfirm(ThemeData theme) {
    return _SheetScaffold(
      title: '그룹 초대를 받았어요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ⚠️ 그룹 이름·이모지·멤버 수를 **여기에 넣지 마세요.** 요청자는 아직 멤버가
          //    아니고, 링크는 유출될 수 있다(요청 완료 화면과 같은 규약).
          Icon(Icons.mail_outline, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            '방장이 승인하면 그룹에 참여돼요.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _sending ? null : _submit,
            child: Text(_sending ? '보내는 중…' : '그룹 참여 요청하기'),
          ),
          // 실패한 뒤에만 보여준다 — 만료된 링크로 거절당한 사람이 방장에게 6자리
          // 코드를 불러 받는 것이 정상 경로인데, 이 전환이 없으면 시트를 닫고 공유
          // 탭에서 다시 열어야 한다.
          if (_failed) ...<Widget>[
            const SizedBox(height: 8),
            TextButton(
              onPressed:
                  _sending ? null : () => setState(() => _manualEntry = true),
              child: const Text('초대코드로 참여하기'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 기프티콘 공유 바텀시트 — 내 기프티콘 중 하나를 골라 [groupId] 그룹에 공유한다.
Future<void> showShareGifticonSheet(BuildContext context, String groupId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _ShareGifticonSheet(groupId: groupId),
  );
}

class _ShareGifticonSheet extends ConsumerWidget {
  const _ShareGifticonSheet({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    // 공유 후보 = 사용 가능하고 아직 내 어느 그룹에도 공유하지 않은 내 기프티콘.
    // (이미 다른 그룹에 공유된 것도 제외 → 이중 공유/이중 사용 사전 차단.)
    final List<Gifticon> candidates = ref.watch(unsharedGifticonsProvider);
    // 후보 계산의 원천(내 기프티콘 / 그룹별 공유 목록)이 에러면 목록을 믿을 수 없다:
    // 후보가 0개로 접히거나(→ "없어요" 오인), 이미 공유된 항목이 다시 노출된다.
    // 저장소 [StateError] 가드가 최후 방어선이지만, 이유를 알려 헛수고를 줄인다.
    final bool hasError = ref.watch(shareCandidatesHaveErrorProvider);
    // 공유 상세와 같은 규칙: 원인이 어느 축이든 재시도는 하나의 진입점으로 한다
    // ([retryShareCandidates] — 내 기프티콘·내 그룹 목록·그룹별 공유 중 에러인 원천만
    // 되살린다). 그룹 목록이 원인일 때 버튼을 감추던 강등은 계약 재시도 훅 도착으로
    // 제거됐다(#13).
    // 후보 계산 원천이 아직 첫 방출 전(값 없는 로딩)이면 후보 0개는 확정이 아니다 —
    // "없어요"로 위장하지 않고 스피너를 둔다(콜드 로딩 false-empty 게이트).
    final AsyncValue<List<Gifticon>> mineAsync =
        ref.watch(shareableGifticonsProvider);
    final bool pending = (mineAsync.isLoading && !mineAsync.hasValue) ||
        ref.watch(sharedGifticonsPendingProvider);
    final Widget? errorBanner = hasError
        ? InlineErrorBanner(
            message: '공유할 기프티콘 목록을 불러오지 못했어요.',
            onRetry: () => retryShareCandidates(ref),
          )
        : null;

    return _SheetScaffold(
      title: '기프티콘 공유',
      child: candidates.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: errorBanner ??
                  (pending
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: Text(
                            '공유할 수 있는 기프티콘이 없어요.',
                            style: theme.textTheme.bodySmall,
                          ),
                        )),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (errorBanner != null) ...<Widget>[
                  errorBanner,
                  const SizedBox(height: 12),
                ],
                Text('내 기프티콘에서 선택', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext ctx, int i) {
                      final Gifticon g = candidates[i];
                      return Card(
                        child: ListTile(
                          leading: const EmojiAvatar(emoji: '🎁', size: 40),
                          title: Text(g.productName,
                              style: theme.textTheme.titleMedium),
                          subtitle: Text(
                              '${g.brand} · ${formatExpiryLabel(g.expiryDate)}',
                              style: theme.textTheme.bodySmall),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () => _share(context, ref, g),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref, Gifticon g) async {
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(shareRepositoryProvider)
          .shareGifticon(groupId: groupId, gifticon: g);
    } catch (e, s) {
      reportHandledFailure(ref, e, s,
          context: 'ShareGifticonSheet.shareGifticon');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 공유할 수 없어요.')));
      return;
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('${g.productName}${g.productName.eulReul} 공유했어요.')));
  }
}
