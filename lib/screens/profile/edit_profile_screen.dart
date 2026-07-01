import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../auth/auth_validators.dart';

/// Edit Profile — the primary action of the Profile settings page.
///
/// A focused sub-screen (opened from the identity header) for the fields the
/// app actually owns: full name and phone number. Email is shown read-only —
/// changing a sign-in email is a separate, security-sensitive flow. Saves
/// through [UserRepository.updateProfile] and returns the fresh [UserProfile]
/// so the caller can update its view.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController =
      TextEditingController(text: widget.profile.fullName);
  late final TextEditingController _phoneController =
      TextEditingController(text: widget.profile.phone ?? '');

  bool _busy = false;

  String get _initials {
    final parts = widget.profile.fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  void dispose() {
    _nameController.dispose();
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      developer.log('EditProfile: saving ${widget.profile.authUserId}',
          name: 'profile');
      final updated = await UserRepository.instance.updateProfile(
        authUserId: widget.profile.authUserId,
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on PostgrestException catch (e) {
      developer.log('EditProfile Postgrest error: ${e.message}',
          name: 'profile', error: e);
      _snack(e.message);
    } catch (e) {
      developer.log('EditProfile error: $e', name: 'profile', error: e);
      _snack('Could not save your changes. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: palette.textPrimary),
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Edit Profile',
          style: AppText.title.copyWith(color: palette.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
                AppSpacing.screen, AppSpacing.xl),
            children: [
              const SizedBox(height: AppSpacing.xs),
              _AvatarEditor(
                initials: _initials,
                photoUrl: widget.profile.profilePhoto,
                onTap: () => _snack('Change photo — coming soon',
                    isError: false),
              ),
              const SizedBox(height: AppSpacing.xl),
              AuthTextField(
                controller: _nameController,
                label: 'Full name',
                icon: Icons.person_outline_rounded,
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                validator: AuthValidators.name,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthTextField(
                controller:
                    TextEditingController(text: widget.profile.email),
                label: 'Email address',
                icon: Icons.mail_outline_rounded,
                enabled: false,
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Email is tied to your sign-in and can’t be changed here.',
                  style: AppText.caption.copyWith(color: palette.textFaint),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AuthTextField(
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
              const SizedBox(height: AppSpacing.xl),
              AuthPrimaryButton(
                label: 'Save Changes',
                busy: _busy,
                onPressed: _busy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The circular gradient avatar with a small camera badge (photo upload is a
/// future flow — the badge signals it without promising it yet).
class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.initials,
    required this.onTap,
    this.photoUrl,
  });

  final String initials;
  final String? photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
                  gradient: AppColors.brandGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
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
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 15, color: AppColors.primaryGreen),
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
            fontSize: 30,
          ),
        ),
      ),
    );
  }
}
