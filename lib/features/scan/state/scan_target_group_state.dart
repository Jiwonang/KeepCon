/// scan — 저장 대상 그룹 선택용 상태(공유 계약 소비).
///
/// 스캔/추가 화면은 "이 기프티콘을 내 지갑에 둘지, 어느 그룹에 공유할지"를 저장 전에
/// 고르게 한다. 그 선택지를 만들기 위해 그룹 목록을 계약에서 읽어 온다.
///
/// 계약 준수 포인트:
/// - 그룹 목록은 `ShareRepository.watchGroups(userId)`만 사용한다(계약 메서드 그대로).
/// - Repository provider는 `lib/shared/providers/repositories.dart`의 **SSOT**
///   ([authRepositoryProvider]/[shareRepositoryProvider])를 `watch`해 소비한다
///   (페이지 재선언 금지 — 인스턴스 분기 방지).
/// - `Group`/`User`는 계약 모델을 그대로 쓴다(재정의 금지).
///
/// 여기의 provider는 **scan 페이지 로컬 파생 provider**다(그룹 도메인 정본이 아니다).
/// share 페이지에도 비슷한 파생 provider가 있지만, 페이지끼리 상태를 import하면
/// 페이지 간 결합이 생기므로 각 페이지가 같은 계약(SSOT repository)을 각자 소비한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/group.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/repositories.dart';

/// 현재 로그인 사용자 스트림(scan 로컬 구독).
///
/// 저장 소유자 식별(`submit`)은 동기 getter `AuthRepository.currentUser`를 쓰지만,
/// 그룹 목록은 화면에 떠 있는 동안 세션 변화(로그인/로그아웃)에 반응해야 하므로
/// 스트림으로 구독한다.
///
/// **autoDispose인 이유(체인 전체 공통):** 스캔 화면은 상시 탭이 아니라 일회성
/// 추가 플로우다. keepAlive면 화면을 한 번만 열어도 실서버 리스너가 앱 수명 동안
/// 잔존하고, family는 로그아웃→다른 계정 로그인 시 이전 userId의 구독이 누적된다.
/// autoDispose면 유일한 소비자(선택 UI)가 사라질 때 자동 해제되고, 재진입 시
/// 로딩을 빈 목록으로 접는 설계 덕에 잠깐 '내 지갑'만 보이는 것 외 UX 손실이 없다.
final _scanCurrentUserProvider = StreamProvider.autoDispose<User?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});

/// 특정 사용자의 그룹 스트림(내부용 — 확정된 userId로만 구독).
final _scanGroupsByUserProvider =
    StreamProvider.autoDispose.family<List<Group>, String>((ref, userId) {
  return ref.watch(shareRepositoryProvider).watchGroups(userId);
});

/// 저장 대상으로 고를 수 있는 내 그룹 목록.
///
/// 로딩 중·미로그인·그룹 없음은 모두 **빈 목록**으로 접는다. 선택 UI가 항상
/// '내 지갑'(그룹 공유 없음) 타일을 첫 번째로 두기 때문에, 빈 목록도 그 자체로
/// 정상 상태이며 사용자는 언제나 저장을 진행할 수 있다(로딩 스피너 불필요).
///
/// 스트림 **error**도 빈 목록으로 접힌다(권한/네트워크 오류 시 타일이 사라질 뿐
/// 별도 안내 없음) — 저장은 부분 실패 정책이 백스톱이고, 에러 표시/재시도 UI는
/// 후속 과제로 남긴다. autoDispose라 재진입 시 재구독으로 자연 복구된다.
final scanTargetGroupsProvider = Provider.autoDispose<List<Group>>((ref) {
  final User? user = ref.watch(_scanCurrentUserProvider).value;

  if (user == null) return const <Group>[];

  return ref.watch(_scanGroupsByUserProvider(user.id)).value ?? const <Group>[];
});
