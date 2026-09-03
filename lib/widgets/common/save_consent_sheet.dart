import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';
import '../wallet_modules/module_kit.dart';
import 'ino_options_sheet.dart';

/// The save-consent gate every wallet record passes through.
///
/// Shown just before a record is stored. It tells the user, in plain words,
/// how the data is protected, and only a tap on "I agree" lets the save
/// proceed - which is what the `consent` column on every wallet table records.
/// Dismissing the sheet any other way declines.
///
/// The Password Vault has its own specialised sheet (it adds the nickname
/// warning); every other wallet uses this one.
///
/// [what] names the thing being saved so the copy reads naturally:
/// "this property", "this card", "this document". Pass a localized noun
/// (e.g. `l10n.t('thisProperty')`); when omitted it falls back to
/// `l10n.t('thisRecord')`.
Future<bool> showDataConsentSheet(
  BuildContext context, {
  String? what,
}) async {
  final label = what ?? AppLocalizations.of(context).t('thisRecord');
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: AppPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (_) => _DataConsentSheet(what: label),
  );
  return agreed == true;
}

class _DataConsentSheet extends StatelessWidget {
  const _DataConsentSheet({required this.what});

  final String what;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: InoSheetGrip()),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                 Icon(Icons.verified_user_rounded,
                    size: 20, color: AppColors.primaryGreen),
                const SizedBox(width: 8),
                Text(l10n.t('consentDataStaysYours'),
                    style: AppText.title.copyWith(color: palette.textPrimary)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.t('consentSaveBody').replaceAll('{what}', what),
              style: AppText.body.copyWith(
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: PressableScale(
                    pressedScale: 0.97,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          l10n.t('goBack'),
                          style: AppText.subtitle
                              .copyWith(color: palette.textPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: GradientButton(
                    label: l10n.t('iAgreeSave'),
                    icon: Icons.check_rounded,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
