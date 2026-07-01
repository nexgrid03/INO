import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import 'auth_flow.dart';
import 'auth_validators.dart';
import 'login_screen.dart';

/// Post-sign-in step for first-time users (notably Google sign-in, which gives
/// us a name + email but no phone number). Collects the remaining details,
/// persists them, then continues into the app shell.
///
/// Built entirely from the existing shared auth components so it matches the
/// rest of the flow — it is an ADD, not a redesign of any existing screen.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({
    super.key,
    required this.authUserId,
    required this.fullName,
    required this.email,
    this.existingProfile,
  });

  final String authUserId;
  final String fullName;
  final String email;

  /// The already-created (but incomplete) profile row, if any. Null for a
  /// brand-new user whose row hasn't been inserted yet.
  final UserProfile? existingProfile;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController =
      TextEditingController(text: widget.fullName);
  late final TextEditingController _phoneController =
      TextEditingController(text: widget.existingProfile?.phone ?? '');

  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() => _busy = true);
    try {
      developer.log(
        'CompleteProfile save (new=${widget.existingProfile == null}) '
        'for ${widget.authUserId}',
        name: 'auth',
      );
      UserProfile profile;
      if (widget.existingProfile == null) {
        // Row doesn't exist yet — create it complete, with the phone included.
        profile = await UserRepository.instance.createProfile(
          authUserId: widget.authUserId,
          fullName: name,
          email: widget.email,
          phone: phone,
        );
      } else {
        // Row exists but was missing details — fill them in.
        profile = await UserRepository.instance.updateProfile(
          authUserId: widget.authUserId,
          fullName: name,
          phone: phone,
        );
      }
      developer.log('CompleteProfile saved → Home (${profile.id})',
          name: 'auth');
      if (!mounted) return;
      goToShell(context, profile);
    } on PostgrestException catch (e) {
      developer.log('CompleteProfile PostgrestException: ${e.message}',
          name: 'auth', error: e);
      _showMessage(e.message);
    } catch (e) {
      developer.log('CompleteProfile error: $e', name: 'auth', error: e);
      _showMessage('Could not save your details. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Escape hatch so an authenticated user who won't/can't provide a phone is
  /// never stranded on this screen (it's pushed with the auth stack cleared).
  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await AuthService.instance.signOut();
    } catch (_) {
      // Best-effort sign-out; still return to Login.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      // No back button: sign-in already succeeded — the only way forward is to
      // finish these details (or the app would strand an authed user on Login).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          FadeSlideIn(child: const _ProfileBadge()),
          const SizedBox(height: 26),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: const Text(
              'Complete Your Profile',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: const Duration(milliseconds: 110),
            child: const Text(
              'Just a couple of details to finish setting up your secure vault.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 30),
          Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                FadeSlideIn(
                  delay: const Duration(milliseconds: 160),
                  child: AuthTextField(
                    controller: _nameController,
                    label: 'Full name',
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.name,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: AuthValidators.name,
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 200),
                  child: AuthTextField(
                    controller: _phoneController,
                    label: 'Mobile number',
                    hint: '+91 98765 43210',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    validator: AuthValidators.phone,
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FadeSlideIn(
            delay: const Duration(milliseconds: 250),
            child: AuthPrimaryButton(
              label: 'Continue',
              busy: _busy,
              onPressed: _busy ? null : _save,
            ),
          ),
          const SizedBox(height: 6),
          FadeSlideIn(
            delay: const Duration(milliseconds: 290),
            child: Center(
              child: TextButton(
                onPressed: _busy ? null : _signOut,
                child: const Text(
                  'Not you? Sign out',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The gradient profile badge shown atop the Complete Profile form.
class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(
          Icons.person_add_alt_1_rounded,
          color: Colors.white,
          size: 38,
        ),
      ),
    );
  }
}
