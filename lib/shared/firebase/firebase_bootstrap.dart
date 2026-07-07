/// KeepCon 공유 계약 — Firebase 부트스트랩 / provider 전환.
///
/// 이 파일은 "Firebase 백엔드로 전환하는 방법"을 함수+문서로 제공한다.
/// **기본 실행 경로에서 호출하지 마라.** 기본은 in-memory 유지가 계약이다.
/// (사용자가 아직 `flutterfire configure`를 하지 않았을 수 있으므로,
///  강제 초기화는 데모를 깨뜨린다.)
///
/// ---
/// ## 계약의 가치 시연
/// 페이지들은 [AuthRepository]/[GifticonRepository] **인터페이스에만** 의존한다.
/// 따라서 백엔드 교체는 "새 구현체를 provider로 override" 하는 것만으로 끝난다 —
/// 페이지 코드는 단 한 줄도 바뀌지 않는다.
///
/// ---
/// ## 사용자가 Firebase를 켜는 절차 (요약; 상세는 의존성 매트릭스 문서)
/// 1. Firebase 콘솔에서 프로젝트 생성.
/// 2. `dart pub global activate flutterfire_cli` 후 프로젝트 루트에서 `flutterfire configure`.
///    → `lib/firebase_options.dart`가 실제 값으로 생성된다.
/// 3. 콘솔에서 Authentication·Cloud Firestore 활성화.
/// 4. 앱 조립부(main.dart)에서 아래 [firebaseProviderOverrides]로 provider를 override.
///
/// ---
/// ## main.dart 조립 예시 (기본 in-memory → Firebase 전환)
/// ```dart
/// import 'package:flutter/widgets.dart';
/// import 'package:flutter_riverpod/flutter_riverpod.dart';
/// import 'package:keepcon/shared/firebase/firebase_bootstrap.dart';
///
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   // 아래 한 줄을 켜면 Firebase, 끄면(주석 처리하면) 기본 in-memory.
///   final overrides = await initFirebaseAndBuildOverrides(); // Firebase 경로
///   // final overrides = <Override>[];                       // in-memory 경로(기본)
///
///   runApp(ProviderScope(overrides: overrides, child: const KeepConApp()));
/// }
/// ```
///
/// ⚠️ `lib/main.dart`는 이 계약 스캐폴딩에서 수정하지 않는다(앱 조립부는 오케스트레이터가
/// 하단 탭 셸과 함께 배선한다). 이 파일은 그 배선에서 **호출해 쓰라고** 제공하는 도구다.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';
import '../providers/repositories.dart';
import '../repositories/impl/firebase/firebase_auth_repository.dart';
import '../repositories/impl/firebase/firebase_gifticon_repository.dart';

/// Firebase를 초기화하고, Repository provider를 Firebase 구현으로 교체하는
/// [Override] 목록을 만든다.
///
/// 이 함수를 호출한다는 것은 "이 앱 실행을 Firebase 백엔드로 돌린다"는 의미다.
/// `flutterfire configure`가 선행되어야 한다([DefaultFirebaseOptions] 참조) —
/// 미구성 상태에서 호출하면 [DefaultFirebaseOptions.currentPlatform]이
/// [UnimplementedError]를 던진다.
///
/// 반환한 [Override] 목록을 `ProviderScope(overrides: ...)`에 그대로 넣으면,
/// 계약 SSOT provider([authRepositoryProvider]/[gifticonRepositoryProvider])가
/// Firebase 구현을 참조하게 된다. 페이지 코드는 변경 불필요.
Future<List<Override>> initFirebaseAndBuildOverrides() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  return firebaseProviderOverrides();
}

/// 이미 [Firebase.initializeApp]이 완료된 상태에서, provider override만 만든다.
///
/// (초기화를 호출부가 직접 제어하고 싶을 때 사용. 초기화 없이 이 override만 넣으면
///  Firebase 호출 시점에 예외가 난다.)
///
/// gifticonRepository는 scan·main·share가 **같은 단일 인스턴스**를 공유하도록
/// 하나만 생성해 주입한다(계약 SSOT 규칙 — 인스턴스 분기 방지).
List<Override> firebaseProviderOverrides() {
  final FirebaseAuthRepository authRepo = FirebaseAuthRepository();
  final FirebaseGifticonRepository gifticonRepo = FirebaseGifticonRepository();

  return <Override>[
    authRepositoryProvider.overrideWithValue(authRepo),
    gifticonRepositoryProvider.overrideWithValue(gifticonRepo),
  ];
}
