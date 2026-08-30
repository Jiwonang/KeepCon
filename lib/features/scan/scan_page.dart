/// 스캔/추가 페이지.
///
/// 카메라 스캔 / 갤러리 불러오기 / 수동 입력 세 가지 경로를 제공한다.
/// 세 경로는 최종적으로 모두 [GifticonFormScreen]으로 이동한다
/// (`pages/gifticon_form_page.dart`).
///
/// route: [AppRoutes.scan]
library;

import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image_picker/image_picker.dart';

import 'package:keepcon/features/scan/services/gifticon_ocr_parser.dart';
import 'package:keepcon/features/scan/services/ml_kit_service.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/features/scan/state/scan_target_group_state.dart';
import 'package:keepcon/features/scan/util/keep_all_ko.dart';
import 'package:keepcon/features/scan/pages/gifticon_form_page.dart';
import 'package:keepcon/features/scan/widgets/barcode_scanner_screen.dart';
import 'package:keepcon/features/scan/widgets/category_tile.dart';
import 'package:keepcon/features/scan/widgets/scan_method_card.dart';
import 'package:keepcon/features/scan/widgets/target_tile.dart';
import 'package:keepcon/shared/diagnostics/report_handled_failure.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/providers/my_groups_provider.dart';
import 'package:keepcon/shared/widgets/inline_error_banner.dart';

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  GifticonCategory _selectedCategory = GifticonCategory.cafe;
  String? _selectedTargetGroupId; // null이면 내 지갑(개인 소장)
  bool _busy = false;

  /// 지금 실제로 저장 대상이 되는 그룹 id.
  ///
  /// 골라 둔 그룹이 목록에서 사라질 수 있다 — 다른 기기에서 탈퇴·강퇴됐거나,
  /// 그룹 스트림이 실패해 파생 provider가 빈 목록으로 접었을 때다. 그때 저장해 둔
  /// id를 그대로 쓰면 **화면에는 아무 타일도 선택돼 있지 않은데 저장은 그 그룹을
  /// 노려**, 공유만 실패하는 부분 실패로 빠진다(그 실패 문구는 지금 어디에도
  /// 표시되지 않는다 — `gifticon_form_state.dart`의 `shareError` 주석 참조).
  ///
  /// 그래서 목록에 없으면 '내 지갑'으로 되돌린다 — 보이는 것과 저장되는 곳이
  /// 일치한다. 대가로, 스트림 실패로 목록이 접힌 경우 사용자가 고른 그룹 대신
  /// 지갑에 조용히 저장된다. 그 상태는 이제 섹션 맨 위 배너·진행 표시가 알린다
  /// ([scanGroupsUnavailableProvider]·[scanGroupsPendingProvider] —
  /// `scan_target_group_state.dart` doc).
  String? _resolveTargetGroupId(List<Group> groups) {
    final String? id = _selectedTargetGroupId;
    if (id == null) return null;

    return groups.any((Group g) => g.id == id) ? id : null;
  }

  /// 스캔 프레임(JPEG)을 임시 파일로 떨군다.
  ///
  /// ML Kit의 [InputImage.fromFilePath]와 폼의 이미지 미리보기([Image.file])가
  /// 모두 경로를 요구하므로, 바이트를 한 번만 파일로 만들어 둘 다에 쓴다.
  /// 갤러리 경로에서 image_picker가 만드는 임시 파일과 같은 성격이다.
  Future<File> _writeTempFrame(Uint8List bytes) async {
    final Directory dir = await Directory.systemTemp.createTemp('keepcon_scan');
    final File file = File('${dir.path}/frame.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _openForm(ScanSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });

    HapticFeedback.lightImpact();

    final controller = ref.read(gifticonFormControllerProvider.notifier);
    controller.startWith(
      source,
      targetGroupId: _resolveTargetGroupId(ref.read(scanTargetGroupsProvider)),
    );

    MlKitService? mlKitService;

    try {
      if (source == ScanSource.manual) {
        controller.setCategory(_selectedCategory.label);
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const GifticonFormScreen(),
          ),
        );
        return;
      }

      // 카메라는 촬영 버튼 없이 "비추기만 해도" 인식되는 실시간 스캔을 쓴다.
      //
      // [BarcodeScannerScreen]이 첫 유효 바코드를 감지하는 즉시 pop하므로 사용자는
      // 셔터를 누를 필요가 없다. 그러면서도 인식된 **프레임**을 함께 받아 OCR을
      // 돌려, 촬영 방식이 해 주던 프리필(브랜드·상품명·금액·유효기간·이미지)을
      // 그대로 유지한다.
      if (source == ScanSource.camera) {
        controller.setCategory(_selectedCategory.label);
        if (!mounted) return;

        final BarcodeScanResult? scan =
            await Navigator.of(context).push<BarcodeScanResult>(
          MaterialPageRoute<BarcodeScanResult>(
            builder: (_) => const BarcodeScannerScreen(),
          ),
        );

        // 사용자가 인식 전에 닫았으면(null) 폼을 열지 않는다.
        if (scan == null || !mounted) return;

        controller.setBarcode(scan.barcode);

        // OCR은 **덤이다.** 프레임이 없거나 인식이 실패해도 바코드는 이미 유효하므로
        // 폼은 반드시 연다 — 여기서 예외가 새어 나가면 바깥 catch가 폼을 열지 않아,
        // 힘들게 잡은 바코드가 통째로 버려진다.
        final Uint8List? frame = scan.imageBytes;

        if (frame != null) {
          try {
            final File file = await _writeTempFrame(frame);

            mlKitService = MlKitService();
            final scanResult =
                await mlKitService.scan(InputImage.fromFilePath(file.path));
            final parsed = const GifticonOcrParser().parse(scanResult.text);

            controller.prefillFromRecognition(
              brand: parsed.brand,
              productName: parsed.productName,
              price: parsed.price,
              category: _selectedCategory.label,
              expiryDate: parsed.expiryDate,
              // ⚠️ 이 값은 **저장되지 않는다**(`gifticon_form_state.dart`의
              // `submit()` 주석 참조 — 표시되지도 않고 곧 깨지는 경로라 뺐다).
              // 그렇다고 죽은 인자가 아니다: 폼 미리보기(`gifticon_form_page.dart`의
              // `formState.imagePath` 분기)의 **유일한 입력**이다.
              //
              // 지우면 저장 전 확인 화면에서 방금 찍은 사진이 사라지는데,
              // **테스트는 652건 전부 통과한다**(실측). named 인자라 컴파일도
              // analyze도 막지 않는다 — 이 주석이 유일한 방어다.
              imagePath: file.path,
            );
          } catch (e) {
            // **여기는 보고 대상이 아니다.** OCR은 덤이고 바코드는 이미 유효하므로
            // 작업 자체는 성공한다 — 이건 실패가 아니라 성능 저하다. 프레임 품질에
            // 따라 흔히 일어나므로 [ErrorReporter]로 보내면 진짜 실패가 묻힌다.
            // 그래서 형제들과 달리 의도적으로 로그만 남긴다.
            //
            // ⚠️ 그래도 **release에서는 예외를 찍지 않는다.** [debugPrint]는 release
            // 빌드에서도 플랫폼 로그로 나가므로, 보고를 안 한다고 해서 원시 예외를
            // 그대로 실어도 되는 것은 아니다 — 이 PR이 없애려는 유출이 여기만
            // 남는다. `DebugPrintErrorReporter`가 `includeMessage: kDebugMode`로
            // 하는 것과 같은 판단이다.
            if (kDebugMode) {
              debugPrint('KeepCon: 스캔 프레임 OCR 실패(바코드만 사용): $e');
            }
          }
        }

        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const GifticonFormScreen(),
          ),
        );
        return;
      }

      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (file == null || !mounted) {
        return;
      }

      mlKitService = MlKitService();
      final inputImage = InputImage.fromFilePath(file.path);
      final scanResult = await mlKitService.scan(inputImage);
      final parsed = const GifticonOcrParser().parse(scanResult.text);

      controller.prefillFromRecognition(
        brand: parsed.brand,
        productName: parsed.productName,
        price: parsed.price,
        barcode: scanResult.firstBarcodeValue,
        category: _selectedCategory.label,
        expiryDate: parsed.expiryDate,
        // ⚠️ 저장되지 않지만 **지우면 안 된다** — 폼 미리보기의 유일한 입력이다.
        // 위 카메라 경로와 같은 이유이고, 지워도 테스트가 전부 통과한다.
        imagePath: file.path,
      );

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const GifticonFormScreen(),
        ),
      );
    } catch (e, s) {
      // **원인은 로그로, 화면에는 다음 행동만.** 여기 오는 것은 이미지 디코딩·
      // ML Kit 실패라 사용자가 예외 문자열로 할 수 있는 것이 없다. 진단은 공유
      // 계약의 진입점으로 넘긴다 — 이 자리는 [WidgetRef]가 있어 그대로 쓸 수 있다
      // (컨트롤러 쪽은 [Ref]라 못 쓴다. `gifticon_form_state.dart` 참조).
      reportHandledFailure(ref, e, s, context: 'ScanPage._openForm');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          // scan 화면군의 스낵바 넷 중 유일하게 어절 보호가 빠져 있던 자리다
          // (나머지 셋은 `pages/gifticon_form_page.dart`). 좁은
          // 폭에서 '오류가 발/생했습니다'처럼 갈라진다.
          content: KeepAllText('이미지를 처리하지 못했어요. 다시 시도해 주세요.'),
        ),
      );
    } finally {
      await mlKitService?.dispose();
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 저장 대상으로 고를 수 있는 내 그룹. 로딩·미로그인·에러는 파생 provider가
    // 빈 목록으로 접는다 — 그래서 목록만으로는 "그룹 없음"과 "못 불러옴"이 같아
    // 보인다. 둘을 가르는 판정은 별도 provider가 맡는다.
    final List<Group> targetGroups = ref.watch(scanTargetGroupsProvider);
    final bool groupsUnavailable = ref.watch(scanGroupsUnavailableProvider);
    final bool groupsPending = ref.watch(scanGroupsPendingProvider);
    final String? selectedTargetId = _resolveTargetGroupId(targetGroups);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('기프티콘 등록'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text(
                  '등록 방식을 선택해 주세요',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 6),
                KeepAllText(
                  '바코드 이미지 분석 또는 수동 입력이 가능합니다.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ScanMethodCard(
                        title: '갤러리',
                        subtitle: '앨범에서 선택',
                        icon: Icons.photo_library_rounded,
                        accentColor: scheme.primary,
                        onTap: () => _openForm(ScanSource.gallery),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ScanMethodCard(
                        title: '카메라',
                        subtitle: '직접 촬영하기',
                        icon: Icons.camera_alt_rounded,
                        accentColor: scheme.secondary,
                        onTap: () => _openForm(ScanSource.camera),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ManualEntryCard(
                  onTap: () => _openForm(ScanSource.manual),
                ),
                const SizedBox(height: 28),
                // 두 글자 덩어리를 [Flexible]로 감싼다 — 감싸지 않으면 각자 자연
                // 너비를 고집해, 글자 확대 설정(접근성)을 켠 기기에서 둘의 합이
                // 폭을 넘는다(360px·1.3배에서 1.5px 넘쳤다). 넘치면 잘려서 안
                // 보이므로, 넘기는 대신 접히게 두는 편이 읽는 데 낫다.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: KeepAllText(
                        '자주 쓰는 카테고리',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: KeepAllText(
                        '미리 분류하기',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 타일 높이는 원래 비율(0.95)로 잡되, **내용이 필요로 하는 높이
                // 아래로는 내려가지 않게 바닥을 깐다.**
                //
                // 비율만 쓰면 폭이 좁아질수록 타일이 낮아져 고정 높이인 내용이
                // 넘친다(390px에서 2.4px 오버플로 — 디버그 빌드는 매 프레임
                // 예외를 던지고 릴리스에서는 내용이 잘린다). 넓은 화면에서는
                // 비율이 이기므로 지금 보이는 모양이 그대로 유지된다.
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    const int columns = 3;
                    const double spacing = 10;

                    final double tileWidth =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                    final double byRatio = tileWidth / 0.95;
                    final double floor = CategoryTile.minExtentFor(context);

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        mainAxisExtent: byRatio > floor ? byRatio : floor,
                      ),
                      itemCount: GifticonCategory.values.length,
                      itemBuilder: (BuildContext context, int index) {
                        final category = GifticonCategory.values[index];
                        final selected = _selectedCategory == category;

                        return CategoryTile(
                          data: category,
                          selected: selected,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedCategory = category;
                            });
                          },
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  '저장할 그룹 선택',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),

                // 그룹을 못 불러왔을 때만 뜬다(`hasError && !hasValue`). 이전 값이
                // 보존된 순단 에러에는 띄우지 않는다 — 목록이 그대로 선택되므로
                // 사용자가 할 일이 없다(판정 근거는 provider doc).
                //
                // 재시도는 계약 정본의 훅으로 한다. 그룹 목록의 에러는 정본이
                // watch하는 **private 체인**(`lib/shared`)에 캐시돼 페이지에서
                // `invalidate(myGroupsProvider)`로는 되살릴 수 없다(#13 실측).
                if (groupsUnavailable) ...<Widget>[
                  InlineErrorBanner(
                    message: '그룹 목록을 불러오지 못했어요.',
                    onRetry: () => retryMyGroups(ref),
                  ),
                  const SizedBox(height: 12),
                ],

                // '내 지갑'(개인 소장)은 **항상 첫 번째**다. 그룹이 없거나 아직
                // 못 불러온 상태에서도 사용자는 언제나 저장을 진행할 수 있어야
                // 하므로, 이 타일은 목록과 무관하게 존재한다.
                TargetTile(
                  icon: Icons.account_balance_wallet_rounded,
                  label: '내 지갑',
                  selected: selectedTargetId == null,
                  onTap: () => setState(() => _selectedTargetGroupId = null),
                ),

                // 아직 첫 방출 전이면 진행 표시를 둔다 — 이 화면은 '그룹 없음'을
                // 타일의 **부재**로 말하므로, 로딩을 무음으로 두면 위 배너가 가른
                // 것과 똑같은 위장이 로딩 축에 남는다(실측: 콜드 스타트 화면이
                // "정말 그룹이 없을 때"와 픽셀 단위로 같았다).
                //
                // 재시도 중에도 뜬다 — 그때 상태는 `AsyncError(isLoading: true)`라
                // 배너와 **공존**한다(배너=원인, 이것=진행 중). 배너를 숨기지 않는
                // 이유는 계약 정본의 왕복 깜빡임 규약이다.
                if (groupsPending) ...<Widget>[
                  const SizedBox(height: 14),
                  const Center(
                    // 팔레트에 크기 토큰이 없어 리터럴이다. 저장소의 인라인
                    // 스피너는 16·18·22로 갈려 있고 **그것들은 모두 버튼 아이콘
                    // 슬롯**이라, 목록 아래 독립 스피너인 이 자리에 정확히
                    // 대응하는 선례는 없다. 가장 작은 값을 골라 목록을 밀어내지
                    // 않게 한다.
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],

                // 내가 속한 그룹. 목록이 비면 아무것도 그리지 않고 '내 지갑'만
                // 남는다 — 그 이유가 '그룹 없음'인지 '못 불러옴'인지는 위 배너가,
                // '아직 못 받음'인지는 위 진행 표시가 가른다.
                for (final Group group in targetGroups) ...<Widget>[
                  const SizedBox(height: 10),
                  TargetTile(
                    emoji: group.emoji,
                    icon: Icons.groups_rounded,
                    label: group.name,
                    selected: selectedTargetId == group.id,
                    onTap: () =>
                        setState(() => _selectedTargetGroupId = group.id),
                  ),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
