# KeepCon 프로젝트 전역 표준 (검증 실행용)

> 이것은 하네스 검증(validation) 실행을 위한 임시 표준이다. 실제 개발 시 사용자와 재확정한다.

- **상태관리:** Riverpod (flutter_riverpod). 페이지마다 다른 것을 쓰지 않는다.
- **데이터 계층:** 실제 백엔드 없이 in-memory/mock Repository 구현으로 진행. 계약은 abstract interface로 정의하고 mock 구현체는 `lib/shared/repositories/impl/`에 둔다.
- **Flutter 프로젝트:** 이 검증에서는 `pubspec.yaml` 전체 스캐폴딩보다 `lib/` 소스의 계약·페이지 코드 정합성에 집중한다. `flutter` SDK가 설치돼 있으면 `flutter analyze`를 돌리고, 없으면 정적 교차 검증으로 대체한다.
- **네이밍:** Dart 관례 (클래스 UpperCamelCase, 메서드/필드 lowerCamelCase, enum 값 lowerCamelCase, 파일 snake_case).

## 스캔 페이지 패키지 표준 (2026-07-30 사용자 확정)

- **갤러리/이미지:** image_picker + google_mlkit_text_recognition(korean) + google_mlkit_barcode_scanning (기확정, 구현 완료)
- **카메라 실시간 바코드/QR 스캔:** **mobile_scanner** — ML Kit 기반 실시간 스캐너 위젯. 플래시·카메라 전환 내장, 웹 부분 지원.
- **카테고리:** 계약상 자유 문자열(기본값 "기타") 유지. 스캔 페이지의 프리셋 칩은 페이지 로컬(두 번째 소비자가 생기면 승격 — 메인 필터는 데이터에서 동적 도출하므로 현재 불필요).
