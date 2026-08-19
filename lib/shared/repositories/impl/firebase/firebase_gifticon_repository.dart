/// KeepCon 공유 계약 — FirebaseGifticonRepository (cloud_firestore 구현체).
///
/// [GifticonRepository] 계약을 Cloud Firestore로 구현한다.
/// **인터페이스는 그대로**이므로, provider override만으로 in-memory ↔ Firebase가 교체된다.
///
/// 정렬/필터는 계약대로 하지 않는다(소비자 책임) — 소유자별 원천 목록/스트림만 제공한다.
///
/// ## 문서 매핑 규약 (Firestore ↔ 계약 [Gifticon])
/// - 컬렉션: `'gifticons'`, 문서 id = [Gifticon.id].
/// - enum([GifticonStatus])은 `.name` 문자열로 저장하고 역매핑한다(매직 스트링 금지 —
///   저장 문자열은 enum 이름에 고정).
/// - [DateTime]([Gifticon.expiryDate], [Gifticon.registeredAt])은 Firestore [Timestamp]로
///   저장하고 역매핑한다.
///
/// ⚠️ 기본 실행 경로에서 인스턴스화하지 마라 — `Firebase.initializeApp()` 선행 필요.
/// 부트스트랩([firebase_bootstrap.dart]) 경유로만 활성화한다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'doc_read.dart';

import '../../../models/gifticon.dart';
import '../../gifticon_repository.dart';

/// [GifticonRepository]의 Cloud Firestore 구현.
class FirebaseGifticonRepository implements GifticonRepository {
  /// 주입받는 [FirebaseFirestore] 인스턴스. 미지정 시 [FirebaseFirestore.instance] 사용.
  FirebaseGifticonRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// 기프티콘 컬렉션 이름(SSOT).
  static const String collectionName = 'gifticons';

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(collectionName);

  @override
  Future<Gifticon> addGifticon(Gifticon gifticon) async {
    // id가 비어 있으면 Firestore가 문서 id를 발급하도록 하고, 그 id를 [Gifticon]에 반영한다.
    final DocumentReference<Map<String, dynamic>> ref =
        gifticon.id.isEmpty ? _col.doc() : _col.doc(gifticon.id);
    final Gifticon saved = gifticon.copyWith(id: ref.id);
    await ref.set(_toDoc(saved));
    return saved;
  }

  @override
  Stream<List<Gifticon>> watchGifticons(String ownerId) {
    return _col.where('ownerId', isEqualTo: ownerId).snapshots().map(
        (QuerySnapshot<Map<String, dynamic>> snap) =>
            snap.docs.map(_fromDoc).toList(growable: false));
  }

  @override
  Future<List<Gifticon>> getGifticons(String ownerId) async {
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _col.where('ownerId', isEqualTo: ownerId).get();
    return snap.docs.map(_fromDoc).toList(growable: false);
  }

  @override
  Future<Gifticon?> getGifticonById(String id) async {
    final DocumentSnapshot<Map<String, dynamic>> doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return _fromDoc(doc);
  }

  @override
  Future<Gifticon> updateStatus(String id, GifticonStatus status) async {
    final DocumentReference<Map<String, dynamic>> ref = _col.doc(id);

    // 상태 전이 검증은 트랜잭션 내부에서 현재 값을 읽어 계약 규칙으로 판정한다.
    // 위반 시 [StateError]를 던지는 것이 계약([GifticonRepository.updateStatus]).
    return _db.runTransaction<Gifticon>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) {
        throw StateError('Gifticon not found: $id');
      }
      final Gifticon current = _fromDoc(doc);
      if (!GifticonStatusTransition.isAllowed(current.status, status)) {
        throw StateError(
          'Illegal status transition: ${current.status} -> $status',
        );
      }
      tx.update(ref, <String, dynamic>{'status': status.name});
      return current.copyWith(status: status);
    });
  }

  // --- 매핑 헬퍼 ---------------------------------------------------------

  /// 계약 [Gifticon] → Firestore 문서 맵.
  ///
  /// enum은 `.name`, [DateTime]은 [Timestamp]로 저장한다.
  Map<String, dynamic> _toDoc(Gifticon g) => <String, dynamic>{
        'ownerId': g.ownerId,
        'brand': g.brand,
        'productName': g.productName,
        'price': g.price,
        'barcode': g.barcode,
        'category': g.category,
        'expiryDate': Timestamp.fromDate(g.expiryDate),
        'registeredAt': Timestamp.fromDate(g.registeredAt),
        'status': g.status.name,
        'imagePath': g.imagePath,
      };

  /// Firestore 문서 → 계약 [Gifticon].
  ///
  /// 문서 id를 [Gifticon.id]로, `status` 문자열을 [GifticonStatus]로 역매핑한다.
  Gifticon _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      gifticonFromData(doc.id, doc.data() ?? const <String, dynamic>{});

  /// [_fromDoc]의 순수 본체(문서 없이 맵만으로 동작 — 테스트 진입점).
  ///
  /// 손상 문서라도 **던지지 않는다.** [watchGifticons]/[getGifticons]가 목록 전체를 이
  /// 매퍼로 매핑하므로, 문서 하나가 [Error]를 던지면 **사용자의 기프티콘 목록이 통째로
  /// 사라진다**(공유 쪽과 같은 사고 구조다 — `doc_read.dart` 참조).
  @visibleForTesting
  static Gifticon gifticonFromData(String id, Map<String, dynamic> data) {
    return Gifticon(
      id: id,
      ownerId: docString(data['ownerId']),
      brand: docString(data['brand']),
      productName: docString(data['productName']),
      // price는 required 계약. 숫자면 그대로, 문자열이면 파싱, 그 밖(손상·누락)은 0.
      //
      // 예전에는 `(data['price'] as num?)?.toInt() ?? int.tryParse(...)`였는데, 문자열이
      // 들어오면 **캐스팅이 먼저 [TypeError]를 던져 문자열 폴백에 닿지 못했다** —
      // 방어 코드가 있는 것처럼 보이지만 실제로는 죽은 가지였다.
      price:
          docInt(data['price']) ?? int.tryParse(docString(data['price'])) ?? 0,
      barcode: docStringOrNull(data['barcode']),
      category: docString(data['category']),
      expiryDate: docDate(data['expiryDate']),
      registeredAt: docDate(data['registeredAt']),
      status: _statusFromName(docStringOrNull(data['status'])),
      imagePath: docStringOrNull(data['imagePath']),
    );
  }

  /// 저장된 `status` 문자열을 [GifticonStatus]로 역매핑한다.
  ///
  /// 알 수 없는 값은 [GifticonStatus.available]로 폴백한다(방어적).
  static GifticonStatus _statusFromName(String? name) {
    for (final GifticonStatus s in GifticonStatus.values) {
      if (s.name == name) return s;
    }
    return GifticonStatus.available;
  }
}
