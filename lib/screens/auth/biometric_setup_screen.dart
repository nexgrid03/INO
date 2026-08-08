import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/biometric_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import 'auth_flow.dart';

/// Screen 7 - Biometric Setup.
///
/// The last step of onboarding a new account: offer fingerprint / Face ID for
/// faster, safer unlock. Both actions (Enable / Skip) land in the app shell, so
/// biometrics stay strictly optional. Talks to [BiometricService] (a UI-ready
/// stub today; wire `local_auth` later without touching this screen).
class BiometricSetupScreen extends StatefulWidget {
  const BiometricSetupScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<BiometricSetupScreen> createState() => _BiometricSetupScreenState();
}

class _BiometricSetupScreenState extends State<BiometricSetupScreen> {
  BiometricKind _kind = BiometricKind.generic;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    BiometricService.instance.detectKind().then((kind) {
      if (mounted) setState(() => _kind = kind);
    });
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? AppColors.critical : AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      final available = await BiometricService.instance.isAvailable();
      if (!mounted) return;
      if (!available) {
        _showMessage(
          'No biometrics are set up on this device. You can enable this later '
          'in Settings.',
          isError: false,
        );
        _finish();
        return;
      }
      final ok = await BiometricService.instance.authenticate(
        reason: 'Enable ${_kind.noun} to unlock INO',
      );
      if (!mounted) return;
      if (ok) {
        // Turn the app-lock on (persisted locally) and mirror the choice on the
        // profile row (best-effort - the lock itself is already active).
        await BiometricService.instance.setLockEnabled(true);
        unawaited(
          UserRepository.instance
              .updateProfile(
                authUserId: widget.profile.authUserId,
                biometricEnabled: true,
              )
              .catchError((Object _) => widget.profile),
        );
        if (!mounted) return;
        _finish();
      } else {
        _showMessage('${_kind.noun} setup was cancelled.');
      }
    } catch (_) {
      _showMessage('Could not enable ${_kind.noun}. You can set it up later.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() => goToShell(context, widget.profile);

  @override
  Widget build(BuildContext context) {
    // Divine Glass layout: glass frame illustration, title + copy, two glass
    // feature tiles, then the pill CTA / skip / trust badge. Scrolls (fixed
    // gaps instead of Spacers) so the richer content fits every screen size.
    return AuthScaffold(
      showBack: true,
      child: Column(
        children: [
          const SizedBox(height: 24),
          FadeSlideIn(child: _BiometricArt(kind: _kind)),
          const SizedBox(height: 28),
          FadeSlideIn(
            delay: const Duration(milliseconds: 80),
            child: AuthPageTitle('Secure Your Vault'),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            delay: const Duration(milliseconds: 130),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Enable ${_kind == BiometricKind.faceId ? 'Face ID' : 'fingerprint or Face ID'} '
                'for faster, safer access to your documents - no password '
                'needed each time.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.textMuted,
                  height: 1.55,
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          FadeSlideIn(
            delay: const Duration(milliseconds: 150),
            child: const _FeatureTile(
              icon: Icons.lock_open_rounded,
              title: 'Quick Access',
              subtitle: 'Unlock in less than a second',
            ),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            delay: const Duration(milliseconds: 170),
            child: const _FeatureTile(
              icon: Icons.shield_rounded,
              title: 'Enhanced Privacy',
              subtitle: 'Your biometric data stays on your device',
            ),
          ),
          const SizedBox(height: 32),
          FadeSlideIn(
            delay: const Duration(milliseconds: 180),
            child: AuthPrimaryButton(
              label: _kind.actionLabel,
              icon: _kind == BiometricKind.faceId
                  ? Icons.face_rounded
                  : Icons.fingerprint_rounded,
              busy: _busy,
              onPressed: _busy ? null : _enable,
            ),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            delay: const Duration(milliseconds: 220),
            child: TextButton(
              onPressed: _busy ? null : _finish,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Skip for now',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: const Duration(milliseconds: 260),
            child: const _EncryptionBadge(),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

/// The biometric illustration in the Divine Glass language: a large
/// translucent glass frame (rounded 44) with soft pastel light blobs and the
/// brand-blue fingerprint / face glyph at its centre.
class _BiometricArt extends StatelessWidget {
  const _BiometricArt({required this.kind});

  final BiometricKind kind;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final artSize = width < 360 ? 140.0 : (width < 420 ? 160.0 : 176.0);
    final iconSize = artSize * 0.48;

    return Container(
      width: artSize,
      height: artSize,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(artSize * 0.25),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.8),
          width: 1.5,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Decorative pastel light blobs bleeding in from the corners.
          Positioned(
            top: -artSize * 0.2,
            right: -artSize * 0.2,
            child: _GlowDot(color: AppColors.skyBlue, size: artSize * 0.66),
          ),
          Positioned(
            bottom: -artSize * 0.2,
            left: -artSize * 0.2,
            child: _GlowDot(color: AppColors.tealPale, size: artSize * 0.66),
          ),
          Icon(
            kind == BiometricKind.faceId
                ? Icons.face_rounded
                : Icons.fingerprint_rounded,
            color: AppColors.primaryGreen,
            size: iconSize,
          ),
        ],
      ),
    );
  }
}

/// A soft radial light blob used inside the glass frame.
class _GlowDot extends StatelessWidget {
  const _GlowDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.5),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

/// A glass feature row (pastel icon chip + title + supporting line) from the
/// Divine Glass biometric mockup - purely informational.
class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final launcher = InoStyle.usesDivineGlass(context);
    final row = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration:  BoxDecoration(
            color: AppColors.tealMist,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primaryGreen, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (launcher) {
      return DivineGlassCard(
        radius: 18,
        blur: 14,
        padding: const EdgeInsets.all(14),
        child: row,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.tealPale, width: 1),
      ),
      child: row,
    );
  }
}

/// The decorative "military-grade AES encryption" trust pill from the mockup.
class _EncryptionBadge extends StatelessWidget {
  const _EncryptionBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_user_rounded,
              size: 14,
              color: AppColors.primaryGreen,
            ),
            const SizedBox(width: 8),
            Text(
              'MILITARY-GRADE AES ENCRYPTION',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppColors.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
