---
name: contract-design
description: "KeepCon 공유 계약(데이터 모델·Repository 인터페이스·함수 시그니처·라우트·상태 전이)을 lib/shared/에 단일 진실 원천으로 설계·유지하는 스킬. 페이지 간 의존성의 기준을 확정하고 의존성 매트릭스를 작성한다. 계약 정의/변경/확장, 공유 타입 설계 작업 시 사용. 후속 작업(계약 추가·수정·breaking change 관리)에도 적용."
---

# Contract Design — KeepCon 공유 계약 설계

KeepCon의 4개 페이지가 서로 안전하게 연동하려면, 모두가 참조하는 **단일 진실 원천(SSOT)** 이 필요하다. 이 스킬은 그 계약을 `lib/shared/`에 설계하는 방법을 정의한다. 계약이 흔들리면 4개 페이지가 전부 흔들린다 — 그래서 계약은 신중히 확정하고, 확정 후에는 함부로 바꾸지 않는다.

## 계약이 담는 것

| 범주 | 위치 | 내용 |
|------|------|------|
| 데이터 모델 | `lib/shared/models/` | `User`, `Gifticon`, `Group`, `GroupMember`, `SharedGifticon`, `UsageLog` + enum |
| Repository 인터페이스 | `lib/shared/repositories/` | `AuthRepository`, `GifticonRepository`, `GroupRepository`, `ShareRepository`, `NotificationService`의 abstract class |
| Mock 구현(선택) | `lib/shared/repositories/impl/` | 페이지가 즉시 병렬 개발할 수 있게 하는 in-memory 구현 |
| **공유 DI provider** | `lib/shared/providers/` | 여러 페이지가 공유하는 Riverpod provider(`authRepositoryProvider`, `gifticonRepositoryProvider` 등)의 **단일 정본**. 페이지 폴더에 두면 페이지마다 별도 인스턴스가 생겨 데이터가 연결되지 않는다 |
| 라우트 | `lib/shared/routes.dart` | named route 상수 |
| 의존성 매트릭스 | `_workspace/01_contract_dependency_matrix.md` | 누가 무엇을 소비/생산하는지 (개발자·QA의 기준 문서) |

## 설계 원칙

- **함수명은 계약이다.** 메서드 이름·파라미터명·파라미터 순서·반환 타입을 확정하면, 그것이 곧 4개 페이지가 의존하는 인터페이스다. 확정 후 변경은 breaking change로 취급하고 아래 절차를 따른다.
- **인터페이스 우선.** 구체 구현이 아니라 abstract class로 계약을 정의한다. 페이지는 인터페이스에만 의존하므로 백엔드 구현을 나중에 바꿔도 페이지가 안 깨진다.
- **공유 의존성 주입(DI)은 계약이 소유한다.** 여러 페이지가 같은 Repository/Service 인스턴스를 공유해야 하면, 그 Riverpod provider를 처음부터 `lib/shared/providers/`에 정본으로 둔다. 페이지가 각자 provider를 선언하면 서로 다른 인스턴스를 참조해 "한쪽이 추가한 데이터가 다른 쪽에 안 보이는" 조용한 런타임 버그가 난다. 앱 조립부(`main.dart`의 `ProviderScope overrides`)에서 실제 구현으로 교체하는 규칙도 계약 주석에 명시한다.
- **enum으로 값을 못 박는다.** 상태(`GifticonStatus`), 정렬(`SortOption`), 필터(`FilterOption`), 공유 상태(`ShareStatus`), 알림 종류(`NotificationType`)는 문자열이 아니라 enum으로 정의한다. 이것이 페이지 간 매직 스트링 불일치를 원천 차단한다.
- **네이밍 일관성.** Dart 관례 — 클래스 UpperCamelCase, 메서드/필드 lowerCamelCase, enum 값 lowerCamelCase, 파일 snake_case. camelCase↔snake_case 혼용 금지.
- **최소하고 충분하게.** 지금 페이지들이 실제로 필요로 하는 것만 정의한다. 미래를 과도하게 추측한 필드는 넣지 않되, 명백한 크로스페이지 필드(만료일·카테고리·상태)는 빠뜨리지 않는다.

## 핵심: 크로스페이지 필드를 놓치지 마라

경계면 버그의 최대 원인은 "생산자가 안 채운 필드를 소비자가 기대하는 것"이다. 모델 설계 시 다음을 반드시 확인한다:

- **`Gifticon`** — 메인의 정렬(만료일 등)과 필터(카테고리·상태)가 쓰는 필드를 포함하고, 스캔이 그것을 채울 수 있는지 확인. 스캔이 확보 불가능한 필드는 nullable로 하고 기본값 규칙을 매트릭스에 명시.
- **상태 전이** — `GifticonStatus`의 허용 전이(예: `available → used`, `available → expired`)를 명시한다. 공유의 사용 동기화와 메인의 필터가 이 전이를 공유한다.
- **소유/식별** — `Gifticon`·`Group`·`SharedGifticon`이 `User`를 어떻게 참조하는지(userId 등) 일관되게 정한다.

## 의존성 매트릭스 작성

`_workspace/01_contract_dependency_matrix.md`에 다음 표를 유지한다:

```markdown
## 계약 요약
| 계약 | 종류 | 위치 | v |
|------|------|------|---|
| Gifticon | model | lib/shared/models/gifticon.dart | 1 |
| GifticonRepository.addGifticon(Gifticon) → Future<Gifticon> | method | ... | 1 |
| ... | | | |

## 페이지별 소비/생산
| 페이지 | 소비 | 생산 |
|--------|------|------|
| auth   | User | AuthRepository.currentUser |
| main   | Gifticon, GifticonRepository.watchGifticons(userId), SortOption, FilterOption | - |
| scan   | Gifticon, AuthRepository.currentUser | GifticonRepository.addGifticon(...) |
| share  | Group, SharedGifticon, GifticonRepository.updateStatus(...) | UsageLog, 그룹 상태 |

## 크로스페이지 주의점
- scan이 채워야 하는 Gifticon 필수 필드: expiryDate, category, status(=available)
- share 사용 동기화: GifticonRepository.updateStatus(id, GifticonStatus.used) → main 필터 반영
- 허용 상태 전이: available→used, available→expired, (공유취소)shared→available
```

## Breaking change 절차

계약 시그니처를 바꿔야 하면:

1. 변경 전/후 시그니처를 매트릭스에 기록한다.
2. **의존하는 페이지 개발자에게만** 정확한 변경 내용을 SendMessage로 알린다(누가 의존하는지는 매트릭스로 판단).
3. 가능하면 하위호환(오버로드/새 메서드 추가 후 구 메서드 deprecate)을 우선하고, 불가피할 때만 깨는 변경을 한다.
4. `integration-qa`에게 재검증을 요청한다.

## 후속 작업 시

- 기존 `lib/shared/`와 매트릭스를 먼저 읽고 증분 변경한다. 새 페이지 요구가 기존 계약으로 충족되면 새로 만들지 말고 재사용을 안내한다.
- 두 페이지가 상충하는 계약을 요청하면 병기 후 통합안을 제시하고 합의를 구한다.
