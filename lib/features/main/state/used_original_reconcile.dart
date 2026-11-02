/// main 페이지 — 공유로 사용 완료된 원본의 사후 보정 트리거(Riverpod).
///
/// 다른 멤버가 그룹에서 사용 완료하면 원본 동기화는 공유 항목 갱신과 별도 쓰기라
/// 실패할 수 있고, 그러면 소유자의 목록에 이미 쓴 기프티콘이 '보유중'으로 남는다.
/// 보정 자체는 계약 [ShareRepository.reconcileUsedOriginals]가 하고, 이 파일은
/// **언제 부를지**만 정한다 — 메인 목록에 들어올 때, 로그인 사용자마다 한 번.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/diagnostics/error_reporter.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/error_reporter_provider.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/providers/session_provider.dart';
import '../../../shared/repositories/share_repository.dart';

/// 현재 사용자에 대해 보정을 한 번 돌린다. 값은 맞춘 원본 수(미로그인이면 0).
///
/// **keepAlive가 곧 "한 번"이다.** 세션에서 사용자 id만 `select`하므로 같은 사용자의
/// 재방출(토큰 갱신·프로필 편집)에는 다시 돌지 않고, 계정이 바뀌면 그 사용자로 한 번 더
/// 돈다. 화면을 떠났다 돌아와도 재실행하지 않는다 — 원본마다 조회가 붙는 작업이라
/// 진입마다 돌릴 값이 없고, 보정은 다음 앱 실행에서 다시 시도된다.
///
/// 실패는 화면에 올리지 않는다(보정은 사용자가 요청한 동작이 아니다). 대신
/// [ErrorReporter]로 원본을 남긴다 — 조용히 삼키면 보정이 영영 안 도는 결함이 드러나지
/// 않는다.
final usedOriginalsReconcileProvider = FutureProvider<int>((ref) async {
  final String? uid = ref.watch(
    sessionUserProvider.select((AsyncValue<User?> s) => s.valueOrNull?.id),
  );
  if (uid == null) return 0;
  try {
    return await ref.read(shareRepositoryProvider).reconcileUsedOriginals();
  } catch (e, st) {
    ref
        .read(errorReporterProvider)
        .report(e, st, context: 'usedOriginalsReconcileProvider');
    return 0;
  }
});
