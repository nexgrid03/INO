import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 1 — the personalised welcome bar.
///
/// Left: a gradient avatar (initials) + a time-aware greeting and the brand
/// "welcome back" line. Right: global search, a notification bell with an
/// unread dot, and a light/dark theme toggle. A speaker chip plays a single
/// gentle pulse on first build to stand in for the spoken greeting.
class WelcomeHeader extends StatefulWidget {
  const WelcomeHeader({
    super.key,
    required this.fullName,
    required this.onSearch,
    required this.onNotifications,
    this.notificationCount = 0,
  });

  final String fullName;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;
  final int notificationCount;

  @override
  State<WelcomeHeader> createState() => _WelcomeHeaderState();
}

class _WelcomeHeaderState extends State<WelcomeHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  String get _firstName =>
      widget.fullName.trim().isEmpty ? 'there' : widget.fullName.split(' ').first;

  String get _initials {
    final parts = widget.fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
    'Friday', 'Saturday', 'Sunday',
  ];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// Today's date, e.g. "Thursday, 2 July 2026".
  String get _todayLabel {
    final n = DateTime.now();
    return '${_weekdays[n.weekday - 1]}, ${n.day} ${_months[n.month - 1]} ${n.year}';
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        // Avatar with a soft pulsing halo (the "voice greeting" cue).
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = Curves.easeOut.transform(_pulse.value);
            final ring = math.sin(t * math.pi); // 0→1→0
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.35 * ring),
                    blurRadius: 18,
                    spreadRadius: 2 * ring,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.brandGradient,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '$_greeting, $_firstName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('👋', style: TextStyle(fontSize: 16)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _todayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ],
          ),
        ),
        _HeaderIcon(
          icon: Icons.search_rounded,
          onTap: widget.onSearch,
          tooltip: 'Search',
        ),
        const SizedBox(width: 8),
        _HeaderIcon(
          icon: Icons.notifications_none_rounded,
          onTap: widget.onNotifications,
          tooltip: 'Notifications',
          badge: widget.notificationCount,
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
        child: Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 21, color: palette.textPrimary),
                  if (badge > 0)
                    Positioned(
                      top: 9,
                      right: 9,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.critical,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.surface, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
