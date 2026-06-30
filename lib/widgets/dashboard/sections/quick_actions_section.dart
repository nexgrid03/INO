import 'package:flutter/material.dart';

import '../../../models/dashboard_models.dart';
import '../../../theme/app_theme.dart';
import '../ino_card.dart';
import '../section_header.dart';
import '../../pressable_scale.dart';

/// Section 5 — Quick Actions.
///
/// A one-tap action grid (Scan, Add Document, Open Vault, QR Share …) wrapped
/// in a single surface. Tiles use large touch targets (≥64px) so they remain
/// comfortable for senior users, and reflow by available width.
class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({
    super.key,
    required this.actions,
    this.onAction,
  });

  final List<QuickAction> actions;
  final void Function(QuickAction action)? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Quick Actions',
          subtitle: 'Everything one tap away',
          icon: Icons.bolt_rounded,
        ),
        InoCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cols = w >= 560 ? 6 : (w >= 420 ? 5 : 4);
              const gap = 4.0;
              final tileW = (w - gap * 2 * cols) / cols;
              return Wrap(
                alignment: WrapAlignment.start,
                children: [
                  for (final a in actions)
                    SizedBox(
                      width: tileW + gap * 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _ActionTile(
                          action: a,
                          onTap: () => onAction?.call(a),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.onTap});

  final QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: action.color.withValues(alpha: 0.30),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: action.color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: Icon(action.icon, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            action.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
