/// KeepCon 공유 계약 — Repository Riverpod provider (단일 정본 / SSOT).
///
/// ⚠️ 이 파일이 Repository provider의 **유일한 정본**이다.
/// [authRepositoryProvider]와 [gifticonRepositoryProvider]는 오직 여기에만 존재한다.
/// scan / main / share / auth 등 모든 페이지는 provider를 페이지 내부에 재선언하지 말고
/// 이 파일을 import 해서 소비한다.
///
/// ---
/// ## 왜 계약(lib/shared)에 있어야 하는가 (경계면 버그 방어)
/// Repository provider가 페이지마다 중복 선언되면, 페이지별로 **서로 다른**
/// [GifticonRepository]/[AuthRepository] 인스턴스를 참조하게 된다.
/// 그 결과 scan이 추가한 기프티콘이 main 목록에 반영되지 않는 등, 페이지 간
/// 상태가 갈라지는 경계면 결함이 발생한다(통합 QA에서 실제로 검출됨).
///
/// provider는 "어떤 인스턴스를 공유하는가"를 결정하는 공유 관심사이므로, 모델·인터페이스와
/// 마찬가지로 계약 레벨에서 하나로 정의한다.
///
/// ---
/// ## 검증용 기본값
/// 이 파일의 기본 구현은 **공유 in-memory 인스턴스**([InMemoryAuthRepository],
/// [InMemoryGifticonRepository])다. override 없이도(단일 [ProviderScope] 안이라면)
/// 모든 페이지가 같은 인스턴스를 공유하므로, scan→main 데이터 흐름이 즉시 검증된다.
///
/// ---
/// ## 앱 조립부(main.dart)에서의 override 규칙 — 반드시 지킬 것
/// 실제 앱에서는 `ProviderScope(overrides: [...])`에서 아래처럼 override 한다.
///
/// 1. **auth 페이지가 실제 [AuthRepository] 구현을 제공**하면
///    [authRepositoryProvider]를 그 구현으로 override 한다.
/// 2. **[gifticonRepositoryProvider]는 scan·main·share가 반드시 같은 단일 인스턴스를
///    공유**하도록, 조립부에서 하나의 인스턴스를 만들어 override 로 주입한다.
///    (기본값도 SSOT라 단일 인스턴스지만, 실구현으로 교체할 때 인스턴스가 갈라지지 않도록
///    조립부에서 명시적으로 하나만 만든다.)
///
/// ```dart
/// // main.dart 조립 예시
/// final sharedGifticonRepo = InMemoryGifticonRepository(); // 앱 전체가 공유
/// final authRepo = InMemoryAuthRepository();               // auth 페이지 제공 구현으로 교체
///
/// runApp(
///   ProviderScope(
///     overrides: [
///       authRepositoryProvider.overrideWithValue(authRepo),
///       gifticonRepositoryProvider.overrideWithValue(sharedGifticonRepo),
///     ],
///     child: const KeepConApp(),
///   ),
/// );
/// ```
///
/// override 시에는 인스턴스 수명을 조립부가 소유하므로, 아래 기본 provider의 dispose는
/// 기본값(비-override)일 때만 동작한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/auth_repository.dart';
import '../repositories/gifticon_repository.dart';
import '../repositories/impl/in_memory_auth_repository.dart';
import '../repositories/impl/in_memory_gifticon_repository.dart';

/// 현재 사용자 세션을 제공하는 [AuthRepository]. **SSOT provider.**
///
/// 기본 구현은 검증용 [InMemoryAuthRepository]. 실제 앱에서는 auth 페이지가 제공하는
/// 구현으로 [authRepositoryProvider]를 override 한다(파일 상단 조립 규칙 참조).
///
/// scan은 [AuthRepository.currentUser]로 소유자를 식별하고, main/share도 동일 세션을
/// 이 provider를 통해 공유한다.
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((ref) {
  final InMemoryAuthRepository repo = InMemoryAuthRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// 기프티콘 원천 데이터를 제공하는 [GifticonRepository]. **SSOT provider.**
///
/// 기본 구현은 검증용 [InMemoryGifticonRepository]. scan·main·share는 이 provider를
/// 통해 **같은 단일 인스턴스**를 공유해야 한다 — 그래야 scan이 추가한 기프티콘이 main의
/// [GifticonRepository.watchGifticons] 스트림에 반영된다.
///
/// 실제 앱에서는 조립부에서 하나의 인스턴스를 만들어 override 로 주입한다
/// (파일 상단 조립 규칙 참조).
final Provider<GifticonRepository> gifticonRepositoryProvider =
    Provider<GifticonRepository>((ref) {
  final InMemoryGifticonRepository repo = InMemoryGifticonRepository();
  ref.onDispose(repo.dispose);
  return repo;
});
