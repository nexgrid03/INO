import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/auth_service.dart';
import '../../services/signup_identity_flow.dart';
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
/// rest of the flow - it is an ADD, not a redesign of any existing screen.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({
    super.key,
    required this.authUserId,
    required this.fullName,
    required this.email,
    this.phone,
    this.existingProfile,
    this.notice,
  });

  final String authUserId;
  final String fullName;
  final String email;
  final String? phone;

  /// Shown once when signup reached this screen because the profile row
  /// could not be saved. Never a raw database error.
  final String? notice;

  /// The already-created (but incomplete) profile row, if any. Null for a
  /// brand-new user whose row hasn't been inserted yet.
  final UserProfile? existingProfile;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController = TextEditingController(
    text: widget.fullName == 'INO User' ? '' : widget.fullName,
  );
  late final TextEditingController _phoneController = TextEditingController(
    text: widget.phone ?? widget.existingProfile?.phone ?? '',
  );

  bool _busy = false;
  bool _phoneLocked = false;

  static const String _saveFailed =
      "We couldn't save your profile. Your sign-in is saved. Please try again.";
  static const String _ownedByOtherAccount =
      'That email or mobile number is already on another INO account. '
      'Sign out and log in with that account.';

  @override
  void initState() {
    super.initState();
    final notice = widget.notice;
    if (notice != null && notice.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showMessage(notice);
      });
    }
    if (widget.existingProfile != null) {
      _phoneLocked = true;
      final stored = widget.existingProfile!.phone ?? '';
      if (stored.isNotEmpty) _phoneController.text = stored;
    }
    final user = AuthService.instance.currentUser;
    if (widget.existingProfile == null &&
        user?.phoneConfirmedAt != null &&
        (user?.phone ?? '').isNotEmpty) {
      _phoneLocked = true;
      _phoneController.text =
          DualSignupCoordinator.phoneTarget(user!.phone!);
    }
  }

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
    final l10n = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final current = AuthService.instance.currentUser;
    if (widget.existingProfile == null && current != null) {
      final meta = current.userMetadata ?? {};
      final email =
          ((meta['email'] as String?) ?? current.email ?? widget.email).trim();
      final rawPhone =
          ((meta['phone'] as String?) ?? current.phone ?? phone).trim();
      final canonical = DualSignupCoordinator.phoneTarget(rawPhone);
      if (secondFactorStillNeeded(
        emailConfirmed: current.emailConfirmedAt != null,
        phoneConfirmed: current.phoneConfirmedAt != null,
        email: email,
        phone: canonical.isEmpty ? rawPhone : canonical,
      )) {
        _showMessage(
          'Verify your email and mobile number before saving your profile.',
        );
        return;
      }
    }

    setState(() => _busy = true);
    try {
      logAuthEvent(
        widget.existingProfile == null
            ? 'complete profile insert'
            : 'complete profile update',
      );
      UserProfile profile;
      final confirmedPhone = current?.phoneConfirmedAt != null
          ? DualSignupCoordinator.phoneTarget(current?.phone ?? '')
          : null;
      final confirmedEmail = current?.emailConfirmedAt != null
          ? (current?.email ?? '').trim()
          : null;
      if (widget.existingProfile == null &&
          confirmedPhone != null &&
          confirmedPhone.isNotEmpty &&
          profilePhoneToSave(
                confirmedPhone: confirmedPhone,
                typedPhone: phone,
              ) ==
              null) {
        _showMessage('The verified mobile number cannot be changed here.');
        return;
      }
      if (widget.existingProfile != null) {
        profile = await UserRepository.instance.updateProfile(
          authUserId: widget.authUserId,
          fullName: name,
        );
      } else {
        final savePhone = (confirmedPhone != null && confirmedPhone.isNotEmpty)
            ? confirmedPhone
            : DualSignupCoordinator.phoneTarget(phone);
        final saveEmail = (confirmedEmail != null && confirmedEmail.isNotEmpty)
            ? confirmedEmail
            : widget.email;
        profile = await UserRepository.instance.createProfile(
          authUserId: widget.authUserId,
          fullName: name,
          email: saveEmail,
          phone: savePhone,
        );
      }
      logAuthEvent('complete profile saved');
      if (!mounted) return;
      goToShell(context, profile);
    } on PostgrestException catch (e) {
      logAuthEvent('complete profile save failed', code: e.code);
      if (isUsersUniqueViolation(e)) {
        try {
          final existing = await UserRepository.instance
              .getProfileByAuthId(widget.authUserId);
          if (existing != null) {
            if (!mounted) return;
            goToShell(context, existing);
            return;
          }
        } catch (_) {
          logAuthEvent('complete profile reread failed');
        }
        _showMessage(_ownedByOtherAccount);
      } else {
        _showMessage(_saveFailed);
      }
    } catch (_) {
      logAuthEvent('complete profile save failed');
      _showMessage(l10n.t('saveDetailsError'));
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
    final l10n = AppLocalizations.of(context);
    final validate = AuthValidators.of(context);
    return AuthScaffold(
      // No back button: sign-in already succeeded - the only way forward is to
      // finish these details (or the app would strand an authed user on Login).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          FadeSlideIn(child: const _ProfileBadge()),
          const SizedBox(height: 18),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: AuthPageTitle(l10n.t('completeProfile')),
          ),
          const SizedBox(height: 8),
          FadeSlideIn(
            delay: const Duration(milliseconds: 110),
            child: Text(
              l10n.t('completeProfileSubtitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                FadeSlideIn(
                  delay: const Duration(milliseconds: 160),
                  child: AuthTextField(
                    controller: _nameController,
                    label: l10n.t('fullName'),
                    hint: 'e.g. John Doe',
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.name,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: validate.name,
                  ),
                ),
                const SizedBox(height: 14),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 200),
                  child: AuthTextField(
                    controller: _phoneController,
                    label: l10n.t('mobileNumber'),
                    hint: '+91 98765 43210',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    enabled: !_phoneLocked,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    validator: validate.phone,
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FadeSlideIn(
            delay: const Duration(milliseconds: 250),
            child: AuthPrimaryButton(
              label: l10n.t('continue'),
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
                child: Text(
                  l10n.t('notYouSignOut'),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(
          Icons.person_add_alt_1_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}
