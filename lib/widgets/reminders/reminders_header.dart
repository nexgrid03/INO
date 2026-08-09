import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/avatar_color.dart';
import '../../theme/theme_style.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

/// The Reminders Dashboard header: gradient profile avatar, page title +
/// subtitle, and search / notification actions. Matches the home header
/// LiquidGlass icon chrome and a flush white avatar rim.
class RemindersHeader extends StatelessWidget {
  const RemindersHeader({
    super.key,
    required this.fullName,
    required this.onSearch,
    required this.onNotifications,
    this.email,
    this.notificationCount = 0,
  });

  final String fullName;
  final String? email;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;
  final int notificationCount;

  String get _initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get _colorSeed {
    final mail = email?.trim() ?? '';
    if (mail.isNotEmpty) return mail;
    final name = fullName.trim();
    return name.isEmpty ? 'ino' : name;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final style = InoStyle.of(context);
    final accentGrad = AvatarColor.gradientForStyle(style, _colorSeed);
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: accentGrad,
            border: Border.all(
              color: Colors.white.withValues(
                alpha: palette.isDark ? 0.22 : 0.92,
              ),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: palette.isDark ? 0.35 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            _initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.t('reminders'),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.2,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.t('remindersSubtitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ],
          ),
        ),
        _HeaderIcon(
          icon: Icons.search_rounded,
          tooltip: l10n.t('search'),
          onTap: onSearch,
        ),
        const SizedBox(width: 8),
        _HeaderIcon(
          icon: Icons.notifications_none_rounded,
          tooltip: l10n.t('notifications'),
          onTap: onNotifications,
          badge: notificationCount,
        ),
      ],
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: tooltip,
        child: LiquidGlass(
          circle: true,
          blur: 16,
          shadow: false,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 21, color: AppColors.primaryGreen),
                    if (badge > 0)
                      Positioned(
                        top: 5,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.critical,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: palette.surfaceVariant,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badge > 9 ? '9+' : '$badge',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              height: 1,
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
      ),
    );
  }
}
