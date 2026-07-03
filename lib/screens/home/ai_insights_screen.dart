import 'package:flutter/material.dart';

import '../../data/reminder_store.dart';
import '../../repositories/document_repository.dart';
import '../../services/app_settings.dart';
import '../../services/biometric_service.dart';
import '../../services/net_worth_service.dart';
import '../../services/storage_stats_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../networth/net_worth_analytics_screen.dart';
import '../shell/shell_controller.dart';

class _Insight {
  const _Insight({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// AI Insights — actionable observations computed from the user's real signals
/// (due reminders, expiring documents, backup / security posture, storage) plus
/// portfolio suggestions from the net-worth model. Not a black box: each card
/// explains itself and offers a concrete next step.
class AiInsightsScreen extends StatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  State<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends State<AiInsightsScreen> {
  List<_Insight>? _insights;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  void _goTab(int i) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    ShellController.tab.value = i;
  }

  Future<void> _compute() async {
    final list = <_Insight>[];

    // Reminders needing attention.
    try {
      await ReminderStore.instance.ensureLoaded();
      final today = ReminderStore.instance.today;
      final due =
          ReminderStore.instance.active.where((r) => r.daysFrom(today) <= 7).length;
      if (due > 0) {
        list.add(_Insight(
          icon: Icons.alarm_rounded,
          color: AppColors.warning,
          title: '$due item${due == 1 ? '' : 's'} need attention this week',
          message:
              'You have $due reminder${due == 1 ? '' : 's'} due within 7 days. '
              'Review them so nothing lapses.',
          actionLabel: 'Open reminders',
          onAction: () => _goTab(3),
        ));
      }
    } catch (_) {}

    // Expiring documents.
    try {
      final docs = await DocumentRepository.instance.listAll();
      final expiring = docs.where((d) {
        final e = d.expiresAt;
        if (e == null) return false;
        final days = e.difference(DateTime.now()).inDays;
        return days >= 0 && days <= 30;
      }).length;
      if (expiring > 0) {
        list.add(_Insight(
          icon: Icons.event_busy_rounded,
          color: AppColors.critical,
          title: '$expiring document${expiring == 1 ? '' : 's'} expiring soon',
          message:
              'Renew or replace them before they expire to stay covered.',
          actionLabel: 'View wallet',
          onAction: () => _goTab(1),
        ));
      }
    } catch (_) {}

    // Backup health.
    final lastBackup = AppSettings.instance.lastBackupAt.value;
    if (lastBackup == null) {
      list.add(_Insight(
        icon: Icons.cloud_off_rounded,
        color: AppColors.lightBlue,
        title: 'Protect your data with a backup',
        message:
            'You haven’t backed up yet. A cloud backup keeps your documents safe '
            'if you lose your device.',
        actionLabel: 'Go to Profile',
        onAction: () => _goTab(4),
      ));
    }

    // Security posture.
    if (!BiometricService.instance.lockEnabled.value) {
      list.add(_Insight(
        icon: Icons.fingerprint_rounded,
        color: AppColors.primaryGreen,
        title: 'Add a biometric lock',
        message:
            'Your vault holds sensitive documents. A Face ID / fingerprint lock '
            'adds strong, effortless protection.',
        actionLabel: 'Enable in Profile',
        onAction: () => _goTab(4),
      ));
    }

    // Storage tip (real usage).
    try {
      final usage = await StorageStatsService.instance.load();
      if (usage.fileCount > 0) {
        list.add(_Insight(
          icon: Icons.pie_chart_rounded,
          color: AppColors.secondaryGreen,
          title: 'Storage in good shape',
          message:
              'You’re using ${usage.usedLabel} across ${usage.fileCount} file'
              '${usage.fileCount == 1 ? '' : 's'} — well within your quota.',
        ));
      }
    } catch (_) {}

    // Portfolio suggestions (from the net-worth model).
    final data = NetWorthService.instance.data;
    final top = data.allocations.reduce((a, b) => a.value >= b.value ? a : b);
    final share = data.total == 0 ? 0.0 : top.value / data.total;
    if (share > 0.4) {
      list.add(_Insight(
        icon: Icons.balance_rounded,
        color: const Color(0xFF8B6CEF),
        title: 'Your portfolio leans on ${top.label}',
        message:
            '${top.label} is ${(share * 100).round()}% of your net worth. '
            'Diversifying can reduce concentration risk.',
        actionLabel: 'View net worth',
        onAction: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const NetWorthAnalyticsScreen())),
      ));
    }
    list.add(_Insight(
      icon: Icons.trending_up_rounded,
      color: AppColors.primaryGreen,
      title: 'Net worth is trending up',
      message:
          'Your wealth grew ${data.growthPercent.toStringAsFixed(1)}% '
          '(${formatInr(data.growthAmount)}) this month. Keep it going.',
    ));

    if (!mounted) return;
    setState(() => _insights = list);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final insights = _insights;
    return SettingsScaffold(
      title: 'AI Insights',
      child: insights == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                  AppSpacing.md, AppSpacing.screen, AppSpacing.xl),
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Personalised from your documents, reminders and portfolio.',
                        style: AppText.caption.copyWith(
                            color: palette.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final i in insights) ...[
                  _InsightCard(insight: i),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});
  final _Insight insight;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: insight.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(insight.icon, color: insight.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(insight.title,
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary)),
                    const SizedBox(height: 4),
                    Text(insight.message,
                        style: AppText.body.copyWith(
                            color: palette.textSecondary, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
          if (insight.actionLabel != null && insight.onAction != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: insight.onAction,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(insight.actionLabel!,
                        style: TextStyle(
                            color: insight.color,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    Icon(Icons.arrow_forward_rounded,
                        size: 15, color: insight.color),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
