/// KeepCon 공유 계약 — 딥링크/알림 목적지 버스 provider (SSOT).
///
/// 앱 바깥의 신호가 앱 안의 화면 전환으로 이어지는 **유일한 통로**다. 딥링크 수신부와
/// 알림 탭 핸들러는 여기에 목적지를 실기만 하고, 소비(탭 전환·시트 열기)는 셸이 한 곳에서
/// 처리한다 — 수신 경로마다 화면을 직접 조작하면 "어느 경로로 들어왔느냐"에 따라 동작이
/// 갈린다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../deeplink/app_destination.dart';
import '../deeplink/deep_link_parser.dart';

/// 아직 처리되지 않은 목적지(1회성). **SSOT.**
///
/// 앱 시작 시 웹 진입 URL에서 시드되고, 안드로이드에서는 `app_links` 수신부가 채운다.
/// 셸이 소비 즉시 `null`로 비운다 — 비우지 않으면 탭을 오갈 때마다 참여 시트가 다시 뜬다.
///
/// 로그인 전에 링크가 도착할 수 있으므로(초대 링크로 앱을 처음 여는 경우가 그렇다)
/// 값은 **로그인 여부와 무관하게 보관**되고, 셸이 뜨는 시점에 소비된다.
///
/// 승격 이력: 초대 한정이던 `pendingInviteCodeProvider`(share 페이지 소유, 웹 전용)를
/// 두 번째 소비자(알림 탭)가 생기면서 목적지 계약으로 일반화했다.
final StateProvider<AppDestination?> pendingDestinationProvider =
    StateProvider<AppDestination?>((Ref ref) => destinationFromPlatformUrl());
