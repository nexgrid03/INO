import 'package:flutter/material.dart';

import '../../../models/dashboard_models.dart';
import '../../../theme/app_theme.dart';
import '../ino_card.dart';
import '../section_header.dart';

/// Sections 8, 9 & 10 — Property, Health and Insurance snapshots.
///
/// Each is a compact "overview" card built from a shared [_StatCell] grid so
/// the three read as a consistent family. Kept in one file because they share
/// the same internal layout primitives.

String _fmtCurrency(double v) {
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
  return '₹${v.toStringAsFixed(0)}';
}

// ---------------------------------------------------------------------------

class PropertySection extends StatelessWidget {
  const PropertySection({super.key, required this.summary});

  final PropertySummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Property',
          subtitle: 'Your real-estate portfolio',
          actionLabel: 'Manage',
          icon: Icons.home_work_rounded,
        ),
        InoCard(
          onTap: () {},
          child: Column(
            children: [
              Row(
                children: [
                  _StatCell(
                    icon: Icons.home_work_rounded,
                    color: AppColors.lightBlue,
                    value: '${summary.totalProperties}',
                    label: 'Properties',
                  ),
                  _divider(palette),
                  _StatCell(
                    icon: Icons.account_balance_wallet_rounded,
                    color: AppColors.primaryGreen,
                    value: _fmtCurrency(summary.portfolioValue),
                    label: 'Portfolio value',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FootNote(
                icon: Icons.verified_user_rounded,
                text: summary.ownership,
              ),
              _FootNote(
                icon: Icons.update_rounded,
                text: summary.recentUpdate,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class HealthSection extends StatelessWidget {
  const HealthSection({super.key, required this.summary});

  final HealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Health',
          subtitle: 'Records & reminders',
          actionLabel: 'View',
          icon: Icons.favorite_rounded,
        ),
        InoCard(
          onTap: () {},
          child: Column(
            children: [
              Row(
                children: [
                  _StatCell(
                    icon: Icons.bloodtype_rounded,
                    color: const Color(0xFF3B82F6),
                    value: summary.bloodGroup,
                    label: 'Blood group',
                  ),
                  _divider(palette),
                  _StatCell(
                    icon: Icons.folder_rounded,
                    color: AppColors.lightBlue,
                    value: '${summary.recordsCount}',
                    label: 'Records',
                  ),
                  _divider(palette),
                  _StatCell(
                    icon: Icons.contacts_rounded,
                    color: AppColors.primaryGreen,
                    value: '${summary.emergencyContacts}',
                    label: 'Emergency',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FootNote(
                icon: Icons.event_available_rounded,
                text: 'Next checkup · ${summary.nextCheckup}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class InsuranceSection extends StatelessWidget {
  const InsuranceSection({super.key, required this.summary});

  final InsuranceSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Insurance',
          subtitle: 'Coverage & premiums',
          actionLabel: 'View',
          icon: Icons.shield_rounded,
        ),
        InoCard(
          onTap: () {},
          child: Column(
            children: [
              Row(
                children: [
                  _StatCell(
                    icon: Icons.shield_rounded,
                    color: AppColors.primaryGreen,
                    value: '${summary.activePolicies}',
                    label: 'Active',
                  ),
                  _divider(palette),
                  _StatCell(
                    icon: Icons.timelapse_rounded,
                    color: AppColors.warning,
                    value: '${summary.expiringSoon}',
                    label: 'Expiring',
                  ),
                  _divider(palette),
                  _StatCell(
                    icon: Icons.savings_rounded,
                    color: AppColors.lightBlue,
                    value: summary.totalCover,
                    label: 'Total cover',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FootNote(
                icon: Icons.payments_rounded,
                text: 'Next premium · ${summary.nextPremium}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared primitives
// ---------------------------------------------------------------------------

Widget _divider(AppPalette palette) => Container(
      width: 1,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: palette.border,
    );

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _FootNote extends StatelessWidget {
  const _FootNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: palette.textFaint),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
