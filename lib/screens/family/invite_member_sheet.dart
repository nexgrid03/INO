import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../data/family_vault_repository.dart';
import '../../models/family_vault_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pressable_scale.dart';

/// Bottom sheet for inviting a member by email or phone with a role. Pops
/// `true` when an invitation was sent. All permission / dedup checks are
/// enforced server-side by `invite_to_vault` (see the 20260731 migration); this
/// sheet just does light client validation for fast feedback.
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

enum _By { email, phone }

class _InviteMemberSheet extends StatefulWidget {
  const _InviteMemberSheet({required this.vaultId});

  final String vaultId;

  @override
  State<_InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends State<_InviteMemberSheet> {
  final _controller = TextEditingController();
  _By _by = _By.email;
  VaultRole _role = VaultRole.viewer;
  bool _sending = false;
  String? _error;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phoneRe = RegExp(r'^\+?[0-9]{8,15}$');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate() {
    final v = _controller.text.trim();
    if (v.isEmpty) {
      return _by == _By.email ? 'Enter an email address' : 'Enter a phone number';
    }
    if (_by == _By.email && !_emailRe.hasMatch(v)) {
      return 'Enter a valid email address';
    }
    if (_by == _By.phone && !_phoneRe.hasMatch(v.replaceAll(' ', ''))) {
      return 'Enter a valid phone number (e.g. +919876543210)';
    }
    return null;
  }

  Future<void> _send() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    final value = _controller.text.trim();
    try {
      await FamilyVaultRepository.instance.invite(
        widget.vaultId,
        _role,
        email: _by == _By.email ? value : null,
        phone: _by == _By.phone ? value.replaceAll(' ', '') : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      // Server-side validation (duplicate / already a member / self / role) is
      // surfaced verbatim so the user knows exactly why it was rejected.
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t send the invitation. Try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
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
          Text('Invite a member',
              style: AppText.title.copyWith(color: palette.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text('They\'ll join when they accept — even if they sign up later '
              'with this email or number.',
              style: AppText.caption.copyWith(color: palette.textSecondary)),
          const SizedBox(height: AppSpacing.md),

          // Email / Phone toggle.
          _Segmented(
            options: const ['Email', 'Phone'],
            selectedIndex: _by == _By.phone ? 1 : 0,
            onChanged: (i) => setState(() {
              _by = i == 1 ? _By.phone : _By.email;
              _error = null;
            }),
          ),
          const SizedBox(height: AppSpacing.md),

          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: _by == _By.email
                ? TextInputType.emailAddress
                : TextInputType.phone,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            style: AppText.body.copyWith(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: _by == _By.email
                  ? 'name@example.com'
                  : '+91 98765 43210',
              hintStyle: AppText.body.copyWith(color: palette.textFaint),
              prefixIcon: Icon(
                  _by == _By.email
                      ? Icons.email_rounded
                      : Icons.phone_rounded,
                  color: palette.textFaint),
              filled: true,
              fillColor: palette.surfaceVariant,
              border: _border(palette.border),
              enabledBorder: _border(palette.border),
              focusedBorder: _border(AppColors.primaryGreen, 1.6),
              errorText: _error,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Text('Role', style: AppText.label.copyWith(color: palette.textFaint)),
          const SizedBox(height: 6),
          // Owner is never invitable — only these three roles.
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
          Text(_role.description,
              style: AppText.caption.copyWith(color: palette.textSecondary)),
          const SizedBox(height: AppSpacing.lg),

          PressableScale(
            child: GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                height: AppSizes.button,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.button),
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
                      : const Text('Send Invitation',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                ),
              ),
            ),
          ),
        ],
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
              Text(role.label,
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

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient:
                        i == selectedIndex ? AppColors.brandGradient : null,
                    borderRadius: BorderRadius.circular(AppRadius.chip - 4),
                  ),
                  child: Text(options[i],
                      style: AppText.subtitle.copyWith(
                          color: i == selectedIndex
                              ? Colors.white
                              : palette.textSecondary,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
