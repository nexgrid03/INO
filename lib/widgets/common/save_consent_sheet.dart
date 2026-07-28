import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';
import '../wallet_modules/module_kit.dart';

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
/// "this property", "this card", "this document".
Future<bool> showDataConsentSheet(
  BuildContext context, {
  String what = 'this record',
}) async {
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DataConsentSheet(what: what),
  );
  return agreed == true;
}

class _DataConsentSheet extends StatelessWidget {
  const _DataConsentSheet({required this.what});

  final String what;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
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
                const Icon(Icons.verified_user_rounded,
                    size: 20, color: AppColors.primaryGreen),
                const SizedBox(width: 8),
                Text('Your data stays yours',
                    style: AppText.title.copyWith(color: palette.textPrimary)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Before we save $what: it is stored in your private INO vault, '
              'locked to your signed-in account - no other user can read it, '
              'and it is never shared unless you explicitly share it yourself.'
              '\n\nSave $what to your vault?',
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
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          'Go back',
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
                    label: 'I agree · save',
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
