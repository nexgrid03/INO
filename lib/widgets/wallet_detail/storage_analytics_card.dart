import 'package:flutter/material.dart';

import '../../models/wallet_detail_models.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../dashboard/section_header.dart';

/// Section 9 — Storage Analytics.
///
/// A clean analytics card: total files, used vs available storage on a modern
/// progress bar, plus a small monthly-uploads mini bar chart.
class StorageAnalyticsCard extends StatelessWidget {
  const StorageAnalyticsCard({super.key, required this.storage});

  final StorageAnalytics storage;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Storage Analytics',
          subtitle: 'Files & space usage',
          icon: Icons.donut_small_rounded,
        ),
        InoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Metric(
                    value: '${storage.totalFiles}',
                    label: 'Total files',
                    color: AppColors.primaryGreen,
                  ),
                  _divider(palette),
                  _Metric(
                    value: storage.usedLabel,
                    label: 'Used',
                    color: AppColors.lightBlue,
                  ),
                  _divider(palette),
                  _Metric(
                    value: '${storage.monthlyUploads}',
                    label: 'This month',
                    color: AppColors.secondaryGreen,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text('Storage',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: palette.textSecondary)),
                  const Spacer(),
                  Text(
                    '${storage.usedLabel} · ${storage.availableLabel} free',
                    style: TextStyle(fontSize: 12, color: palette.textFaint),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: storage.usedFraction.clamp(0.0, 1.0),
                  minHeight: 9,
                  backgroundColor: palette.surfaceVariant,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primaryGreen),
                ),
              ),
              const SizedBox(height: 18),
              Text('Monthly uploads',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary)),
              const SizedBox(height: 10),
              _MiniBars(values: storage.monthly),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider(AppPalette palette) => Container(
        width: 1,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: palette.border,
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 12 + (values[i] / maxV) * 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.lightBlue, AppColors.primaryGreen],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            if (i != values.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
