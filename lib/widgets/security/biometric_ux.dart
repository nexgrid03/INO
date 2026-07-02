import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// Reusable, premium biometric dialogs + snackbars — the Google Password
/// Manager / Samsung Secure Folder feel. Pure UI; no biometric logic lives here,
/// so services and screens share one consistent look.
class BiometricUx {
  BiometricUx._();

  // ---- Snackbars ------------------------------------------------------------

  static void successSnack(BuildContext context, String message) => _snack(
      context, message, AppColors.primaryGreen, Icons.check_circle_rounded);

  static void errorSnack(BuildContext context, String message) =>
      _snack(context, message, AppColors.critical, Icons.error_rounded);

  static void _snack(
      BuildContext context, String message, Color color, IconData icon) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
  }

  // ---- Dialogs --------------------------------------------------------------

  /// "No Biometrics Found" — returns true if the user chose Open Device Settings.
  static Future<bool> noBiometricsDialog(BuildContext context) async {
    final result = await _dialog(
      context,
      icon: Icons.fingerprint_rounded,
      iconColor: AppColors.warning,
      title: 'No Biometrics Found',
      message:
          "You haven't enrolled any fingerprint or face recognition on this device.",
      cancelLabel: 'Cancel',
      confirmLabel: 'Open Device Settings',
    );
    return result ?? false;
  }

  /// "Disable Biometric Authentication?" — returns true if confirmed.
  static Future<bool> disableBiometricDialog(BuildContext context) async {
    final result = await _dialog(
      context,
      icon: Icons.gpp_maybe_rounded,
      iconColor: AppColors.critical,
      title: 'Disable Biometric Authentication?',
      message:
          'You will need to enter your password whenever sensitive actions require verification.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Disable',
      danger: true,
    );
    return result ?? false;
  }

  /// A generic error dialog for hard failures (e.g. permanent lockout).
  static Future<void> errorDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return _dialog(
      context,
      icon: Icons.lock_rounded,
      iconColor: AppColors.critical,
      title: title,
      message: message,
      confirmLabel: 'OK',
    );
  }

  static Future<bool?> _dialog(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String confirmLabel,
    String? cancelLabel,
    bool danger = false,
  }) {
    final palette = AppPalette.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: palette.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.body
                    .copyWith(color: palette.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (cancelLabel != null) ...[
                    Expanded(
                      child: _DialogButton(
                        label: cancelLabel,
                        onTap: () => Navigator.of(context).pop(false),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: _DialogButton(
                      label: confirmLabel,
                      filled: true,
                      danger: danger,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bg = filled
        ? (danger ? AppColors.critical : AppColors.primaryGreen)
        : palette.surfaceVariant;
    final fg = filled ? Colors.white : palette.textPrimary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              label,
              style: AppText.subtitle.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
