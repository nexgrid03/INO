import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// One-time consent before INO hands a scanned payment QR to an external
/// payment app.
///
/// **Why this is a prompt and not just a tap.** Opening a payment app is the
/// point where the payee's VPA leaves INO and the transaction moves somewhere
/// INO can neither see nor undo. Users should agree to that boundary knowingly
/// once, rather than discover it the first time an app suddenly takes over the
/// screen mid-scan.
///
/// It is asked **once per device** and then remembered
/// (`AppSettings.paymentAppConsent`), so paying stays a single tap afterwards.
/// The sheet that calls this always shows the payee first, so this dialog is
/// about the hand-off itself, not about confirming the amount.
///
/// Returns true when the user allows the hand-off.
Future<bool> showPaymentAppConsentDialog(
  BuildContext context,
  String appLabel,
) async {
  final l10n = AppLocalizations.of(context);
  final palette = AppPalette.of(context);

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      icon: Container(
        width: AppSizes.iconContainer,
        height: AppSizes.iconContainer,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: const Icon(
          Icons.account_balance_wallet_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
      title: Text(
        l10n.t('paymentConsentTitle'),
        textAlign: TextAlign.center,
        style: AppText.headline.copyWith(color: palette.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.t('paymentConsentBody').replaceFirst('{app}', appLabel),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.t('paymentConsentNote'),
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: palette.textFaint),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            l10n.t('cancel'),
            style: AppText.label.copyWith(color: palette.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
          ),
          child: Text(l10n.t('paymentConsentAllow')),
        ),
      ],
    ),
  );

  // A dismissed dialog (tap outside / back) is a "no", never an implicit yes.
  return result ?? false;
}
