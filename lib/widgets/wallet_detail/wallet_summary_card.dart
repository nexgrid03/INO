import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';

/// Section 3 — the compact Wallet Summary Card (≈150dp).
///
/// One glance, four facts: how many documents, how many are expiring, that the
/// vault is protected, and when it last changed — plus a single "View Vault"
/// affordance. Deliberately *not* a storage dashboard; analytics live in
/// Wallet Settings. Reads from live counts so it stays in sync as the user
/// favorites / archives / deletes.
class WalletSummaryCard extends StatelessWidget {
  const WalletSummaryCard({
    super.key,
    required this.totalDocuments,
    required this.expiring,
    required this.protected,
  });

  final int totalDocuments;
  final int expiring;
  final bool protected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return InoCard(
      radius: AppRadius.large,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Stat(
              value: '$totalDocuments',
              label: l10n.t('documents'),
              color: palette.textPrimary,
            ),
          ),
          _Divider(palette: palette),
          Expanded(
            child: _Stat(
              value: '$expiring',
              label: l10n.t('expiring'),
              color: expiring > 0 ? AppColors.warning : palette.textPrimary,
            ),
          ),
          _Divider(palette: palette),
          Expanded(
            child: _ProtectedStat(protected: protected),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// The "✓ Protected" assurance, standing in for the removed security dashboard.
class _ProtectedStat extends StatelessWidget {
  const _ProtectedStat({required this.protected});

  final bool protected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color =
        protected ? AppColors.primaryGreen : palette.textFaint;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          protected
              ? Icons.verified_user_rounded
              : Icons.gpp_maybe_rounded,
          size: 24,
          color: color,
        ),
        const SizedBox(height: 4),
        Text(
          protected
              ? AppLocalizations.of(context).t('protected')
              : AppLocalizations.of(context).t('atRisk'),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: palette.border,
    );
  }
}

