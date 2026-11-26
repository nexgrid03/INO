import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/perf/image_decode.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/account_security_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/avatar_color.dart';
import '../../theme/theme_style.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/profile/link_entity_sheet.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../auth/auth_validators.dart';
import '../auth/login_screen.dart' show VerificationChannel;

/// Edit Profile - the primary action of the Profile settings page.
///
/// Allows updating full name directly and updating email or mobile number
/// through OTP verification ([showLinkEntitySheet]) so both `auth.users`
/// sign-in credentials and `public.users` stay in sync and previous
/// credentials stop working.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late UserProfile _profile = widget.profile;
  late final TextEditingController _nameController =
      TextEditingController(text: _profile.fullName);
  late final TextEditingController _emailController =
      TextEditingController(text: _profile.email);
  late final TextEditingController _phoneController =
      TextEditingController(text: _profile.phone ?? '');

  bool _busy = false;
  bool _dirty = false;

  String get _initials {
    final parts = _profile.fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _snack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              isError ? AppColors.critical : AppColors.primaryGreen,
        ),
      );
  }

  Future<void> _changeEntity(VerificationChannel channel) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final isEmail = channel == VerificationChannel.email;
    final typed = isEmail
        ? _emailController.text.trim()
        : _phoneController.text.trim();
    final current = isEmail ? _profile.email.trim() : (_profile.phone ?? '').trim();
    final hasNewInput = isEmail
        ? typed.isNotEmpty &&
            typed.toLowerCase() != current.toLowerCase() &&
            AuthValidators.isValidEmail(typed)
        : typed.isNotEmpty &&
            AccountSecurityService.canonicalPhone(typed) !=
                AccountSecurityService.canonicalPhone(current);

    final updated = await showLinkEntitySheet(
      context,
      profile: _profile,
      channel: channel,
      initialDestination: hasNewInput ? typed : null,
      autoSend: hasNewInput,
      isChange: true,
    );
    if (updated == null || !mounted) return;
    setState(() {
      _profile = updated;
      _dirty = true;
      _emailController.text = updated.email;
      _phoneController.text = updated.phone ?? '';
    });
    _snack(
      isEmail
          ? 'Email updated and verified!'
          : 'Mobile number updated and verified!',
      isError: false,
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context);

    final newName = _nameController.text.trim();
    final newEmail = _emailController.text.trim();
    final rawPhone = _phoneController.text.trim();
    final newCanonicalPhone = AccountSecurityService.canonicalPhone(rawPhone);
    final oldCanonicalPhone =
        AccountSecurityService.canonicalPhone(_profile.phone ?? '');

    final nameChanged = newName != _profile.fullName.trim();
    final emailChanged =
        newEmail.toLowerCase() != _profile.email.trim().toLowerCase();
    final phoneChanged =
        rawPhone.isNotEmpty && newCanonicalPhone != oldCanonicalPhone;

    if (!nameChanged && !emailChanged && !phoneChanged) {
      Navigator.of(context).pop(_dirty ? _profile : null);
      return;
    }

    setState(() => _busy = true);
    try {
      // Pre-check duplicates before prompting OTP or committing partial edits.
      if (emailChanged) {
        await AccountSecurityService.instance.ensureEmailChangeAllowed(
          newEmail,
          currentProfile: _profile,
        );
      }
      final targetPhone =
          newCanonicalPhone.isNotEmpty ? newCanonicalPhone : rawPhone;
      if (phoneChanged) {
        await AccountSecurityService.instance.ensurePhoneChangeAllowed(
          targetPhone,
          currentProfile: _profile,
        );
      }

      if (nameChanged) {
        developer.log('EditProfile: saving name ${_profile.authUserId}',
            name: 'profile');
        final updated = await UserRepository.instance.updateProfile(
          authUserId: _profile.authUserId,
          fullName: newName,
        );
        if (!mounted) return;
        setState(() {
          _profile = updated;
          _dirty = true;
        });
      }

      if (emailChanged && mounted) {
        final verified = await showLinkEntitySheet(
          context,
          profile: _profile,
          channel: VerificationChannel.email,
          initialDestination: newEmail,
          autoSend: true,
          isChange: true,
        );
        if (!mounted) return;
        if (verified == null) {
          _emailController.text = _profile.email;
          _snack('Email verification is required to save the new email.');
          return;
        }
        setState(() {
          _profile = verified;
          _dirty = true;
          _emailController.text = verified.email;
        });
      }

      if (phoneChanged && mounted) {
        final verified = await showLinkEntitySheet(
          context,
          profile: _profile,
          channel: VerificationChannel.phone,
          initialDestination: targetPhone,
          autoSend: true,
          isChange: true,
        );
        if (!mounted) return;
        if (verified == null) {
          _phoneController.text = _profile.phone ?? '';
          _snack(
              'Mobile verification is required to save the new mobile number.');
          return;
        }
        setState(() {
          _profile = verified;
          _dirty = true;
          _phoneController.text = verified.phone ?? '';
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop(_profile);
    } on AuthException catch (e) {
      _snack(AuthService.formatAuthError(e));
    } on PostgrestException catch (e) {
      developer.log('EditProfile Postgrest error: ${e.message}',
          name: 'profile', error: e);
      _snack(e.message);
    } catch (e) {
      developer.log('EditProfile error: $e', name: 'profile', error: e);
      _snack(l10n.t('couldNotSaveChanges'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final validate = AuthValidators.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_dirty ? _profile : null);
      },
      child: SettingsScaffold(
        title: l10n.t('editProfile'),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          // A centred, width-capped column so the form reads as one tidy
          // block on any screen instead of stretching edge to edge.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xl),
                children: [
                  _AvatarEditor(
                    initials: _initials,
                    colorSeed: _profile.email.trim().isNotEmpty
                        ? _profile.email
                        : _profile.fullName,
                    photoUrl: _profile.profilePhoto,
                    onTap: () =>
                        _snack(l10n.t('changePhotoComingSoon'), isError: false),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AuthTextField(
                    controller: _nameController,
                    label: l10n.t('fullName'),
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.name,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: validate.name,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthTextField(
                    key: const ValueKey('edit_profile_email_field'),
                    controller: _emailController,
                    label: l10n.t('emailAddress'),
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) {
                      final trimmed = (v ?? '').trim();
                      if (trimmed.isEmpty && _profile.email.trim().isEmpty) {
                        return null;
                      }
                      return validate.email(v);
                    },
                    suffix: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _changeEntity(VerificationChannel.email),
                      child: Text(
                        'Verify',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthTextField(
                    key: const ValueKey('edit_profile_phone_field'),
                    controller: _phoneController,
                    label: l10n.t('mobileNumber'),
                    hint: l10n.t('mobileHint'),
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    validator: (v) {
                      final trimmed = (v ?? '').trim();
                      if (trimmed.isEmpty &&
                          (_profile.phone ?? '').trim().isEmpty) {
                        return null;
                      }
                      return validate.phone(v);
                    },
                    suffix: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _changeEntity(VerificationChannel.phone),
                      child: Text(
                        'Verify',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Changing your email or mobile number requires OTP verification. You will sign in with the new one afterwards.',
                      style: AppText.caption.copyWith(color: palette.textFaint),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AuthPrimaryButton(
                    label: l10n.t('saveChanges'),
                    busy: _busy,
                    onPressed: _busy ? null : _save,
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

/// The circular gradient avatar with a small camera badge (photo upload is a
/// future flow - the badge signals it without promising it yet).
class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.initials,
    required this.colorSeed,
    required this.onTap,
    this.photoUrl,
  });

  final String initials;
  final String colorSeed;
  final String? photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final style = InoStyle.of(context);
    final accent = AvatarColor.forStyle(style, colorSeed);
    final accentGrad = AvatarColor.gradientForStyle(style, colorSeed);
    return Center(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: accentGrad,
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: palette.isDark ? 0.22 : 0.92,
                    ),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: (photoUrl != null && photoUrl!.isNotEmpty)
                    ? Image.network(
                        photoUrl!,
                        fit: BoxFit.cover,
                        width: 92,
                        height: 92,
                        cacheWidth: context.decodeWidthFor(92),
                        cacheHeight: context.decodeWidthFor(92),
                        errorBuilder: (_, _, _) => _InitialsFill(
                          initials: initials,
                          gradient: accentGrad,
                        ),
                      )
                    : _InitialsFill(
                        initials: initials,
                        gradient: accentGrad,
                      ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.bg, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(Icons.camera_alt_rounded,
                      size: 15, color: accent),
                ),
              ),
            ],
          ),
        ),
      ),
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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 30,
            ),
          ),
        ),
      ),
    );
  }
}
