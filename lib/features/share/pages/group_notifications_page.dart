/// share 페이지 — 그룹 알림(전체 화면, KeepCon 틀 재디자인).
///
/// 등록/만료임박/사용완료 유형별 아이콘·문구를 카드 목록으로 보여준다. 공유/사용완료가
/// 일어날 때마다 계약 [ShareRepository]에 알림이 쌓이고 이 화면이 [notificationsProvider]
/// 구독으로 동기화된다. 상대 시각 포맷은 소비자(UI) 책임. 색 하드코딩 없음.
///
/// 스트림 에러는 [ShareErrorBanner]로 표시하고 재시도는 사용자 액션으로만 한다
/// (자동 재시도 금지 — 크로스페이지 주의점 #13).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/share.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../state/share_providers.dart';
import '../widgets/share_error_banner.dart';
import '../widgets/share_format.dart';

/// 그룹 알림 화면. 공유 메인 헤더의 알림 아이콘에서 push 한다.
///
/// 알림 목록을 **실제로 보여준 뒤에만** [ShareRepository.markNotificationsRead]를
/// 호출해 안읽음을 해소한다(뱃지 클리어) — 아래 읽음 가드 참조.
class GroupNotificationsPage extends ConsumerStatefulWidget {
  const GroupNotificationsPage({super.key});

  @override
  ConsumerState<GroupNotificationsPage> createState() =>
      _GroupNotificationsPageState();
}

