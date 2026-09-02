import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/expense_models.dart';
import '../../services/expense_store.dart';
import '../../services/tax_summary_pdf.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/ino_scroll_behavior.dart';
import '../../utils/indian_number_format.dart';
import '../../utils/share_origin.dart';
import '../../widgets/common/liquid_glass.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/common/ino_loader.dart';

/// Locks Tax Summary: no scrolling and no overscroll stretch/bounce.
class _TaxSummaryScrollBehavior extends InoScrollBehavior {
  const _TaxSummaryScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const NeverScrollableScrollPhysics();
  }
}

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
    final glass = divineGlassEnabled(context);

    return SettingsScaffold(
      title: l10n.t('taxSummary'),
      child: ScrollConfiguration(
        behavior: const _TaxSummaryScrollBehavior(),
        child: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final s = _store.taxSummary();
            final net = s.totalIncome - s.totalExpenses;
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.sm,
                AppSpacing.screen,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NetHero(net: net, summary: s, glass: glass),
                  const SizedBox(height: AppSpacing.md),
                  AdaptiveGlassCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.internal,
                      vertical: AppSpacing.xs,
                    ),
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
                    textAlign: TextAlign.center,
                    style: AppText.caption
                        .copyWith(color: palette.textFaint, height: 1.4),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _div(AppPalette p) =>
      Divider(height: 1, color: p.border.withValues(alpha: 0.7));

  Widget _line(BuildContext context, String label, double value, IconData icon,
      {Color? color}) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (color ?? palette.textFaint).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: color ?? palette.textFaint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppText.body.copyWith(
                color: palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            rupees(value.round()),
            style: AppText.subtitle.copyWith(
              color: color ?? palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetHero extends StatelessWidget {
  const _NetHero({
    required this.net,
    required this.summary,
    required this.glass,
  });

  final double net;
  final TaxSummary summary;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final amount =
        '${net < 0 ? '-' : ''}${rupees(net.abs().round())}';
    final meta = l10n
        .t('transactionsForYear')
        .replaceFirst('{n}', '${summary.transactionCount}')
        .replaceFirst('{fy}', summary.year.label);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('netIncomeMinusExpenses'),
          style: AppText.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.92),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            amount,
            style: AppText.bigNumber.copyWith(
              color: Colors.white,
              height: 1.05,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          meta,
          style: AppText.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
      ],
    );

    if (!glass) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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
        child: content,
      );
    }

    // Frosted brand plate — glass rim over a soft teal wash (not a solid slab).
    return LiquidGlass(
      borderRadius: BorderRadius.circular(AppRadius.card),
      blur: 22,
      frost: 0.35,
      tint: AppColors.primaryGreen,
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryGreen.withValues(alpha: 0.88),
              AppColors.secondaryGreen.withValues(alpha: 0.82),
            ],
          ),
        ),
        child: content,
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
                color: AppColors.primaryGreen.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: busy
                ? const InoLoader(size: 22, color: Colors.white)
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
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
