import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/expense_models.dart';
import '../../services/expense_store.dart';
import '../../services/tax_summary_pdf.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../utils/share_origin.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/profile/settings_scaffold.dart';

/// ITR Tax Summary for the selected financial year, with a PDF export.
class TaxSummaryScreen extends StatefulWidget {
  const TaxSummaryScreen({super.key});

  @override
  State<TaxSummaryScreen> createState() => _TaxSummaryScreenState();
}

class _TaxSummaryScreenState extends State<TaxSummaryScreen> {
  final _store = ExpenseStore.instance;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    // Hydrate the vault from Supabase (no-op when already loaded / signed out).
    _store.ensureLoaded();
  }

  Future<void> _export(TaxSummary summary) async {
    if (_exporting) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _exporting = true);
    final origin = shareOrigin(context);
    try {
      final file = await TaxSummaryPdf.generate(summary);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'INO Tax Summary - FY ${summary.year.label}',
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.t('couldNotGeneratePdf')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.critical,
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SettingsScaffold(
      title: l10n.t('taxSummary'),
      child: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final s = _store.taxSummary();
          final net = s.totalIncome - s.totalExpenses;
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md,
                AppSpacing.screen, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.internal),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen.withValues(alpha: 0.28),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.t('netIncomeMinusExpenses'),
                          style: AppText.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.9))),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                            '${net < 0 ? '-' : ''}${rupees(net.abs().round())}',
                            style: AppText.bigNumber
                                .copyWith(color: Colors.white)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                          l10n
                              .t('transactionsForYear')
                              .replaceFirst('{n}', '${s.transactionCount}')
                              .replaceFirst('{fy}', s.year.label),
                          style: AppText.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.85))),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                InoCard(
                  radius: AppRadius.card,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.internal,
                      vertical: AppSpacing.xs),
                  child: Column(
                    children: [
                      _line(context, l10n.t('totalIncome'), s.totalIncome,
                          Icons.south_west_rounded,
                          color: AppColors.primaryGreen),
                      _div(palette),
                      _line(context, l10n.t('totalExpenses'), s.totalExpenses,
                          Icons.north_east_rounded),
                      _div(palette),
                      _line(context, l10n.t('totalInvestments'),
                          s.totalInvestments, Icons.trending_up_rounded),
                      _div(palette),
                      _line(context, l10n.t('insurancePremiums'),
                          s.insurancePremiums, Icons.shield_rounded),
                      _div(palette),
                      _line(context, l10n.t('medicalExpenses'),
                          s.medicalExpenses, Icons.favorite_rounded),
                      _div(palette),
                      _line(context, l10n.t('rentPaid'), s.rentPaid,
                          Icons.home_rounded),
                      _div(palette),
                      _line(context, l10n.t('taxPaid'), s.taxPaid,
                          Icons.gavel_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _ExportButton(
                  busy: _exporting,
                  onTap: () => _export(s),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.t('taxSummaryDisclaimer'),
                  style: AppText.caption
                      .copyWith(color: palette.textFaint, height: 1.4),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _div(AppPalette p) => Divider(height: 1, color: p.border);

  Widget _line(BuildContext context, String label, double value, IconData icon,
      {Color? color}) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? palette.textFaint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label,
                style: AppText.body.copyWith(color: palette.textSecondary)),
          ),
          Text(rupees(value.round()),
              style: AppText.subtitle.copyWith(
                  color: color ?? palette.textPrimary,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          height: AppSizes.button,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.button),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.picture_as_pdf_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                          AppLocalizations.of(context)
                              .t('generateTaxSummaryPdf'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
