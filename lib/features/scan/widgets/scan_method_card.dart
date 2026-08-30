/// scan — 등록 방식 카드(갤러리·카메라)와 '직접 입력하기' 행.
///
/// `scan_page.dart`에서 떼어냈다. 둘은 같은 화면의 형제라 한 파일에 둔다.
library;

import 'package:flutter/material.dart';

import 'package:keepcon/features/scan/util/keep_all_ko.dart';

class ScanMethodCard extends StatelessWidget {
  const ScanMethodCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ManualEntryCard extends StatelessWidget {
  const ManualEntryCard({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                color: scheme.primary,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '직접 입력하기',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    // 섹션 부제('바코드 이미지 분석 또는 수동 입력이 가능합니다.'
                    // — `scan_page.dart`)와 같은 역할·같은 화면이다. 한쪽만
                    // 처리하면 320~375px에서 위는 어절 경계로, 아래는 어절
                    // 한가운데로 갈라져 같은 화면 안에서 문단 모양이 어긋난다.
                    //
                    // ⚠️ 이 주석은 원래 `:258`이라는 줄번호를 가리켰는데 **그
                    // 번호는 처음부터 틀려 있었다**(그 자리는 `[Ref]` 관련
                    // 주석이었다). 분할하며 대상을 실제로 찾아 이름으로 바꿨다.
                    // 위 [ScanMethodCard]의 `subtitle`은 이 짝이 아니다 —
                    // 그쪽은 카드 안 보조 설명이라 일반 [Text]로 둔다.
                    KeepAllText(
                      '이미지 없이 정보를 직접 작성합니다.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
