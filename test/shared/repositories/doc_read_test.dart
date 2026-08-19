/// Firestore 문서 필드 **타입 안전 리더** 테스트.
///
/// 이 리더들이 존재하는 이유는 캐스팅(`as String?`)이 손상 값에 [Error]를 던지고, 그
/// [Error]가 목록 매핑에서 **문서 하나로 스트림 전체를 죽이기** 때문이다. 그래서 여기서
/// 고정하는 것은 "어떤 값을 넣어도 던지지 않는가"와 **폴백이 어느 쪽으로 닫히는가**다.
///
/// 특히 [docInt]의 `NaN`·`±Infinity`는 `is num`을 통과하고 [num.toInt]에서
/// [UnsupportedError]를 던지는 값이라, `is` 검사만으로는 못 막는 구멍이다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/repositories/impl/firebase/doc_read.dart';

void main() {
  group('docString / docStringOrNull', () {
    test('문자열은 그대로', () {
      expect(docString('메가커피'), '메가커피');
      expect(docStringOrNull('x'), 'x');
    });

    test('빈 문자열도 값으로 인정한다(폴백으로 바꾸지 않는다)', () {
      expect(docString('', '기본'), '');
      expect(docStringOrNull(''), '');
    });

    test('문자열이 아니면 폴백', () {
      for (final Object? v in <Object?>[
        null,
        1,
        1.5,
        true,
        <int>[1],
        <String, int>{}
      ]) {
        expect(docString(v), '');
        expect(docString(v, '🎁'), '🎁');
        expect(docStringOrNull(v), isNull);
      }
    });
  });

  group('docBool — 결측과 손상의 방향을 나눈다', () {
    test('bool은 그대로', () {
      expect(docBool(true, ifAbsent: false, ifCorrupt: false), isTrue);
      expect(docBool(false, ifAbsent: true, ifCorrupt: true), isFalse);
    });

    test('값이 없으면 ifAbsent', () {
      expect(docBool(null, ifAbsent: false, ifCorrupt: true), isFalse);
      expect(docBool(null, ifAbsent: true, ifCorrupt: false), isTrue);
    });

    test('값은 있는데 타입이 어긋나면 ifCorrupt', () {
      // 잠가 둔 정책이 손상 하나로 풀리지 않게 하는 갈림길.
      for (final Object v in <Object>['yes', 1, 0, <String>[]]) {
        expect(docBool(v, ifAbsent: false, ifCorrupt: true), isTrue);
      }
    });
  });

  group('docInt', () {
    test('정수·실수는 int로', () {
      expect(docInt(5), 5);
      expect(docInt(5.9), 5); // truncate
      expect(docInt(-3.2), -3);
    });

    test('숫자가 아니면 null', () {
      for (final Object? v in <Object?>[
        null,
        'many',
        true,
        <int>[1]
      ]) {
        expect(docInt(v), isNull);
      }
    });

    test('NaN·무한대는 null — toInt()가 UnsupportedError(Error)를 던지는 값이다', () {
      // `is num`은 통과하므로 타입 검사만으로는 못 막는다. Firestore는 IEEE 754 double을
      // 그대로 저장하므로 이 값들이 실제 문서에 들어올 수 있다.
      expect(() => double.nan.toInt(), throwsUnsupportedError);
      expect(() => double.infinity.toInt(), throwsUnsupportedError);

      expect(docInt(double.nan), isNull);
      expect(docInt(double.infinity), isNull);
      expect(docInt(double.negativeInfinity), isNull);
    });

    test('유한하지만 거대한 값은 통과한다 — 범위는 호출부 책임이다', () {
      // 이 계약을 문서가 아니라 테스트로 못박는다. `docInt`만 믿고 상한을 안 두면
      // 정원 같은 필드가 int64 최대값으로 포화한다.
      expect(1e300.isFinite, isTrue);
      expect(docInt(1e300), 9223372036854775807);
    });
  });

  group('docListOrNull', () {
    test('리스트는 그대로, 아니면 null', () {
      expect(docListOrNull(<dynamic>[1, 2]), <dynamic>[1, 2]);
      expect(docListOrNull(<dynamic>[]), isEmpty);
      for (final Object? v in <Object?>[
        null,
        'not-a-list',
        1,
        <String, int>{}
      ]) {
        expect(docListOrNull(v), isNull);
      }
    });
  });

  group('docDate / docDateOrNull', () {
    final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime when = DateTime(2026, 8, 19, 12);

    test('Timestamp·DateTime을 해석한다', () {
      expect(docDate(Timestamp.fromDate(when)), when);
      expect(docDate(when), when);
      expect(docDateOrNull(Timestamp.fromDate(when)), when);
    });

    test('그 밖의 값은 docDate=epoch(닫히는 쪽) / docDateOrNull=null', () {
      for (final Object? v in <Object?>[null, 'nope', 3, true]) {
        expect(docDate(v), epoch);
        expect(docDateOrNull(v), isNull);
      }
    });
  });

  group('isUsableDocId — doc(\'\')이 ArgumentError를 던지는 것을 막는다', () {
    test('비어 있지 않은 문자열만 참', () {
      expect(isUsableDocId('gx-1'), isTrue);
      expect(isUsableDocId(''), isFalse);
      expect(isUsableDocId(null), isFalse);
    });
  });
}
