import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/biometric_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import 'auth_flow.dart';

/// Screen 7 — Biometric Setup.
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
      final ok = await BiometricService.instance.authenticate(
        reason: 'Enable ${_kind.noun} to unlock INO',
      );
      if (!mounted) return;
      if (ok) {
        final updated = await UserRepository.instance.updateBiometricEnabled(
          authUserId: widget.profile.authUserId,
          enabled: true,
        );
        if (!mounted) return;
        goToShell(context, updated);
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
    return AuthScaffold(
      scrollable: false,
      child: Column(
        children: [
          const Spacer(flex: 2),
          FadeSlideIn(child: _BiometricArt(kind: _kind)),
          const Spacer(flex: 2),
          FadeSlideIn(
            delay: const Duration(milliseconds: 80),
            child: const Text(
              'Secure Your Vault',
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Enable ${_kind == BiometricKind.faceId ? 'Face ID' : 'fingerprint or Face ID'} '
                'for faster, safer access to your documents — no password '
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
          const Spacer(flex: 3),
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
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// The large biometric illustration: a gradient ring cradling a fingerprint
/// (or face) glyph, with a soft halo — premium but calm.
class _BiometricArt extends StatelessWidget {
  const _BiometricArt({required this.kind});

  final BiometricKind kind;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
          // A small "lock" accent badge, bottom-right of the core.
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
                Icons.lock_rounded,
                color: AppColors.primaryGreen,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