class _GroupNotificationsPageState
    extends ConsumerState<GroupNotificationsPage> {
  /// 이번 화면 수명 동안 읽음 처리를 이미 호출했는지(중복 호출 방지).
  bool _markedRead = false;

  @override
  void initState() {
    super.initState();
    // 진입 시점에 이미 데이터가 있으면(따뜻한 캐시) 첫 프레임 뒤 바로 읽음 처리한다.
    // 로딩/에러면 여기서는 아무것도 하지 않고, build의 ref.listen이 이후 도착하는
    // 첫 성공 방출에서 처리한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markReadWhenVisible(ref.read(notificationsProvider));
    });
  }

  /// 읽음 가드 — **성공 데이터를 방출한 뒤에만** 읽음 처리한다.
  ///
  /// 예전 구현은 진입 즉시 무조건 [ShareRepository.markNotificationsRead]를 호출했다.
  /// 그래서 스트림이 에러여서 목록을 한 줄도 못 본 상태로 들어와도 읽음 시각이 갱신됐고,
  /// 스트림이 회복된 뒤에는 그 알림들이 "읽음"이라 뱃지에도, 화면에도 다시 뜨지 않았다
  /// (= 한 번도 못 본 알림의 유실). 로딩/에러 중에는 보류하고, 사용자가 실제로 목록을
  /// 볼 수 있는 상태([AsyncData])가 됐을 때 1회만 호출한다. 에러 상태로 화면을 나가면
  /// 읽음 처리가 아예 일어나지 않는다 — 알림이 보존되는, 의도된 동작이다.
  void _markReadWhenVisible(AsyncValue<List<GroupNotification>> value) {
    if (_markedRead) return;
    // 이전 값을 안고 있는 AsyncLoading/AsyncError도 제외한다(재조회 중·실패 중).
    // 이때 화면은 보존된 이전 목록을 렌더하지만 그 목록은 **최신이 아닐 수 있다** —
    // 에러 이후 도착했어야 할 새 알림을 사용자는 못 봤는데 readAt만 지금으로 찍으면
    // 그 알림들이 통째로 "읽음" 처리돼 유실된다(위 예전 구현과 같은 사고). 뱃지가
    // 남는 과대 표시는 배너의 '다시 시도'로 회복 가능하지만 유실은 회복 불가이므로,
    // 보수적으로 성공 방출([AsyncData])만 "봤다"로 인정한다.
    if (value is! AsyncData<List<GroupNotification>>) return;
    _markedRead = true;
    unawaited(_markRead(value));
  }

  Future<void> _markRead(AsyncValue<List<GroupNotification>> attempted) async {
    try {
      await ref.read(shareRepositoryProvider).markNotificationsRead();
    } catch (_) {
      // 실패는 "읽음 처리가 안 된 것"이므로 가드를 소모하지 않은 상태로 되돌린다.
      // 흔한 두 갈래 — ① [StateError]: 세션이 `data(null)`이면 [notificationsProvider]가
      // `AsyncData(<GroupNotification>[])`를 돌려주는데 이것도 AsyncData라 가드를
      // 통과하고, 저장소가 미로그인 StateError로 거부한다. ② 저장소 구현별 실패
      // (Firestore 쓰기의 네트워크·권한 오류 등) — 계약 dartdoc이 명시한 StateError가
      // 아니어도 원칙은 같고, unawaited 뒤라 여기서 잡지 않으면 unhandled async
      // error로 샌다. 사용자에게 따로 알리지는 않는다(다음 성공 방출에서 재시도).
      _markedRead = false;
      // ②처럼 실패가 비동기(네트워크 왕복 뒤)인 경우, 처리 중 도착한 방출은 위
      // 가드에 막혀 버려졌고 같은 값은 재통지되지 않는다. 복원 직후 현재 상태를
      // 한 번 재평가해 그 창을 닫는다(상태가 그대로면 재시도하지 않으므로 같은
      // 실패를 도는 루프는 생기지 않는다 — 시도마다 서로 다른 방출이 필요하다).
      if (!mounted) return;
      final AsyncValue<List<GroupNotification>> current =
          ref.read(notificationsProvider);
      if (!identical(current, attempted)) {
        _markReadWhenVisible(current);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 성공 방출이 뒤늦게 도착하는 경우(로딩/에러로 진입 → 회복)를 여기서 받는다.
    ref.listen<AsyncValue<List<GroupNotification>>>(
      notificationsProvider,
      (_, AsyncValue<List<GroupNotification>> next) =>
          _markReadWhenVisible(next),
    );

    final AsyncValue<List<GroupNotification>> async =
        ref.watch(notificationsProvider);
    // 폴딩 규약(#13)은 그대로 두고, 에러 표시만 hasError 관찰로 얹는다.
    final List<GroupNotification> items =
        async.valueOrNull ?? const <GroupNotification>[];
    final bool hasError = async.hasError;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('그룹 알림', style: context.navTitleStyle),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: ShareErrorBanner(
                  message: '알림을 불러오지 못했어요.',
                  onRetry: () => retryNotifications(ref),
                ),
              ),
            Expanded(
              child: items.isEmpty
                  // 에러일 땐 배너가 실패를 설명하고, 첫 방출 전(값 없는 로딩)엔
                  // 스피너를 둔다 — 어느 쪽도 "알림이 없어요"라는 확정 부재로
                  // 위장하지 않는다(존재 은폐 방지).
                  ? (hasError
                      ? const SizedBox.shrink()
                      : async.isLoading && !async.hasValue
                          ? const Center(child: CircularProgressIndicator())
                          : Center(
                              child: Text('알림이 없어요.',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (BuildContext context, int i) =>
                          _NotificationCard(item: items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 알림 카드 — 유형별 원형 아이콘 + 제목/시간/본문 + 셰브론.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item});

  final GroupNotification item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    late final IconData icon;
    late final Color tint;
    switch (item.type) {
      case GroupNotificationType.registered:
        icon = Icons.card_giftcard;
        tint = scheme.primary;
      case GroupNotificationType.expiringSoon:
        icon = Icons.schedule;
        tint = scheme.error;
      case GroupNotificationType.used:
        icon = Icons.check_circle_outline;
        tint = scheme.onSurfaceVariant;
      case GroupNotificationType.joinRequested:
        icon = Icons.person_add_alt;
        tint = scheme.primary;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.softCard(scheme),
      child: Row(
        children: <Widget>[
          // 유형별 원형 아이콘(연한 틴트 배경).
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: tint, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.title,
                        style: context.sectionTitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(formatRelativeKo(item.createdAt),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.message,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
