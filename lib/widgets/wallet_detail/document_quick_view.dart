import 'package:flutter/material.dart';

import '../../models/wallet_detail_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Quick View — a peek at a document's key details (name, type, and the
/// OCR-extracted fields) WITHOUT opening the full file. Requirement #6: the user
/// should not need to open the document every time to see what's inside.
///
/// Presented as a bottom sheet with an "Open Full Document" action to continue
/// into the full viewer.
Future<void> showDocumentQuickView(
  BuildContext context, {
  required DocumentRecord record,
  required List<Color> accent,
  required VoidCallback onOpenFull,
}) {
  final palette = AppPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (context) => _QuickViewSheet(
      record: record,
      accent: accent,
      onOpenFull: onOpenFull,
    ),
  );
}

class _QuickViewSheet extends StatelessWidget {
  const _QuickViewSheet({
    required this.record,
    required this.accent,
    required this.onOpenFull,
  });

  final DocumentRecord record;
  final List<Color> accent;
  final VoidCallback onOpenFull;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final extraction = record.extraction;
    final fields = extraction.displayFields();
    final typeLabel = extraction.typeLabel ?? record.category;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: accent,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(record.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(record.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.title
                                .copyWith(color: palette.textPrimary)),
                        const SizedBox(height: 2),
                        Text(typeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption
                                .copyWith(color: palette.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (fields.isNotEmpty) ...[
                Text('EXTRACTED INFORMATION',
                    style: AppText.label
                        .copyWith(color: palette.textFaint, letterSpacing: 1.0)),
                const SizedBox(height: AppSpacing.xs),
                for (final f in fields)
                  _QuickRow(label: f.label, value: f.value),
              ] else
                Text(
                  'No extracted details for this document.',
                  style: AppText.body.copyWith(color: palette.textSecondary),
                ),
              if (extraction.userNotes.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _QuickRow(label: 'Notes', value: extraction.userNotes.trim()),
              ],
              const SizedBox(height: AppSpacing.lg),
              PressableScale(
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenFull();
                  },
                  child: Container(
                    height: AppSizes.button,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_full_rounded,
                              color: Colors.white, size: 19),
                          SizedBox(width: 8),
                          Text('Open Full Document',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label,
                style: AppText.caption.copyWith(color: palette.textSecondary)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SelectableText(
              value,
              style: AppText.body.copyWith(
                  color: palette.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
