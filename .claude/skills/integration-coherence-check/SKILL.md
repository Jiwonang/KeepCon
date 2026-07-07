---
name: integration-coherence-check
description: "KeepCon 페이지 간 통합 정합성을 검증하는 스킬. 공유 계약과 페이지 구현을 양쪽 동시에 읽어 경계면(Repository 시그니처·모델·enum·상태전이·라우트)을 교차 비교하고, 중복 구현·잘못된 함수명·매직 스트링·무단 상태전이를 잡는다. 페이지 모듈 완성 직후 점진적으로 검증. 통합 검증·연동 오류 점검·QA 작업 시 사용. 후속 작업(회귀 검증, 특정 경계면 재검증)에도 적용."
---

# Integration Coherence Check — KeepCon 통합 정합성 검증

담당이 나뉜 페이지들은 각각 `flutter analyze`를 통과해도 연결 지점에서 계약이 어긋날 수 있다. 이 스킬은 그 경계면 버그를 잡는 **교차 비교** 방법론이다. 핵심 원칙은 하나 — **한쪽만 읽지 말고, 생산자와 소비자를 동시에 열어 비교한다.**

## 왜 정적 분석으로는 부족한가

- `flutter analyze` 통과 ≠ 정합성. 매직 스트링 불일치, 미채워진 필드, 무단 상태 전이는 컴파일러가 못 잡는다.
- "함수가 존재하는가?"와 "호출측의 기대와 정확히 일치하는가?"는 전혀 다른 검증이다.
- 그래서 이 스킬은 **존재 확인이 아니라 교차 비교**를 한다.

## 검증 절차 (경계면별)

### 1. Repository 시그니처 대조
- `lib/shared/repositories/*.dart`의 abstract 메서드를 모두 추출한다(이름·파라미터·반환 타입).
- 각 페이지에서 그 메서드 호출부를 `Grep`으로 찾아 시그니처가 일치하는지 확인한다.
- **두 방향 모두** 플래그: (a) 페이지가 호출하는데 계약에 없는 메서드(잘못된 함수명/추측 호출), (b) 계약에 있는데 아무도 안 쓰는 메서드(연동 누락 가능성).

### 2. 중복 정의 탐지
- `Grep`으로 `class User`, `class Gifticon`, `class Group`, `class GroupMember`, `class SharedGifticon`, `class UsageLog`를 전체 검색.
- `lib/shared/models/` **밖**에서 동일 개념이 재정의되면 중복 위반 → 해당 페이지에 계약 import로 교체 지시.

### 3. enum / 매직 스트링 대조
- 계약의 `GifticonStatus`, `SortOption`, `FilterOption`, `ShareStatus`, `NotificationType` 정의를 읽는다.
- 페이지에서 상태/정렬/필터를 문자열 리터럴로 다루는 코드를 `Grep`(예: `"available"`, `"used"`, `"expired"`, `"latest"`)으로 찾는다.
- 매직 스트링 발견 시 계약 enum으로 교체 지시. 특히 scan이 세팅하는 값과 main이 필터링하는 값이 같은 enum을 쓰는지 확인.

### 4. 상태 전이 완전성
- 계약이 정의한 허용 전이 목록을 읽는다.
- share·scan의 모든 status 갱신 코드(`updateStatus(...)`, `status = ...`)를 찾아 각 전이가 허용 목록에 있는지 확인.
- **무단 전이**(정의 안 된 전이 수행)와 **죽은 상태**(정의됐지만 도달 불가)를 식별.
- 특히 share의 사용 동기화 status가 main의 필터 분기(`if status == ...`)와 일치하는지 교차 확인 — 이게 어긋나면 "사용했는데 목록에 반영 안 됨" 버그.

### 5. 라우트 대조
- `lib/shared/routes.dart` 상수와 페이지의 `Navigator.pushNamed`/`pushReplacementNamed` 인자를 대조.
- 하드코딩 경로 문자열을 플래그 → 상수로 교체 지시.

### 6. 정적 분석(보조)
- `flutter analyze` 실행. 경고를 보고하되, 위 1~5의 교차 검증이 우선순위가 높다.

## 리포트 형식

`_workspace/qa_report.md`에 다음을 심각도순으로 기록:

```markdown
# QA 리포트 (YYYY-MM-DD, 검증 범위: {페이지/경계면})

## 요약
- 통과: N / 실패: M / 미검증(미구현): K

## 실패 항목 (심각도순)
### [치명] scan → main 필드 누락
- 위치: lib/features/scan/scan_controller.dart:88
- 문제: Gifticon 생성 시 expiryDate 미설정 → main의 만료임박 정렬에서 제외됨
- 수정: expiryDate를 필수 입력받거나 계약의 기본값 규칙 적용. main-page-dev와 scan-page-dev 모두 통지.

### [경계] share 상태전이 불일치
- ...

## 통과 항목
- auth.currentUser ↔ main/scan/share 소비: 일치

## 미검증 (미구현)
- share 그룹 알림: NotificationService 미구현
```

각 실패는 **파일:라인 + 문제 + 구체적 수정 방법 + 통지 대상**을 포함한다.

## 점진적 검증 원칙

전체 완성 후 1회가 아니라, **각 페이지가 완성될 때마다 즉시** 해당 페이지와 그 경계면을 검증한다. 계약이 변경되면 그 계약에 의존하는 모든 페이지를 재검증한다. 이렇게 해야 초기 불일치가 후속 모듈로 전파되지 않는다.

## 후속 작업 시

- 기존 `_workspace/qa_report.md`가 있으면 먼저 읽고, 이전 지적 항목의 수정 여부를 회귀 확인한 뒤 신규 검증을 진행한다.
- 특정 경계면만 재검증 요청받으면 그 경계면 절차만 수행한다.
