/// 스캔/추가 페이지.
///
/// 카메라 스캔 / 갤러리 불러오기 / 수동 입력 세 경로를 제공한다. 세 경로 모두
/// 최종적으로 편집 가능한 [GifticonForm]으로 수렴해 하나의 [Gifticon]을 생성한다.
///
/// route: [AppRoutes.scan].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/routes.dart';
import 'state/gifticon_form_state.dart';
import 'widgets/gifticon_form.dart';

/// 스캔/추가 진입 화면. 세 입력 경로 선택 → 폼 화면으로 이동.
class ScanPage extends ConsumerWidget {
  const ScanPage({super.key});

  /// route 등록용 상수(계약 [AppRoutes.scan]와 일치).
  static const String routeName = AppRoutes.scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('기프티콘 추가')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _SourceButton(
              icon: Icons.photo_camera,
              label: '카메라로 스캔',
              onTap: () => _openForm(context, ref, ScanSource.camera),
            ),
            const SizedBox(height: 12),
            _SourceButton(
              icon: Icons.photo_library,
              label: '갤러리에서 불러오기',
              onTap: () => _openForm(context, ref, ScanSource.gallery),
            ),
            const SizedBox(height: 12),
            _SourceButton(
              icon: Icons.edit,
              label: '직접 입력',
              onTap: () => _openForm(context, ref, ScanSource.manual),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    ScanSource source,
  ) async {
    // 폼 컨트롤러를 선택 경로로 초기화한다.
    ref.read(gifticonFormControllerProvider.notifier).startWith(source);

    // 카메라/갤러리 경로: 실제 플러그인 연동은 후속 작업.
    // TODO(scan): image_picker/camera + 바코드·OCR 플러그인으로 이미지 획득 후
    //   prefillFromRecognition(...)로 인식 결과를 폼에 채운다. 인식 실패 필드는
    //   비워 두어 사용자가 수동 편집으로 폴백하도록 한다(현재 구조가 이미 폴백).
    if (source != ScanSource.manual) {
      _showPlaceholderNotice(context, source);
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _GifticonFormScreen(),
      ),
    );
  }

  void _showPlaceholderNotice(BuildContext context, ScanSource source) {
    final name = source == ScanSource.camera ? '카메라' : '갤러리';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name 인식은 준비 중입니다. 아래 폼에서 직접 입력/수정하세요.'),
      ),
    );
  }
}

/// 폼 화면. 세 경로 공통으로 이 화면에서 [Gifticon]을 완성해 저장한다.
class _GifticonFormScreen extends ConsumerWidget {
  const _GifticonFormScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(
      gifticonFormControllerProvider.select((s) => s.source),
    );
    final title = switch (source) {
      ScanSource.camera => '카메라 스캔 결과 확인',
      ScanSource.gallery => '갤러리 인식 결과 확인',
      ScanSource.manual => '기프티콘 직접 입력',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const GifticonForm(),
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 28),
        label: Text(label, style: const TextStyle(fontSize: 16)),
        onPressed: onTap,
      ),
    );
  }
}
