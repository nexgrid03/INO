import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/avatar_color.dart';
import '../../theme/theme_style.dart';
import '../common/liquid_glass.dart';
import '../home/voice_mic_button.dart';
import '../pressable_scale.dart';

/// Section 1 - the personalised welcome bar.
///
/// Left: avatar + greeting. Launcher / Aqua family use a fixed profile fill
/// for every user; classic / bold / soft keep the per-user [AvatarColor]
/// rainbow. Right: notifications / help / theme controls.
class WelcomeHeader extends StatefulWidget {
  const WelcomeHeader({
    super.key,
    required this.fullName,
    required this.onNotifications,
    this.onProfile,
    this.photoUrl,
    this.email,
    this.notificationCount = 0,
    this.voiceButtonKey,
    this.launcherStyle = false,
    this.onHelp,
  });

  final String fullName;
  final VoidCallback onNotifications;

  /// Optional key attached to the voice-assistant button so the first-run tour
  /// can spotlight it.
  final Key? voiceButtonKey;

  /// Opens the Profile page when the avatar is tapped.
  final VoidCallback? onProfile;

  /// Optional profile photo; falls back to gradient initials when null/empty.
  final String? photoUrl;

  /// Used for stable per-user avatar colour (matches Profile).
  final String? email;

  final int notificationCount;

  /// Launcher theme: subtitle becomes vault-protected status; trailing shows
  /// help instead of the header mic (voice lives in Quick Actions).
  final bool launcherStyle;

  /// Shown when [launcherStyle] is true (Help Center).
  final VoidCallback? onHelp;

  @override
  State<WelcomeHeader> createState() => _WelcomeHeaderState();
}

class _WelcomeHeaderState extends State<WelcomeHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  String get _firstName => widget.fullName.trim().isEmpty
      ? 'there'
      : widget.fullName.split(' ').first;

  String get _initials {
    final parts = widget.fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _initialsLabel() => Center(
    child: Text(
      _initials,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 18,
      ),
    ),
  );

  String get _colorSeed {
    final email = widget.email?.trim() ?? '';
    if (email.isNotEmpty) return email;
    final name = widget.fullName.trim();
    return name.isEmpty ? 'ino' : name;
  }

  String _greeting(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h < 5) return l10n.t('greetingNight');
    if (h < 12) return l10n.t('greetingMorning');
    if (h < 17) return l10n.t('greetingAfternoon');
    if (h < 21) return l10n.t('greetingEvening');
    return l10n.t('greetingNight');
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final style = InoStyle.of(context);
    final accent = AvatarColor.forStyle(style, _colorSeed);
    final accentGrad = AvatarColor.gradientForStyle(style, _colorSeed);

    return Row(
      children: [
        // Avatar with a soft pulsing halo (the "voice greeting" cue). Tapping it
        // opens the Profile page.
        PressableScale(
          pressedScale: 0.92,
          child: GestureDetector(
            onTap: widget.onProfile,
            behavior: HitTestBehavior.opaque,
            child: Tooltip(
              message: 'Profile',
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final t = Curves.easeOut.transform(_pulse.value);
                  final ring = math.sin(t * math.pi); // 0→1→0
                  final dark = AppPalette.of(context).isDark;
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(
                            alpha: (dark ? 0.16 : 0.35) * ring,
                          ),
                          blurRadius: dark ? 10 : 18,
                          spreadRadius: (dark ? 1 : 2) * ring,
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: accentGrad,
                    // Match LiquidGlass hairline — rim flush on the avatar.
                    border: Border.all(
                      color: AppPalette.of(context).isDark
                          ? Colors.white.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.92),
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  child:
                      (widget.photoUrl != null && widget.photoUrl!.isNotEmpty)
                      ? Image.network(
                          widget.photoUrl!,
                          fit: BoxFit.cover,
                          width: 48,
                          height: 48,
                          errorBuilder: (_, _, _) => _initialsLabel(),
                        )
                      : _initialsLabel(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.launcherStyle
                    ? 'Hi, $_firstName'
                    : '${_greeting(l10n)}, $_firstName ',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                  letterSpacing: -0.2,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              if (widget.launcherStyle)
                Row(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 14,
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.t('vaultFullyProtected'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                )
              else
                // Status-line treatment: a small live brand dot ahead of the
                // localized full date (weekday + month follow the app locale).
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryGreen,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.glowOf(
                              context,
                              light: 0.35,
                              dark: 0.16,
                            ),
                            blurRadius: AppPalette.of(context).isDark ? 4 : 6,
                            spreadRadius: AppPalette.of(context).isDark ? 0 : 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatFullDate(DateTime.now()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (widget.launcherStyle) ...[
          _HeaderIcon(
            icon: Icons.notifications_none_rounded,
            onTap: widget.onNotifications,
            tooltip: AppLocalizations.of(context).t('notifications'),
            badge: widget.notificationCount,
          ),
          const SizedBox(width: 8),
          _HeaderIcon(
            icon: Icons.help_outline_rounded,
            onTap: widget.onHelp ?? () {},
            tooltip: AppLocalizations.of(context).t('helpCenter'),
          ),
        ] else ...[
          // Voice assistant - a small icon beside the bell (replaces search).
          VoiceMicIconButton(key: widget.voiceButtonKey, size: 42),
          const SizedBox(width: 8),
          _HeaderIcon(
            icon: Icons.notifications_none_rounded,
            onTap: widget.onNotifications,
            tooltip: AppLocalizations.of(context).t('notifications'),
            badge: widget.notificationCount,
          ),
        ],
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
        // Liquid Glass chrome: the sky gradient refracts through the circle.
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
