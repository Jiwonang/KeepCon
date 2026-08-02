library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/models/group.dart';
import '../share/state/share_providers.dart';
import 'services/gifticon_ocr_parser.dart';
import 'state/gifticon_form_state.dart';
import 'widgets/barcode_scanner_screen.dart';
import 'widgets/gifticon_form.dart';

/// 스캔 탭 메인 페이지.
///
/// 기프티콘 등록 진입점(카메라, 갤러리, 바코드, 직접 입력)을 제공한다.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final ImagePicker _picker = ImagePicker();
  
  /// 선택된 저장 대상 그룹 ID (null이면 '내 지갑' / 개인 소장).
  String? _selectedGroupId;

  /// 폼 화면으로 이동한다.
  Future<void> _openForm(
    BuildContext context,
    ScanSource source, {
    String? imagePath,
    GifticonOcrResult? ocrResult,
  }) async {
    final controller = ref.read(gifticonFormControllerProvider.notifier);

    // 선택된 targetGroupId를 포함하여 폼 초기화
    controller.startWith(source, targetGroupId: _selectedGroupId);

    if (ocrResult != null) {
      if (ocrResult.brand != null) controller.setBrand(ocrResult.brand!);
      if (ocrResult.productName != null) controller.setProductName(ocrResult.productName!);
      if (ocrResult.price != null) controller.setPrice(ocrResult.price!);
      if (ocrResult.expiryDate != null) controller.setExpiryDate(ocrResult.expiryDate!);
      if (imagePath != null) controller.setImagePath(imagePath);
    } else if (imagePath != null) {
      controller.setImagePath(imagePath);
    }

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const GifticonForm(),
      ),
    );
  }

  /// 갤러리에서 이미지를 선택하고 OCR을 수행한다.
  Future<void> _pickImageAndParse(BuildContext context) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (image == null) return;

      if (!context.mounted) return;

      // 로딩 표시
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      const parser = GifticonOcrParser();
      final result = parser.parse(image.path);

      if (!context.mounted) return;
      Navigator.of(context).pop(); // 로딩 닫기

      await _openForm(
        context,
        ScanSource.gallery,
        imagePath: image.path,
        ocrResult: result,
      );
    } catch (e) {
      if (!context.mounted) return;
      
      // 로딩 팝업이 떠있다면 닫기
      Navigator.of(context).maybePop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지 인식 중 오류가 발생했습니다: $e')),
      );
    }
  }

  /// 바코드 스캐너를 실행한다.
  Future<void> _openBarcodeScanner(BuildContext context) async {
    final String? barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const BarcodeScannerScreen(),
      ),
    );

    if (barcode != null && context.mounted) {
      final controller = ref.read(gifticonFormControllerProvider.notifier);
      controller.startWith(ScanSource.camera, targetGroupId: _selectedGroupId);
      controller.setBarcode(barcode);

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => const GifticonForm(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 스캔 계약에 명시된 내 저장 대상 그룹 목록 구독
    final List<Group> targetGroups = ref.watch(scanTargetGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('기프티콘 등록'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '등록 방법 선택',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // 1. 갤러리 선택 (OCR)
              _ScanOptionCard(
                icon: Icons.photo_library_outlined,
                title: '갤러리에서 가져오기',
                subtitle: '쿠폰 이미지를 분석하여 자동으로 정보를 입력합니다.',
                color: theme.colorScheme.primary,
                onTap: () => _pickImageAndParse(context),
              ),
              const SizedBox(height: 12),

              // 2. 바코드 스캔
              _ScanOptionCard(
                icon: Icons.qr_code_scanner,
                title: '바코드 스캔',
                subtitle: '바코드를 직접 스캔하여 번호를 입력합니다.',
                color: theme.colorScheme.secondary,
                onTap: () => _openBarcodeScanner(context),
              ),
              const SizedBox(height: 12),

              // 3. 직접 입력
              _ScanOptionCard(
                icon: Icons.edit_note,
                title: '직접 입력하기',
                subtitle: '모든 정보를 직접 입력하여 등록합니다.',
                color: theme.colorScheme.tertiary,
                onTap: () => _openForm(context, ScanSource.manual),
              ),
              const SizedBox(height: 32),

              // 저장할 그룹 선택 영역
              Text(
                '저장할 위치 선택',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '개인 지갑에 저장하거나 공유 그룹을 선택할 수 있습니다.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              // 내 지갑 (기본 선택 타일)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _selectedGroupId == null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: _selectedGroupId == null ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: _selectedGroupId == null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('내 지갑 (개인 소장)'),
                  trailing: _selectedGroupId == null
                      ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedGroupId = null;
                    });
                  },
                ),
              ),

              // 동적 공유 그룹 목록
              if (targetGroups.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...targetGroups.map((group) {
                  final isSelected = _selectedGroupId == group.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.group_outlined,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        title: Text(group.name),
                        subtitle: Text('멤버 ${group.members.length}명'),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedGroupId = group.id;
                          });
                        },
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanOptionCard extends StatelessWidget {
  const _ScanOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}