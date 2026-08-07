import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/payment_qr.dart';
import '../../services/upi_app_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Bottom sheet shown after a **payment** QR is scanned: what is being paid, to
/// whom, and which installed app should handle it.
///
/// INO deliberately does not process the payment itself. It reads the QR,
/// confirms the payee back to the user, and hands a canonical `upi://pay` URI to
/// the app they choose - the amount, PIN and the actual transfer all happen
/// inside that app, where they belong.
Future<void> showPaymentAppSheet(
  BuildContext context,
  PaymentRequest request,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaymentAppSheet(request: request),
  );
}

class _PaymentAppSheet extends StatefulWidget {
  const _PaymentAppSheet({required this.request});

  final PaymentRequest request;

  @override
  State<_PaymentAppSheet> createState() => _PaymentAppSheetState();
}

class _PaymentAppSheetState extends State<_PaymentAppSheet> {
  List<UpiApp>? _apps;
  bool _launching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await UpiAppService.instance.installedApps();
    if (!mounted) return;
    setState(() => _apps = apps);
  }

  Future<void> _pay(UpiApp app) async {
    if (_launching) return;
    setState(() => _launching = true);
    final ok = await UpiAppService.instance.pay(app, widget.request.uri);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    // The chosen app refused to start - fall back to the OS rather than
    // leaving the user staring at a dead sheet.
    final fallback =
        await UpiAppService.instance.payWithSystemChooser(widget.request.uri);
    if (!mounted) return;
    setState(() => _launching = false);
    if (fallback) {
      Navigator.of(context).pop();
    } else {
      _toast(AppLocalizations.of(context).t('couldNotOpenPaymentApp'));
    }
  }

  Future<void> _payWithOther() async {
    if (_launching) return;
    setState(() => _launching = true);
    final ok =
        await UpiAppService.instance.payWithSystemChooser(widget.request.uri);
    if (!mounted) return;
    setState(() => _launching = false);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      _toast(AppLocalizations.of(context).t('couldNotOpenPaymentApp'));
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.critical,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final apps = _apps;

    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: palette.border),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _PayeeCard(request: widget.request),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.t('payUsing').toUpperCase(),
                style: AppText.label.copyWith(
                  color: palette.textFaint,
                  letterSpacing: 1.0,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (apps == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (apps.isEmpty)
                _NoAppsFound(onOther: _payWithOther)
              else
                _AppGrid(apps: apps, busy: _launching, onTap: _pay),
              if (apps != null && apps.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: PressableScale(
                    child: GestureDetector(
                      onTap: _launching ? null : _payWithOther,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: Text(
                          l10n.t('useAnotherApp'),
                          style: AppText.subtitle.copyWith(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.t('paymentHandedOffNote'),
                textAlign: TextAlign.center,
                style: AppText.caption
                    .copyWith(color: palette.textFaint, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who is being paid, and how much. Shown before any app is opened so the user
/// can check the payee against the QR they just scanned.
class _PayeeCard extends StatelessWidget {
  const _PayeeCard({required this.request});

  final PaymentRequest request;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final amount = request.amount;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(shape: BoxShape.circle)
                .copyWith(color: AppColors.tealMist),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: AppColors.primaryGreen, size: 22),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            request.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.subtitle.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            request.payeeAddress,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: palette.textFaint),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (amount != null)
            Text(
              '₹$amount',
              style: AppText.title.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 26,
              ),
            )
          else
            Text(
              l10n.t('amountEnteredInApp'),
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          if (request.note != null) ...[
            const SizedBox(height: 4),
            Text(
              request.note!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppGrid extends StatelessWidget {
  const _AppGrid({required this.apps, required this.busy, required this.onTap});

  final List<UpiApp> apps;
  final bool busy;
  final ValueChanged<UpiApp> onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.5 : 1,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        alignment: WrapAlignment.center,
        children: [
          for (final app in apps)
            SizedBox(
              width: 82,
              child: _AppTile(
                app: app,
                onTap: busy ? null : () => onTap(app),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.onTap});

  final UpiApp app;
  final VoidCallback? onTap;

  /// First letter of the app's name, for the iOS fallback avatar.
  static String _initial(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final icon = app.icon;
    return PressableScale(
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: icon != null
                  // Android hands back the app's real launcher icon.
                  ? Image.memory(icon, fit: BoxFit.cover, gaplessPlayback: true)
                  // iOS cannot expose another app's icon - use its initial.
                  : Center(
                      child: Text(
                        _initial(app.name),
                        style: AppText.title.copyWith(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              app.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                color: palette.textSecondary,
                fontSize: 11.5,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when no UPI app could be discovered. The OS handoff is still offered -
/// on iOS discovery is limited by design, so "none found" does not mean "none
/// installed".
class _NoAppsFound extends StatelessWidget {
  const _NoAppsFound({required this.onOther});

  final VoidCallback onOther;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border:
                Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.t('noPaymentAppsFound'),
                  style: AppText.caption
                      .copyWith(color: palette.textSecondary, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: AppSizes.button,
          child: FilledButton(
            onPressed: onOther,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            child: Text(
              l10n.t('openWithAnyApp'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
