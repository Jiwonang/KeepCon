/// KeepCon 공유 계약 — InMemoryGifticonRepository (mock 구현).
///
/// 실제 백엔드 없이 scan(생산)과 main(소비)이 즉시 병렬 개발할 수 있도록 제공하는
/// in-memory 구현체. 정렬/필터는 하지 않는다(소비자 책임) — 계약대로 원천 목록만 관리.
library;

import 'dart:async';

import '../../models/gifticon.dart';
import '../gifticon_repository.dart';

/// [GifticonRepository]의 in-memory mock 구현.
///
/// 소유자별 목록을 메모리에 보관하고, 변경 시 [watchGifticons] 스트림에 방출한다.
/// id/registeredAt이 비어 있으면 저장 시점에 발급한다.
class InMemoryGifticonRepository implements GifticonRepository {
  final List<Gifticon> _store = <Gifticon>[];
  final StreamController<List<Gifticon>> _controller =
      StreamController<List<Gifticon>>.broadcast();
  int _seq = 0;

  /// 초기 시드 데이터를 넣어 생성할 수 있다(미지정 시 빈 저장소).
  InMemoryGifticonRepository({List<Gifticon>? seed}) {
    if (seed != null) _store.addAll(seed);
  }

  void _emit() => _controller.add(List<Gifticon>.unmodifiable(_store));

  @override
  Future<Gifticon> addGifticon(Gifticon gifticon) async {
    final String id =
        gifticon.id.isEmpty ? 'gifticon-${++_seq}' : gifticon.id;
    final Gifticon saved = gifticon.copyWith(id: id);
    _store.add(saved);
    _emit();
    return saved;
  }

  @override
  Stream<List<Gifticon>> watchGifticons(String ownerId) async* {
    yield _ownedBy(ownerId);
    yield* _controller.stream.map((_) => _ownedBy(ownerId));
  }

  @override
  Future<List<Gifticon>> getGifticons(String ownerId) async =>
      _ownedBy(ownerId);

  @override
  Future<Gifticon?> getGifticonById(String id) async {
    for (final Gifticon g in _store) {
      if (g.id == id) return g;
    }
    return null;
  }

  @override
  Future<Gifticon> updateStatus(String id, GifticonStatus status) async {
    final int idx = _store.indexWhere((Gifticon g) => g.id == id);
    if (idx < 0) {
      throw StateError('Gifticon not found: $id');
    }
    final Gifticon current = _store[idx];
    if (!GifticonStatusTransition.isAllowed(current.status, status)) {
      throw StateError(
        'Illegal status transition: ${current.status} -> $status',
      );
    }
    final Gifticon updated = current.copyWith(status: status);
    _store[idx] = updated;
    _emit();
    return updated;
  }

  List<Gifticon> _ownedBy(String ownerId) => List<Gifticon>.unmodifiable(
        _store.where((Gifticon g) => g.ownerId == ownerId),
      );

  /// 리소스 정리. 앱 종료/테스트 teardown 시 호출.
  void dispose() {
    _controller.close();
  }
}
