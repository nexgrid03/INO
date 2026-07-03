import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../services/net_worth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/home/empty_state.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../documents/add_document_screen.dart';
import '../networth/net_worth_analytics_screen.dart';

/// Assets — the total asset value, a searchable breakdown by class (from the
/// [NetWorthService] allocation model) and a real "Add asset" entry point that
/// opens the add-document flow.
class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final _query = TextEditingController();
  String _term = '';

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      final t = _query.text.trim().toLowerCase();
      if (t != _term) setState(() => _term = t);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _addAsset() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddDocumentScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final service = NetWorthService.instance;
    final total = service.total;
    final all = service.allocations;
    final filtered = _term.isEmpty
        ? all
        : all.where((a) => a.label.toLowerCase().contains(_term)).toList();

    return SettingsScaffold(
      title: 'Assets',
      actions: [
        IconButton(
          tooltip: 'Add asset',
          icon: Icon(Icons.add_rounded, color: palette.textPrimary),
          onPressed: _addAsset,
        ),
      ],
      child: Column(
        children: [
          // Total header.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, AppSpacing.xs, AppSpacing.screen, 0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NetWorthAnalyticsScreen())),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total assets',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(formatInr(total),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('${all.length} asset classes',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        const Spacer(),
                        const Text('View analytics',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        const Icon(Icons.chevron_right_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Search.
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            child: TextField(
              controller: _query,
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search assets…',
                hintStyle: TextStyle(color: palette.textFaint),
                prefixIcon:
                    Icon(Icons.search_rounded, color: palette.textSecondary),
                filled: true,
                fillColor: palette.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  borderSide: const BorderSide(
                      color: AppColors.primaryGreen, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2_rounded,
                    title: 'No matching assets',
                    message: 'Try a different search, or add a new asset.',
                    actionLabel: 'Add asset',
                    onAction: _addAsset,
                    compact: true,
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                        AppSpacing.xs, AppSpacing.screen, AppSpacing.xl),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) =>
                        _AssetTile(allocation: filtered[i], total: total),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.allocation, required this.total});

  final AssetAllocation allocation;
  final double total;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final pct = total == 0 ? 0.0 : allocation.value / total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: allocation.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconFor(allocation.label),
                    color: allocation.color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(allocation.label,
                    style:
                        AppText.subtitle.copyWith(color: palette.textPrimary)),
              ),
              Text(formatInr(allocation.value),
                  style: AppText.subtitle.copyWith(color: palette.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: palette.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation(allocation.color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${(pct * 100).toStringAsFixed(0)}%',
                  style: AppText.caption.copyWith(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String label) {
    switch (label) {
      case 'Investments':
        return Icons.trending_up_rounded;
      case 'Property':
        return Icons.home_work_rounded;
      case 'Bank & Cash':
        return Icons.account_balance_rounded;
      case 'Gold':
        return Icons.workspace_premium_rounded;
      case 'Digital Assets':
        return Icons.currency_bitcoin_rounded;
      default:
        return Icons.savings_rounded;
    }
  }
}
