# KeepCon — release(R8) 빌드 규칙.
#
# ML Kit 텍스트 인식 플러그인은 4개 언어 모델을 모두 참조하는 코드를 담고 있지만,
# 그 모델들은 플러그인에서 `compileOnly`라 실제 APK에는 앱이 선언한 것만 들어간다.
# KeepCon은 한국어만 쓰므로(`app/build.gradle.kts`의 dependencies 참조), 나머지 셋은
# 클래스가 없는 상태가 **정상**이다. R8은 이를 "Missing class" 오류로 보고 빌드를
# 세우므로, 쓰지 않는 셋만 골라 경고를 끈다.
#
# ⚠️ 한국어는 여기에 넣지 않는다 — 진짜로 빠졌을 때 빌드가 조용히 통과하고
#    실기기에서 스캔할 때 `NoClassDefFoundError`로 죽는 편이 훨씬 나쁘다.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
