/// KeepCon 앱 조립부 — 플랫폼 딥링크 수신.
///
/// 안드로이드에서 초대 링크를 눌러 앱이 열리면 URL은 **인텐트**로 들어온다. 승격 전에는
/// 이 수신부가 없어 `Uri.base`(웹 전용)만 보고 있었고, 그래서 **안드로이드에서는 초대
/// 링크가 아예 동작하지 않았다** — 링크는 브라우저로 새고 앱은 아무것도 모른 채 떠 있었다.
///
/// 두 경로를 모두 받는다:
/// - **콜드 스타트**: 링크가 앱을 처음 띄운 경우([AppLinks.getInitialLink]).
/// - **웜 스타트**: 앱이 이미 떠 있는데 링크가 도착한 경우(스트림).
///
/// 받은 링크는 파싱해 목적지 버스([pendingDestinationProvider])에 실을 뿐, 화면을 직접
/// 건드리지 않는다. 로그인 전에 도착할 수도 있기 때문이다(초대 링크로 앱을 처음 여는
/// 경우가 그렇다) — 소비 시점은 셸이 정한다.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/deeplink/app_destination.dart';
import '../shared/deeplink/deep_link_parser.dart';
import '../shared/providers/deep_link_providers.dart';

/// 플랫폼 딥링크를 받아 목적지 버스에 싣는 래퍼. 앱 최상단(인증 게이트 바깥)에 둔다.
class DeepLinkListener extends ConsumerStatefulWidget {
  /// [child]를 그대로 그리며 딥링크 수신만 곁들인다.
  const DeepLinkListener({super.key, required this.child});

  /// 감싸는 화면(인증 게이트).
  final Widget child;

  @override
  ConsumerState<DeepLinkListener> createState() => _DeepLinkListenerState();
}

class _DeepLinkListenerState extends ConsumerState<DeepLinkListener> {
  StreamSubscription<Uri>? _subscription;

  @override
  void initState() {
    super.initState();
    // 웹은 진입 URL(Uri.base)에서 이미 시드된다(provider 기본값). app_links의 웹 구현은
    // 그 위에 얹을 것이 없으므로 건너뛴다.
    if (kIsWeb) return;
    unawaited(_listen());
  }

  Future<void> _listen() async {
    try {
      final AppLinks appLinks = AppLinks();

      // 콜드 스타트. 스트림 구독보다 먼저 확인해야 첫 링크를 놓치지 않는다.
      final Uri? initial = await appLinks.getInitialLink();
      if (initial != null) _publish(initial);

      _subscription = appLinks.uriLinkStream.listen(
        _publish,
        onError: (Object e) => debugPrint('KeepCon: 딥링크 수신 오류 — $e'),
      );
    } catch (e) {
      // 플러그인이 없는 환경(위젯 테스트·미지원 플랫폼)에서 앱이 죽어선 안 된다.
      // 딥링크가 안 되는 것은 불편이지만, 앱이 안 뜨는 것은 기능 상실이다.
      debugPrint('KeepCon: 딥링크 수신부 초기화 실패 — $e');
    }
  }

  void _publish(Uri uri) {
    if (!mounted) return;
    final AppDestination? destination = parseDeepLink(uri);
    // 앱이 다룰 링크가 아니면 기존 대기 목적지를 덮어쓰지 않는다 — 무관한 링크 하나가
    // 아직 소비되지 않은 초대를 지워버리면 안 된다.
    if (destination == null) return;
    ref.read(pendingDestinationProvider.notifier).state = destination;
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
