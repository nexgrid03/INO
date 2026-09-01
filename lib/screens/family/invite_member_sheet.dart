import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../data/family_vault_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/family_vault_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pressable_scale.dart';

/// Bottom sheet for inviting a member by **phone number, name or email**.
///
/// One field, auto-detected: anything with an `@` is an email, digits (with an
/// optional +country code) are a phone number, anything else is a name. The
/// server (`invite_ino_user_to_vault`) resolves that to an INO account:
///
///   * found      → the invitation is created and the person is pushed;
///   * not found  → the sheet explains that they need to install INO and
///                  create an account first (no dangling invitation is made);
///   * ambiguous  → several users share that name; asks for phone/email.
///
/// Pops `true` when an invitation was sent.
Future<bool?> showInviteMemberSheet(BuildContext context, String vaultId) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (_) => _InviteMemberSheet(vaultId: vaultId),
  );
}

enum _Kind { email, phone, name }

class _InviteMemberSheet extends StatefulWidget {
  const _InviteMemberSheet({required this.vaultId});

  final String vaultId;

  @override
  State<_InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends State<_InviteMemberSheet> {
  final _controller = TextEditingController();
  VaultRole _role = VaultRole.viewer;
  bool _sending = false;
  String? _error;

  /// A friendlier, non-error explanation (no account / ambiguous name).
  String? _notice;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phoneRe = RegExp(r'^[+()\s\d-]+$');

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {
          _error = null;
          _notice = null;
        }));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  _Kind get _kind {
    final v = _controller.text.trim();
    if (v.contains('@')) return _Kind.email;
    if (_phoneRe.hasMatch(v) && v.replaceAll(RegExp(r'\D'), '').length >= 8) {
      return _Kind.phone;
    }
    return _Kind.name;
  }

  String? _validate(AppLocalizations l10n) {
    final v = _controller.text.trim();
    if (v.isEmpty) return l10n.t('enterPhoneNameOrEmail');
    switch (_kind) {
      case _Kind.email:
        if (!_emailRe.hasMatch(v)) return l10n.t('enterValidEmailAddress');
      case _Kind.phone:
        final digits = v.replaceAll(RegExp(r'\D'), '');
        if (digits.length < 8 || digits.length > 15) {
          return l10n.t('enterValidPhoneNumber');
        }
      case _Kind.name:
        if (v.length < 2) return l10n.t('enterPhoneNameOrEmail');
    }
    return null;
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final err = _validate(l10n);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
      _notice = null;
    });
    final value = _controller.text.trim();
    try {
      await FamilyVaultRepository.instance.inviteUser(
        widget.vaultId,
        _role,
        _kind == _Kind.phone ? value.replaceAll(' ', '') : value,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on VaultUserNotFound catch (e) {
      if (mounted) {
        setState(() => _notice =
            l10n.t('inviteUserNotFound').replaceAll('{query}', e.query));
      }
    } on VaultUserAmbiguous {
      if (mounted) setState(() => _notice = l10n.t('inviteMultipleMatches'));
    } on PostgrestException catch (e) {
      // Server-side validation (already a member / self / duplicate) is
      // surfaced verbatim so the user knows exactly why it was rejected.
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = l10n.t('couldNotSendInvitation'));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final kind = _kind;
    final kindIcon = switch (kind) {
      _Kind.email => Icons.email_rounded,
      _Kind.phone => Icons.phone_rounded,
      _Kind.name => Icons.person_search_rounded,
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.t('inviteAMember'),
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.t('inviteMemberSubtitleAny'),
                style: AppText.caption.copyWith(color: palette.textSecondary)),
            const SizedBox(height: AppSpacing.md),

            Text(l10n.t('inviteByAnyLabel'),
                style: AppText.label.copyWith(color: palette.textFaint)),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _send(),
              style: AppText.body.copyWith(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.t('inviteByAnyHint'),
                hintStyle: AppText.body.copyWith(color: palette.textFaint),
                prefixIcon: Icon(kindIcon, color: palette.textFaint),
                filled: true,
                fillColor: palette.surfaceVariant,
                border: _border(palette.border),
                enabledBorder: _border(palette.border),
                focusedBorder: _border(AppColors.primaryGreen, 1.6),
                errorText: _error,
              ),
            ),

            if (_notice != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.person_off_rounded,
                        size: 18, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _notice!,
                        style: AppText.caption.copyWith(
                            color: palette.textPrimary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),

            Text(l10n.t('role'),
                style: AppText.label.copyWith(color: palette.textFaint)),
            const SizedBox(height: 6),
            // Owner is never invitable — promote a member afterwards instead.
            Row(
              children: [
                for (final r in VaultRoleX.assignable) ...[
                  Expanded(child: _RoleChip(
                    role: r,
                    selected: _role == r,
                    onTap: () => setState(() => _role = r),
                  )),
                  if (r != VaultRoleX.assignable.last)
                    const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(_role.localizedDescription(l10n),
                style: AppText.caption.copyWith(color: palette.textSecondary)),
            const SizedBox(height: AppSpacing.lg),

            PressableScale(
              child: GestureDetector(
                onTap: _sending ? null : _send,
                child: Container(
                  height: AppSizes.button,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: AppShadows.glow(AppColors.primaryGreen),
                  ),
                  child: Center(
                    child: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white)))
                        : Text(l10n.t('sendInvitation'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        borderSide: BorderSide(color: c, width: w),
      );
}

class _RoleChip extends StatelessWidget {
  const _RoleChip(
      {required this.role, required this.selected, required this.onTap});

  final VaultRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.96,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? role.color.withValues(alpha: 0.16)
                : palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
                color: selected ? role.color : palette.border,
                width: selected ? 1.4 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(role.icon,
                  size: 15,
                  color: selected ? role.color : palette.textSecondary),
              const SizedBox(width: 5),
              Text(role.localizedLabel(AppLocalizations.of(context)),
                  style: AppText.caption.copyWith(
                      color: selected ? role.color : palette.textSecondary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
