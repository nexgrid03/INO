import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// The compact identity header at the top of the Profile settings page.
///
/// Just what a user needs to recognise the account and edit it: a gradient
/// avatar, name, email, one subtle "Vault protected" trust cue, and a small
/// edit affordance. The ENTIRE row is tappable ([onEdit]) — the Apple ID / your
/// Google Account pattern — so there's no oversized "Edit Profile" button.
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
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: palette.border),
              boxShadow: palette.cardShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  _Avatar(initials: _initials, photoUrl: photoUrl),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName.trim().isEmpty ? 'Your Name' : fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body
                              .copyWith(color: palette.textSecondary),
                        ),
                        const SizedBox(height: 7),
                        const _VaultBadge(),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.edit_outlined,
                      size: 19, color: palette.textFaint),
                ],
              ),
            ),
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
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.brandGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.26),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: (photoUrl != null && photoUrl!.isNotEmpty)
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _InitialsFill(initials: initials),
              )
            : _InitialsFill(initials: initials),
      ),
    );
  }
}

class _InitialsFill extends StatelessWidget {
  const _InitialsFill({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
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

/// The single, subtle trust cue allowed in the header.
class _VaultBadge extends StatelessWidget {
  const _VaultBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shield_rounded,
            size: 13, color: AppColors.primaryGreen.withValues(alpha: 0.9)),
        const SizedBox(width: 4),
        Text(
          'Vault protected',
          style: AppText.label.copyWith(
            color: AppColors.primaryGreen.withValues(alpha: 0.9),
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}
