/// 기프티콘 계약 스위트를 **두 구현에 모두** 돌린다.
///
/// 이 파일이 하는 일은 백엔드를 갈아 끼우는 것뿐이다 — 기대는 전부
/// `gifticon_repository_contract_suite.dart`에 있고, 그래야 한쪽만 고쳐도 다른 쪽이
/// 시끄럽게 실패한다. **기대를 여기에 쓰지 마라**(쓰는 순간 두 구현이 다른 계약을
/// 검증하게 되고, 이 파일의 존재 이유가 사라진다).
///
/// 경계(fake가 대체하지 못하는 것)는 스위트 파일의 머리말이 정본이다.
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/repositories/gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

import 'gifticon_repository_contract_suite.dart';

/// in-memory 구현 어댑터.
class _InMemoryBackend implements GifticonBackend {
  final InMemoryGifticonRepository _repo = InMemoryGifticonRepository();

  @override
  GifticonRepository get repo => _repo;

  @override
  void stop() => _repo.dispose();
}

/// firebase 구현 어댑터 — 인메모리 Firestore(`fake_cloud_firestore`) 위에서 돈다.
class _FirebaseBackend implements GifticonBackend {
  final FakeFirebaseFirestore _db = FakeFirebaseFirestore();

  late final FirebaseGifticonRepository _repo =
      FirebaseGifticonRepository(firestore: _db);

  @override
  GifticonRepository get repo => _repo;

  @override
  void stop() {
    // `FirebaseGifticonRepository`에는 dispose가 없다(스트림을 자체 보관하지 않는다).
  }
}

void main() {
  // 라벨과 팩토리를 한 자리에 둔다(공유 스위트 쪽과 같은 형태).
  final Map<String, GifticonBackend Function()> backends =
      <String, GifticonBackend Function()>{
    'in-memory': _InMemoryBackend.new,
    'firebase(fake)': _FirebaseBackend.new,
  };

  backends.forEach((String label, GifticonBackend Function() make) {
    group('[$label] extendExpiry — 유효기간 연장', () {
      runExpiryExtensionContract(make);
    });
  });
}
