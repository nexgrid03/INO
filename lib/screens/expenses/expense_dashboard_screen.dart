import 'package:flutter/material.dart';

import '../../models/expense_models.dart';
import '../../services/expense_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/expenses/expense_widgets.dart';
import '../../widgets/pressable_scale.dart';
import 'add_expense_screen.dart';
import 'tax_records_screen.dart';
import 'tax_summary_screen.dart';
import 'transaction_details_screen.dart';

/// ITR-ready Transaction Vault — records + receipts organised by financial year,
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
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<T?> _push<T>(Widget screen) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

  Future<void> _pickYear() async {
    final palette = AppPalette.of(context);
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
            Text('Financial Year',
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
                          ? const Icon(Icons.check_circle_rounded,
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      floatingActionButton:
          _AddButton(onTap: () => _push(const AddExpenseScreen())),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final fy = _store.selectedYear;
            final all = _store.transactionsForYear(fy);
            final results = _store.searchTransactions(_query, fy);
            final empty = all.isEmpty;
            return Column(
              children: [
                _Header(
                  yearLabel: fy.label,
                  onBack: () => Navigator.of(context).maybePop(),
                  onPickYear: _pickYear,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                      AppSpacing.screen, AppSpacing.sm),
                  child: _SummaryCard(
                    count: _store.countForYear(fy),
                    amount: _store.totalForYear(fy),
                    yearLabel: fy.label,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                      AppSpacing.screen, AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ActionChip(
                          icon: Icons.folder_special_rounded,
                          label: 'Tax Records',
                          onTap: () => _push(const TaxRecordsScreen()),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _ActionChip(
                          icon: Icons.summarize_rounded,
                          label: 'Tax Summary',
                          onTap: () => _push(const TaxSummaryScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!empty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                        AppSpacing.screen, AppSpacing.sm),
                    child: _SearchBar(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                Expanded(
                  child: empty
                      ? _EmptyState(
                          onAdd: () => _push(const AddExpenseScreen()))
                      : _List(
                          results: results,
                          onOpen: (t) =>
                              _push(TransactionDetailsScreen(id: t.id)),
                        ),
                ),
              ],
            );
          },
        ),
      ),
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
    if (results.isEmpty) {
      return Center(
        child: Text('No transactions match your search',
            style: AppText.body.copyWith(color: palette.textSecondary)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 2, 0, 2),
          child: Text('Recent Transactions',
              style: AppText.title.copyWith(color: palette.textPrimary)),
        ),
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, 2, AppSpacing.screen, 100),
            itemCount: results.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: palette.border),
            itemBuilder: (context, i) =>
                TransactionTile(txn: results[i], onTap: () => onOpen(results[i])),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
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
                    color: AppColors.primaryGreen.withValues(alpha: 0.30),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  color: Colors.white, size: 44),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No Transactions Yet',
                style: AppText.headline
                    .copyWith(color: palette.textPrimary, fontSize: 20)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Store your transaction receipts and payment records securely.',
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
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Text('Add First Transaction',
                          style: TextStyle(
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
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.count, required this.amount, required this.yearLabel});

  final int count;
  final double amount;
  final String yearLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(
        children: [
          Expanded(
              child: _stat('Total Transactions', '$count',
                  Icons.receipt_long_rounded)),
          Container(
              width: 1,
              height: 42,
              color: Colors.white.withValues(alpha: 0.25)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: _stat('Total Amount', rupees(amount.round()),
                  Icons.account_balance_wallet_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption
                    .copyWith(color: Colors.white.withValues(alpha: 0.9))),
          ),
        ]),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style:
                  AppText.bigNumber.copyWith(color: Colors.white, fontSize: 24)),
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
    return PressableScale(
      pressedScale: 0.97,
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primaryGreen),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                          color: palette.textPrimary, fontSize: 13.5)),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: palette.textFaint),
              ],
            ),
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
        hintText: 'Search by ID, vendor, amount or date',
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: Colors.white, size: 22),
              SizedBox(width: 6),
              Text('Add Transaction',
                  style: TextStyle(
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

class _Header extends StatelessWidget {
  const _Header({
    required this.yearLabel,
    required this.onBack,
    required this.onPickYear,
  });

  final String yearLabel;
  final VoidCallback onBack;
  final VoidCallback onPickYear;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
          AppSpacing.screen, AppSpacing.md),
      child: Row(
        children: [
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onBack,
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 21, color: palette.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('Transaction Vault',
                style: AppText.headline
                    .copyWith(color: palette.textPrimary, fontSize: 21)),
          ),
          PressableScale(
            pressedScale: 0.95,
            child: Material(
              color: AppColors.primaryGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPickYear,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          size: 16, color: AppColors.darkGreen),
                      const SizedBox(width: 5),
                      Text('FY $yearLabel',
                          style: AppText.subtitle.copyWith(
                              color: AppColors.darkGreen,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          size: 18, color: AppColors.darkGreen),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
