// 한글 조사 자동 선택 유틸(josa / KoreanJosa) 테스트.
//
// 받침 유무에 따른 을/를·이/가·은/는·와/과 선택과, 한글이 아닌 문자로 끝나는
// 경우(영문·숫자·기호)의 fallback(받침 없음 취급) 동작을 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/share/data/korean_particle.dart';

void main() {
  group('josa — 을/를', () {
    test('받침 있는 글자 뒤에는 을', () {
      expect('금액권'.eulReul, '을'); // 권: 받침 ㄴ
      expect('세븐'.eulReul, '을'); // 븐: 받침 ㄴ
      // 숫자·기호가 섞여도 마지막 글자가 한글이면 그 받침으로 판정한다.
      expect('5,000원 금액권'.eulReul, '을'); // 마지막 '권' → 받침 있음
    });

    test('받침 없는 글자 뒤에는 를', () {
      expect('아메리카노'.eulReul, '를'); // 노: 받침 없음
      expect('세트'.eulReul, '를'); // 트: 받침 없음
      expect('초대 링크'.eulReul, '를'); // 크: 받침 없음
      expect('초대코드'.eulReul, '를'); // 드: 받침 없음
    });

    test('한글이 아닌 문자로 끝나면 받침 없음으로 간주(를)', () {
      // 문서화된 단순화: 영문·숫자·기호 종료는 발음 관례가 제각각이라 받침 없음(를)으로
      // 처리한다. 실제 발음 문법(예: 3=삼 → 을)과 다를 수 있음을 감안한 의도적 동작이다.
      expect('아메리카노 T'.eulReul, '를'); // 영문 T 종료 (실제 발음 '티'도 받침 없음)
      expect('쿠폰 3'.eulReul, '를'); // 숫자 종료 → 단순화상 를 (발음 문법과는 다름)
      expect('상품권!'.eulReul, '를'); // 기호 종료 → 받침 없음 취급
    });

    test('빈 문자열은 를(받침 없음 기본)', () {
      expect(''.eulReul, '를');
    });
  });

  group('josa — 이/가 · 은/는 · 와/과', () {
    test('받침 있는 글자', () {
      expect('사람'.iGa, '이'); // 람: 받침 ㅁ
      expect('사람'.eunNeun, '은');
      expect('사람'.waGwa, '과');
    });

    test('받침 없는 글자', () {
      expect('친구'.iGa, '가'); // 구: 받침 없음
      expect('친구'.eunNeun, '는');
      expect('친구'.waGwa, '와');
    });
  });
}
