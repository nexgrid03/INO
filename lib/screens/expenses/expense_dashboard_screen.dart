import 'package:flutter/material.dart';

import '../../core/responsive/responsive_metric_text.dart';
import '../../l10n/app_localizations.dart';
import '../../models/expense_models.dart';
import '../../services/expense_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/common/liquid_glass.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/expenses/expense_widgets.dart';
import '../../widgets/pressable_scale.dart';
import 'add_expense_screen.dart';
import 'tax_records_screen.dart';
import 'tax_summary_screen.dart';
import 'transaction_details_screen.dart';

/// ITR-ready Transaction Vault - records + receipts organised by financial year,
/// with a tax-document vault and a tax summary. Starts completely empty.
class ExpenseDashboardScreen extends StatefulWidget {
  const ExpenseDashboardScreen({super.key});

  @override
  State<ExpenseDashboardScreen> createState() => _ExpenseDashboardScreenState();
}

class _ExpenseDashboardScreenState extends State<ExpenseDashboardScreen> {
  final _store = ExpenseStore.instance;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Hydrate the vault from Supabase (no-op when already loaded / signed out).
    _store.ensureLoaded();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<T?> _push<T>(Widget screen) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

  Future<void> _pickYear() async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final base = FinancialYear.current().startYear;
    final years = <int>{
      for (var i = 0; i < 7; i++) base - i,
      for (final y in _store.availableYears) y.startYear,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill))),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.t('financialYear'),
                style: AppText.title.copyWith(color: palette.textPrimary)),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  for (final y in years)
                    ListTile(
                      onTap: () => Navigator.of(context).pop(y),
                      leading: Icon(Icons.calendar_month_rounded,
                          color: y == _store.selectedYear.startYear
                              ? AppColors.primaryGreen
                              : palette.textFaint),
                      title: Text('FY ${FinancialYear(y).label}',
                          style: AppText.subtitle.copyWith(
                              color: palette.textPrimary,
                              fontWeight: y == _store.selectedYear.startYear
                                  ? FontWeight.w800
                                  : FontWeight.w600)),
                      trailing: y == _store.selectedYear.startYear
                          ?  Icon(Icons.check_circle_rounded,
                              color: AppColors.primaryGreen)
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) _store.setSelectedYear(FinancialYear(picked));
  }

  Widget _header(AppPalette palette, String yearLabel) {
    final l10n = AppLocalizations.of(context);
    final glass = divineGlassEnabled(context);
    final yearChip = PressableScale(
      pressedScale: 0.95,
      child: glass
          ? GestureDetector(
              onTap: _pickYear,
              behavior: HitTestBehavior.opaque,
              child: LiquidGlass(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                blur: 12,
                frost: 0.95,
                shadow: false,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      yearLabel,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded,
                        size: 18, color: palette.textSecondary),
                  ],
                ),
              ),
            )
          : Material(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: InkWell(
                onTap: _pickYear,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        yearLabel,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded,
                          size: 18, color: palette.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
    );

    if (glass) {
      return DivineGlassAppBar(
        title: l10n.t('transactionVault'),
        onBack: () => Navigator.of(context).maybePop(),
        trailing: yearChip,
        centerTitle: false,
        includeStatusBar: true,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md,
        AppSpacing.screen,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          InoBackButton(onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.t('transactionVault'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.headline.copyWith(
                color: palette.textPrimary,
                fontSize: 22,
              ),
            ),
          ),
          yearChip,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final glass = divineGlassEnabled(context);
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final fy = _store.selectedYear;
        final all = _store.transactionsForYear(fy);
        final results = _store.searchTransactions(_query, fy);
        final empty = all.isEmpty;
        final loading = _store.isLoading && !_store.isLoaded;
        final failed = _store.loadError != null && _store.isEmpty;

        final monthlyData = List.generate(12, (index) {
          final month = (index + 3) % 12 + 1; // index 0 -> 4 (Apr), index 11 -> 3 (Mar)
          final year = month >= 4 ? fy.startYear : fy.startYear + 1;
          final txns = all.where((t) => t.dateTime.month == month && t.dateTime.year == year);
          final credited = txns.where((t) => t.isCredited).fold(0.0, (sum, t) => sum + t.amount);
          final debited = txns.where((t) => !t.isCredited).fold(0.0, (sum, t) => sum + t.amount);
          return (
            month: month,
            year: year,
            credited: credited,
            debited: debited,
            total: debited - credited,
            count: txns.length,
          );
        });

        return Scaffold(
          backgroundColor: palette.bg,
          floatingActionButton: empty
              ? null
              : _AddButton(onTap: () => _push(const AddExpenseScreen())),
          body: InoBackground(
            sky: glass,
            child: SafeArea(
              top: !glass,
              child: Column(
                children: [
                  _header(palette, fy.label),
                  const SizedBox(height: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                        AppSpacing.screen, AppSpacing.sm),
                    child: _SummaryCard(
                      count: _store.countForYear(fy),
                      amount: _store.totalForYear(fy),
                      credited: _store.creditedForYear(fy),
                      debited: _store.debitedForYear(fy),
                      yearLabel: fy.label,
                    ),
                  ),
                  if (!loading && !failed && !empty) ...[
                    _MonthlyBreakdown(monthlyData: monthlyData),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                        AppSpacing.screen, AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ActionChip(
                            icon: Icons.folder_special_rounded,
                            label: l10n.t('taxRecords'),
                            onTap: () => _push(const TaxRecordsScreen()),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _ActionChip(
                            icon: Icons.summarize_rounded,
                            label: l10n.t('taxSummary'),
                            onTap: () => _push(const TaxSummaryScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!loading && !failed && !empty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                          AppSpacing.screen, AppSpacing.sm),
                      child: _SearchBar(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            color: AppColors.primaryGreen,
                            onRefresh: _store.reload,
                            child: failed
                                ? _ErrorState(
                                    message: _store.loadError!,
                                    onRetry: _store.reload,
                                  )
                                : empty
                                    ? _EmptyState(
                                        onAdd: () =>
                                            _push(const AddExpenseScreen()))
                                    : _List(
                                        results: results,
                                        onOpen: (t) => _push(
                                            TransactionDetailsScreen(
                                                id: t.id)),
                                      ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.results, required this.onOpen});

  final List<TransactionRecord> results;
  final void Function(TransactionRecord) onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    if (results.isEmpty) {
      return Center(
        child: Text(l10n.t('noTransactionsMatch'),
            style: AppText.body.copyWith(color: palette.textSecondary)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 2, 0, 2),
          child: Text(l10n.t('recentTransactions'),
              style: AppText.title.copyWith(color: palette.textPrimary)),
        ),
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, 2, AppSpacing.screen, 100),
            itemCount: results.length,
            separatorBuilder: (_, _) =>
                Divider(height: AppSpacing.md, color: palette.border),
            itemBuilder: (context, i) =>
                TransactionTile(txn: results[i], onTap: () => onOpen(results[i])),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 56, color: palette.textFaint),
                  const SizedBox(height: AppSpacing.md),
                  Text(l10n.t('couldntLoadTransactions'),
                      style:
                          AppText.title.copyWith(color: palette.textPrimary)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppText.body
                        .copyWith(color: palette.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PressableScale(
                    child: GestureDetector(
                      onTap: onRetry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius:
                              BorderRadius.circular(AppRadius.button),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh_rounded,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(l10n.t('tryAgain'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // Always scrollable so pull-to-refresh works on the empty state too.
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(AppRadius.large + 6),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.primaryGreen.withValues(alpha: 0.30),
                          blurRadius: 26,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: Colors.white, size: 44),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(l10n.t('noTransactionsYet'),
                      style: AppText.headline
                          .copyWith(color: palette.textPrimary, fontSize: 20)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.t('noTransactionsYetSubtitle'),
                    textAlign: TextAlign.center,
                    style: AppText.body
                        .copyWith(color: palette.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PressableScale(
                    child: GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm + 2),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryGreen
                                  .withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 6),
                            Text(l10n.t('addFirstTransaction'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.count,
    required this.amount,
    required this.credited,
    required this.debited,
    required this.yearLabel,
  });

  final int count;
  final double amount;
  final double credited;
  final double debited;
  final String yearLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return AdaptiveGlassCard(
      padding: const EdgeInsets.all(AppSpacing.internal),
      radius: AppRadius.large,
      child: Column(
        children: [
          Text(
            l10n.t('totalAmount'),
            style: AppText.caption.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ResponsiveMetricText(
            rupees(amount.round()),
            textAlign: TextAlign.center,
            style: AppText.bigNumber
                .copyWith(color: palette.textPrimary, fontSize: 32),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                 Icon(Icons.receipt_long_rounded,
                    size: 13, color: AppColors.primaryGreen),
                const SizedBox(width: 5),
                Text(
                  '$count · ${l10n.t('totalTransactions')} · FY $yearLabel',
                  style: AppText.label.copyWith(
                      color: AppColors.primaryGreen, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: palette.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.chip + 2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _stat(
                    context,
                    l10n.t('totalCredited'),
                    rupees(credited.round()),
                    Icons.south_west_rounded,
                    AppColors.positive,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Container(width: 1, height: 34, color: palette.border),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _stat(
                    context,
                    l10n.t('totalDebited'),
                    rupees(debited.round()),
                    Icons.north_east_rounded,
                    AppColors.negative,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value, IconData icon,
      Color accent) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 5),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(
                    color: palette.textSecondary, fontSize: 11.5)),
          ),
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: AppText.title
                  .copyWith(color: palette.textPrimary, fontSize: 17)),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final launcher = divineGlassEnabled(context);
    final content = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: AppColors.primaryGreen),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.subtitle
                .copyWith(color: palette.textPrimary, fontSize: 13.5),
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 18, color: palette.textFaint),
      ],
    );
    return PressableScale(
      pressedScale: 0.97,
      child: launcher
          ? GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: LiquidGlass(
                borderRadius: BorderRadius.circular(AppRadius.chip + 2),
                blur: 14,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(height: 52, child: content),
              ),
            )
          : Material(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.chip + 2),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.chip + 2),
                    border: Border.all(color: palette.border),
                  ),
                  child: content,
                ),
              ),
            ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: c),
        );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppText.body.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).t('searchTxnHint'),
        hintStyle: AppText.body.copyWith(color: palette.textFaint),
        prefixIcon: Icon(Icons.search_rounded, color: palette.textFaint),
        filled: true,
        fillColor: palette.surface,
        border: border(palette.border),
        enabledBorder: border(palette.border),
        focusedBorder: border(AppColors.primaryGreen),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 6),
              Text(AppLocalizations.of(context).t('addTransaction'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyBreakdown extends StatelessWidget {
  const _MonthlyBreakdown({required this.monthlyData});

  final List<({
    int month,
    int year,
    double credited,
    double debited,
    double total,
    int count,
  })> monthlyData;

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xs),
          child: Text(
            l10n.t('monthlyTracking'),
            style: AppText.title.copyWith(color: palette.textPrimary, fontSize: 16),
          ),
        ),
        SizedBox(
          height: 108,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen - 4),
            itemCount: monthlyData.length,
            itemBuilder: (context, index) {
              final data = monthlyData[index];
              final hasTxns = data.count > 0;
              final monthLabel = _monthNames[data.month - 1];
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: AdaptiveGlassCard(
                  padding: const EdgeInsets.all(12),
                  radius: AppRadius.card,
                  child: SizedBox(
                    width: 104,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              monthLabel,
                              style: AppText.label.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            if (hasTxns)
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          hasTxns ? rupees(data.debited.round()) : '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle.copyWith(
                            color: hasTxns ? AppColors.negative : palette.textFaint,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasTxns ? '+${rupees(data.credited.round())}' : 'No activity',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: hasTxns ? AppColors.positive : palette.textFaint,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

