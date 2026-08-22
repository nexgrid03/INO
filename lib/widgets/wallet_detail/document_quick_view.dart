import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/wallet_detail_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/shiny_icon.dart';
import '../divine_glass/divine_glass.dart';
import '../pressable_scale.dart';
import 'document_card.dart' show documentCardAccent;

/// Quick View - a peek at a document's key details (name, type, and the
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
  bool isHealth = false,
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
      isHealth: isHealth,
    ),
  );
}

class _QuickViewSheet extends StatelessWidget {
  const _QuickViewSheet({
    required this.record,
    required this.accent,
    required this.onOpenFull,
    this.isHealth = false,
  });

  final DocumentRecord record;
  final List<Color> accent;
  final VoidCallback onOpenFull;
  final bool isHealth;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final extraction = record.extraction;
    final iconAccent =
        documentCardAccent(record, walletAccent: accent.first);
    final List<({String label, String value})> fields;
    final String typeLabel;
    if (isHealth) {
      fields = [
        (label: l10n.t('hospitalName'), value: record.name),
        (label: l10n.t('documentType'), value: record.category),
        if (record.doctorName != null && record.doctorName!.trim().isNotEmpty)
          (label: l10n.t('doctorName'), value: record.doctorName!),
        if (record.expiresAt != null)
          (
            label: l10n.t('nextAppointmentDate'),
            value: inoFormatDate(record.expiresAt!)
          ),
      ];
      typeLabel = record.category;
    } else {
      fields = extraction.displayFields();
      typeLabel = extraction.typeLabel ?? record.category;
    }

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
                  // Same chrome as DivineGlassDocumentCard / classic DocumentCard
                  // — soft round disc under Divine Glass (no accent ring), glossy
                  // chip in classic.
                  divineGlassEnabled(context)
                      ? DivineGlassRoundIcon(
                          icon: record.icon,
                          accent: iconAccent,
                          size: 48,
                          iconSize: 20,
                        )
                      : ShinyIcon(
                          icon: record.icon,
                          color: iconAccent,
                          size: 48,
                          iconSize: 24,
                          radius: 14,
                          style: ShinyIconStyle.filled,
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
              if (fields.isNotEmpty || isHealth) ...[
                Text(
                    (isHealth
                            ? l10n.t('healthDetails')
                            : l10n.t('extractedInformation'))
                        .toUpperCase(),
                    style: AppText.label
                        .copyWith(color: palette.textFaint, letterSpacing: 1.0)),
                const SizedBox(height: AppSpacing.xs),
                for (final f in fields)
                  _QuickRow(label: f.label, value: f.value, copyable: true),
              ] else
                Text(
                  l10n.t('noExtractedDetails'),
                  style: AppText.body.copyWith(color: palette.textSecondary),
                ),
              if (extraction.userNotes.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _QuickRow(
                    label: l10n.t('notes'),
                    value: extraction.userNotes.trim()),
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
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_full_rounded,
                              color: Colors.white, size: 19),
                          const SizedBox(width: 8),
                          Text(l10n.t('openFullDocument'),
                              style: const TextStyle(
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
  const _QuickRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

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
          if (copyable)
            InkResponse(
              radius: 18,
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                HapticFeedback.selectionClick();
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.primaryGreen,
                    content: Text(AppLocalizations.of(context)
                        .t('copiedLabel')
                        .replaceAll('{label}', label)),
                  ));
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 1),
                child:
                    Icon(Icons.copy_rounded, size: 16, color: palette.textFaint),
              ),
            ),
        ],
      ),
    );
  }
}
