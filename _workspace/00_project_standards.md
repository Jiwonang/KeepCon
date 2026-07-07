# KeepCon 프로젝트 전역 표준 (검증 실행용)

> 이것은 하네스 검증(validation) 실행을 위한 임시 표준이다. 실제 개발 시 사용자와 재확정한다.

- **상태관리:** Riverpod (flutter_riverpod). 페이지마다 다른 것을 쓰지 않는다.
- **데이터 계층:** 실제 백엔드 없이 in-memory/mock Repository 구현으로 진행. 계약은 abstract interface로 정의하고 mock 구현체는 `lib/shared/repositories/impl/`에 둔다.
- **Flutter 프로젝트:** 이 검증에서는 `pubspec.yaml` 전체 스캐폴딩보다 `lib/` 소스의 계약·페이지 코드 정합성에 집중한다. `flutter` SDK가 설치돼 있으면 `flutter analyze`를 돌리고, 없으면 정적 교차 검증으로 대체한다.
- **네이밍:** Dart 관례 (클래스 UpperCamelCase, 메서드/필드 lowerCamelCase, enum 값 lowerCamelCase, 파일 snake_case).
