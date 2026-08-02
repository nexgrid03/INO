import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

/// The compact identity header at the top of the Profile settings page.
///
/// Just what a user needs to recognise the account and edit it: a gradient
/// avatar, name, email, one subtle "Vault protected" trust cue, and a small
/// edit affordance. The ENTIRE row is tappable ([onEdit]) - the Apple ID / your
/// Google Account pattern - so there's no oversized "Edit Profile" button.
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.99,
      child: GestureDetector(
        onTap: onEdit,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(AppRadius.card),
          blur: 20,
          frost: palette.isDark ? 1.05 : 0.72,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.lg),
          child: Stack(
            children: [
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _Avatar(initials: _initials, photoUrl: photoUrl),
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
                    const _VaultBadge(),
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
  const _Avatar({required this.initials, this.photoUrl});

  final String initials;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: InoStyle.gradient(context, AppColors.brandGradient),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.26),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: ClipOval(
            child: (photoUrl != null && photoUrl!.isNotEmpty)
                ? Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _InitialsFill(initials: initials),
                  )
                : _InitialsFill(initials: initials),
          ),
        ),
        // Small verified badge riding the avatar's bottom-right edge.
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
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
  const _InitialsFill({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: InoStyle.gradient(context, AppColors.brandGradient)),
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

/// The single, subtle trust cue allowed in the header - a Divine Glass pastel
/// pill with the shield glyph and small-caps label.
class _VaultBadge extends StatelessWidget {
  const _VaultBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.tealFoam,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.tealPale),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded,
              size: 13, color: AppColors.primaryGreen),
          const SizedBox(width: 5),
          Text(
            'VAULT PROTECTED',
            style: AppText.label.copyWith(
              color: AppColors.primaryGreen,
              fontSize: 10.5,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
