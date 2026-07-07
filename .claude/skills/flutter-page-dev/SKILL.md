---
name: flutter-page-dev
description: "KeepCon Flutter 페이지를 구현할 때 따르는 공통 규약 스킬. 공유 계약(lib/shared) 소비 방법, 페이지 간 의존성 확인 절차(중복 구현 방지·함수명 정합성·연동 검증), Flutter 폴더/네이밍/상태관리 표준을 담는다. 로그인·메인·스캔·공유 페이지 개발 작업 시, 또는 페이지 코드를 작성/수정하기 전에 반드시 이 스킬을 사용. 후속 작업(특정 화면만 다시, 기능 수정, 연동 오류 수정)에도 적용."
---

# Flutter Page Dev — KeepCon 페이지 구현 공통 규약

KeepCon은 4명의 담당자가 페이지별(로그인/설정·메인·스캔·공유)로 나눠 개발한다. 각 페이지는 독립적으로 잘 만들어져도, **연결 지점의 계약이 어긋나면 통합 시 버그가 난다.** 이 스킬은 그 경계면 버그를 개발 단계에서 미리 막기 위한 공통 규약이다. 페이지 코드를 작성/수정하기 전에 이 규약을 적용한다.

## 왜 이 규약이 필요한가

담당이 나뉜 상황에서 가장 흔한 3대 사고:
1. **중복 구현** — 다른 페이지(또는 공유 계약)에 이미 있는 모델/함수를 모르고 다시 만든다 → 타입 불일치, 유지보수 지옥.
2. **잘못된 함수명 의존** — 소비할 함수의 이름/파라미터를 추측으로 부른다 → 컴파일 오류 또는 런타임 크래시.
3. **값 규약 불일치** — 한쪽은 enum, 다른 쪽은 매직 스트링으로 같은 개념을 표현한다 → 필터/동기화가 조용히 실패.

이 셋을 막는 유일한 방법은 **작성 전에 계약을 읽고, 추측 대신 확인하는 것**이다.

## 개발 착수 전 체크리스트 (매번)

코드를 쓰기 전에 순서대로 확인한다:

1. **계약을 먼저 읽는다.** `lib/shared/`의 모델·Repository 인터페이스·라우트와 `_workspace/01_contract_dependency_matrix.md`를 읽는다. 계약이 아직 없으면 `contract-architect`의 v1을 기다리고, 그동안은 계약에 의존하지 않는 UI 스캐폴딩만 한다.
2. **내가 소비할 것을 목록화한다.** 이 페이지가 다른 페이지/계약에서 가져다 쓰는 모델·함수·enum·라우트를 적는다. 각각이 계약에 **실제로 존재하는지** 확인한다 — 이름·파라미터·반환 타입까지.
3. **없으면 추측하지 말고 요청한다.** 필요한 모델/메서드/enum 값이 계약에 없으면, 직접 만들지 말고 `contract-architect`에게 SendMessage로 추가를 요청한다. (임의 생성이 곧 경계면 버그의 씨앗이다.)
4. **내가 생산할 것을 알린다.** 이 페이지가 다른 페이지에 노출하는 것(예: auth의 `currentUser`, scan이 채우는 `Gifticon` 필드)이 있으면, 소비하는 개발자에게 정확한 접근 방식을 SendMessage로 공유한다.

## 계약 소비 규칙

- **모델은 절대 재정의하지 않는다.** `User`, `Gifticon`, `Group` 등은 `lib/shared/models/`의 단일 정의를 import한다. 페이지 폴더 안에서 `class Gifticon` 같은 것을 다시 선언하면 즉시 중복 위반이다.
- **Repository는 인터페이스를 통해서만 쓴다.** 페이지는 `contract-architect`가 정의한 abstract 인터페이스(`GifticonRepository` 등)에만 의존하고, 구체 구현에 직접 결합하지 않는다. 메서드는 **계약에 적힌 이름·파라미터 그대로** 호출한다. 오타·순서 변경·유사한 다른 이름 사용 금지.
- **상태/정렬/필터는 enum으로만.** `"used"`, `"latest"` 같은 문자열 리터럴을 직접 쓰지 않는다. 계약의 `GifticonStatus`, `SortOption`, `FilterOption`을 사용한다. 이것이 페이지 간 값 일치를 보장한다.
- **라우트는 상수로만.** 화면 이동은 `lib/shared/routes.dart`의 named route 상수를 사용한다. 경로 문자열을 하드코딩하지 않는다.
- **공유 provider를 페이지에서 재선언하지 않는다.** 여러 페이지가 공유하는 Repository/Service의 Riverpod provider(`gifticonRepositoryProvider` 등)는 `lib/shared/providers/`의 단일 정본을 import한다. 페이지 폴더에 provider를 새로 선언하면 페이지마다 별도 인스턴스가 생겨, 내가 저장한 데이터가 다른 페이지에 안 보이는 연동 버그가 난다. 공유 provider가 아직 계약에 없으면 만들지 말고 `contract-architect`에게 `lib/shared/providers/`로 승격을 요청한다.

## Flutter 프로젝트 규약

| 항목 | 규약 |
|------|------|
| 폴더 구조 | 페이지별 코드는 `lib/features/{auth\|main\|scan\|share}/`. 공유는 `lib/shared/`. |
| 파일명 | snake_case (`login_page.dart`) |
| 네이밍 | 클래스 UpperCamelCase, 메서드/필드 lowerCamelCase, enum 값 lowerCamelCase |
| 화면 위젯 | `{Feature}Page` / `{Feature}Screen` 규칙을 프로젝트 표준에 맞춰 일관 사용 |
| 상태관리 | 오케스트레이터가 지정한 프로젝트 표준(예: Riverpod/Provider/Bloc) **하나만** 사용. 페이지마다 다른 것을 쓰지 않는다. |
| null 안전성 | 계약 모델의 nullable 여부를 존중하고, null 가능 값은 반드시 처리 |
| 정적 분석 | 작업 완료 전 `flutter analyze`로 경고 0 확인 |

> 상태관리·패키지 선택 등 프로젝트 전역 표준이 아직 안 정해졌으면 오케스트레이터/`contract-architect`에게 확인한다. 페이지마다 임의로 정하면 통합이 깨진다.

## 완료 전 자기 검증

페이지(또는 기능) 완성 후, `integration-qa`에 넘기기 전에 스스로 확인한다:

- [ ] `lib/shared/` 밖에서 공유 모델을 재정의하지 않았다
- [ ] 호출한 Repository 메서드가 모두 계약에 존재하고 시그니처가 일치한다
- [ ] 상태/정렬/필터에 매직 스트링 대신 계약 enum을 사용했다
- [ ] 화면 이동에 `routes.dart` 상수를 사용했다
- [ ] 내가 다른 페이지에 노출하는 접근점을 소비자에게 공유했다
- [ ] `flutter analyze` 경고 0

## 후속 작업 시

- 사용자가 특정 화면/기능만 지목하면 그 부분만 수정한다. 기존 `lib/features/{내 페이지}/`를 먼저 읽고 증분 변경한다.
- 계약이 변경됐다는 알림을 받으면, 내 소비 코드가 새 시그니처와 일치하는지 재확인한다.
