import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';

/// A compact, horizontally scrolling row of reminder-creation shortcuts
/// (Create · Birthday · Insurance · Health · Document · Property). Emits the
/// chosen action's label.
class ReminderQuickActions extends StatelessWidget {
  const ReminderQuickActions({super.key, required this.onSelect});

  final ValueChanged<String> onSelect;

  static const _actions = <({String label, IconData icon, Color color})>[
    (
      label: 'Document',
      icon: Icons.description_rounded,
      color: AppColors.lightBlue
    ),
    (
      label: 'Insurance',
      icon: Icons.shield_rounded,
      color: AppColors.warning
    ),
    (
      label: 'Health',
      icon: Icons.favorite_rounded,
      color: Color(0xFFEC6A8C)
    ),
    (
      label: 'Property',
      icon: Icons.home_work_rounded,
      color: Color(0xFF8B6CEF)
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Four compact actions share the row evenly — no horizontal scroll needed.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: Row(
        children: [
          for (var i = 0; i < _actions.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _ActionTile(
                icon: _actions[i].icon,
                label: _actions[i].label,
                color: _actions[i].color,
                onTap: () => onSelect(_actions[i].label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.chip,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
