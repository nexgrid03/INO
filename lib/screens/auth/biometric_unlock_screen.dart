import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import 'auth_flow.dart';
import 'login_screen.dart';

/// Screen 7B — Biometric Unlock.
///
/// Prompts the user to authenticate with biometrics (Face ID/Fingerprint) if
/// enabled on their account. Provides a fallback to sign out and log in via email.
class BiometricUnlockScreen extends StatefulWidget {
  const BiometricUnlockScreen({
    super.key,
    required this.profile,
    this.onUnlocked,
  });

  final UserProfile profile;
  final VoidCallback? onUnlocked;

  @override
  State<BiometricUnlockScreen> createState() => _BiometricUnlockScreenState();
}

class _BiometricUnlockScreenState extends State<BiometricUnlockScreen> {
  BiometricKind _kind = BiometricKind.generic;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    BiometricService.instance.detectKind().then((kind) {
      if (mounted) {
        setState(() => _kind = kind);
        _authenticate();
      }
    });
  }

  Future<void> _authenticate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await BiometricService.instance.authenticate(
        reason: 'Unlock INO to access your vault',
      );
      if (!mounted) return;
      if (ok) {
        if (widget.onUnlocked != null) {
          widget.onUnlocked!();
        } else {
          goToShell(context, widget.profile);
        }
      }
    } catch (_) {
      // Catch silently
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await AuthService.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to sign out. Please try again.'),
            backgroundColor: AppColors.critical,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      scrollable: false,
      child: Column(
        children: [
          const Spacer(flex: 2),
          FadeSlideIn(child: _UnlockArt(kind: _kind, onTap: _authenticate)),
          const Spacer(flex: 2),
          FadeSlideIn(
            delay: const Duration(milliseconds: 80),
            child: const Text(
              'Vault Locked',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            delay: const Duration(milliseconds: 130),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Unlock with ${_kind == BiometricKind.faceId ? 'Face ID' : 'fingerprint or Face ID'} '
                'to access your securely encrypted digital life.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.textMuted,
                  height: 1.55,
                ),
              ),
            ),
          ),
          const Spacer(flex: 3),
          FadeSlideIn(
            delay: const Duration(milliseconds: 180),
            child: AuthPrimaryButton(
              label: 'Unlock Vault',
              icon: _kind == BiometricKind.faceId
                  ? Icons.face_rounded
                  : Icons.fingerprint_rounded,
              busy: _busy,
              onPressed: _busy ? null : _authenticate,
            ),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            delay: const Duration(milliseconds: 220),
            child: TextButton(
              onPressed: _busy ? null : _signOut,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(
                'Switch Account',
                style: TextStyle(
                  color: AppColors.primaryGreen,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _UnlockArt extends StatelessWidget {
  const _UnlockArt({required this.kind, required this.onTap});

  final BiometricKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Soft outer halo.
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryGreen.withValues(alpha: 0.06),
              ),
            ),
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryGreen.withValues(alpha: 0.10),
              ),
            ),
            // Gradient core.
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.4),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(
                kind == BiometricKind.faceId
                    ? Icons.face_rounded
                    : Icons.fingerprint_rounded,
                color: Colors.white,
                size: 60,
              ),
            ),
            // A small "lock" accent badge.
            Positioned(
              right: 30,
              bottom: 30,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.primaryGreen,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
