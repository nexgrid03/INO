import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/avatar_color.dart';
import '../../theme/theme_style.dart';
import '../pressable_scale.dart';

/// The compact identity header at the top of the Profile settings page.
///
/// Solid plate (not translucent glass) so it stays readable on the wash, with
/// a theme-aware accent colour for the avatar ring / initials.
class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({
    super.key,
    required this.fullName,
    required this.email,
    required this.onEdit,
    this.photoUrl,
  });

  final String fullName;
  final String email;
  final String? photoUrl;
  final VoidCallback onEdit;

  String get _initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get _colorSeed =>
      email.trim().isNotEmpty ? email : (fullName.trim().isEmpty ? 'ino' : fullName);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final style = InoStyle.of(context);
    final accent = AvatarColor.forStyle(style, _colorSeed);
    final accentGrad = AvatarColor.gradientForStyle(style, _colorSeed);
    final plate =
        Color.lerp(palette.surface, accent, palette.isDark ? 0.12 : 0.06)!;

    return PressableScale(
      pressedScale: 0.99,
      child: GestureDetector(
        onTap: onEdit,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.lg),
          decoration: BoxDecoration(
            color: plate,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: Color.lerp(palette.border, accent, 0.35)!,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: palette.isDark ? 0.28 : 0.14),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: palette.isDark ? 0.35 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _Avatar(
                      initials: _initials,
                      photoUrl: photoUrl,
                      gradient: accentGrad,
                      plate: plate,
                      accent: accent,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      fullName.trim().isEmpty ? 'Your Name' : fullName,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body
                          .copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    _VaultBadge(accent: accent),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Icon(Icons.edit_outlined,
                    size: 19, color: palette.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initials,
    required this.gradient,
    required this.plate,
    required this.accent,
    this.photoUrl,
  });

  final String initials;
  final String? photoUrl;
  final Gradient gradient;
  final Color plate;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: gradient,
            border: Border.all(
              color: Colors.white.withValues(
                alpha: palette.isDark ? 0.22 : 0.92,
              ),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.26),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: (photoUrl != null && photoUrl!.isNotEmpty)
              ? Image.network(
                  photoUrl!,
                  fit: BoxFit.cover,
                  width: 76,
                  height: 76,
                  errorBuilder: (_, _, _) =>
                      _InitialsFill(initials: initials, gradient: gradient),
                )
              : _InitialsFill(initials: initials, gradient: gradient),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              border: Border.all(color: plate, width: 2),
            ),
            child: const Icon(Icons.check_rounded,
                size: 14, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _InitialsFill extends StatelessWidget {
  const _InitialsFill({required this.initials, required this.gradient});

  final String initials;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 19,
          ),
        ),
      ),
    );
  }
}

class _VaultBadge extends StatelessWidget {
  const _VaultBadge({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 13, color: accent),
          const SizedBox(width: 5),
          Text(
            'VAULT PROTECTED',
            style: AppText.label.copyWith(
              color: accent,
              fontSize: 10.5,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
