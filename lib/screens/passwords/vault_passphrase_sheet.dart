import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/net/net_guard.dart';
import '../../l10n/app_localizations.dart';
import '../../services/biometric_service.dart';
import '../../services/password_store.dart';
import '../../services/vault_crypto.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_loader.dart';

/// Sets up or unlocks the Password Vault's encryption passphrase.
///
/// This passphrase is the *only* thing that can derive the key protecting the
/// stored credentials - it is never uploaded, and nothing recoverable is kept
/// anywhere. That makes the copy on this sheet part of the security design, not
/// decoration: a user who is not told plainly that there is no reset will treat
/// it like a password they can recover, and lose their vault.
///
/// Returns true when the vault ends up unlocked.
Future<bool> showVaultPassphraseSheet(
  BuildContext context, {
  required bool isFirstTime,
}) async {
  // Dismissible in both modes. First-time setup used to trap the user here,
  // which the Android back button defeated anyway — and it is no longer needed:
  // the caller keeps the vault shut on anything but `true` (see _VaultGate),
  // so backing out lands on the locked screen rather than sneaking past the
  // gate. A modal you cannot close is worse than one that simply changes
  // nothing.
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VaultPassphraseSheet(isFirstTime: isFirstTime),
  );
  return result ?? false;
}

class _VaultPassphraseSheet extends StatefulWidget {
  const _VaultPassphraseSheet({required this.isFirstTime});

  final bool isFirstTime;

  @override
  State<_VaultPassphraseSheet> createState() => _VaultPassphraseSheetState();
}

class _VaultPassphraseSheetState extends State<_VaultPassphraseSheet> {
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  bool _acknowledged = false;
  String? _error;

  /// The sheet has been switched from "unlock" to "choose a new passphrase"
  /// after the user proved device ownership. See [_forgotPassphrase].
  bool _resetting = false;

  /// True whenever the form is asking for a NEW passphrase - first-time setup
  /// and a post-biometric reset ask for exactly the same thing (twice, with an
  /// acknowledgement), so they share every branch below.
  bool get _creating => widget.isFirstTime || _resetting;

  /// Short enough to be memorable, long enough that PBKDF2 at 210k rounds makes
  /// brute force impractical. Below this the key derivation is doing all the
  /// work on its own, which is not a position worth being in.
  static const int _minLength = 10;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _passphrase.text;
    final l10n = AppLocalizations.of(context);

    if (_creating) {
      if (value.length < _minLength) {
        setState(() => _error = l10n
            .t('vaultPassphraseTooShort')
            .replaceAll('{n}', '$_minLength'));
        return;
      }
      if (value != _confirm.text) {
        setState(() => _error = l10n.t('vaultPassphraseMismatch'));
        return;
      }
      if (!_acknowledged) {
        setState(() => _error = l10n.t('vaultPassphraseAckRequired'));
        return;
      }
    } else if (value.isEmpty) {
      setState(() => _error = l10n.t('vaultPassphraseRequired'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final bool ok;
    if (_resetting) {
      ok = await VaultCrypto.instance.resetPassphrase(value);
      // Re-seal what this device still holds in plaintext under the new key,
      // so a reset from the phone that has the entries loses nothing.
      if (ok) await PasswordStore.instance.resealForNewKey();
    } else if (widget.isFirstTime) {
      ok = await VaultCrypto.instance.createPassphrase(value);
    } else {
      ok = await VaultCrypto.instance.unlock(value);
    }

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = _resetting
          ? l10n.t('vaultResetFailed')
          : widget.isFirstTime
              ? l10n.t('vaultSetupFailed')
              : l10n.t('vaultPassphraseIncorrect');
    });
  }

  /// "Forgot passphrase?" - the only way back into a vault whose passphrase is
  /// gone.
  ///
  /// It cannot recover the old key (nothing anywhere can), so it re-keys the
  /// vault instead, behind two gates:
  ///
  ///  1. **Device ownership.** The OS prompt runs with `biometricOnly: false`,
  ///     so a phone with no fingerprint enrolled falls back to its PIN or
  ///     pattern - otherwise this door would be shut precisely for the users
  ///     most likely to need it.
  ///  2. **Informed consent.** The dialog states the real cost up front: the
  ///     passwords cached on THIS device survive (they are re-encrypted under
  ///     the new key), anything that only ever lived on another device does
  ///     not. The count is spelled out so the choice is concrete.
  Future<void> _forgotPassphrase() async {
    final l10n = AppLocalizations.of(context);

    final proven = await BiometricService.instance.authenticate(
      reason: l10n.t('authResetVaultPassphrase'),
    );
    if (!mounted) return;
    if (!proven) {
      setState(() => _error = l10n.t('vaultPassphraseIncorrect'));
      return;
    }

    await PasswordStore.instance.reload();
    if (!mounted) return;

    if (!PasswordStore.instance.isLoaded) {
      setState(() => _error = 'Unable to verify vault state. Please try again.');
      return;
    }

    final localCount = PasswordStore.instance.count;
    int? serverCount;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        final res = await Supabase.instance.client
            .from('w_password_vault')
            .select('id')
            .eq('auth_user_id', uid)
            .count(CountOption.exact)
            .timeout(NetGuard.query);
        serverCount = res.count;
      }
    } catch (_) {
      serverCount = null;
    }

    if (!mounted) return;

    // Explicit warning if server count cannot be determined (Requirement 8)
    if (serverCount == null) {
      final proceedOffline = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.t('vaultResetWarnTitle')),
          content: const Text(
            'Unable to check server vault status because the device is offline. '
            'Resetting your passphrase will replace the encryption key. Any passwords stored on other devices '
            'or not cached locally will become permanently unreadable.\n\nDo you still wish to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.t('resetPassphrase'),
                style: const TextStyle(color: AppColors.critical),
              ),
            ),
          ],
        ),
      );
      if (proceedOffline != true || !mounted) return;
    } else if (localCount == 0 && serverCount > 0) {
      // Local is empty but server has passwords (Requirement 6 & 8)
      final proceedServerMismatch = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.t('vaultResetWarnTitle')),
          content: Text(
            'Warning: This device has 0 local passwords, but your account has $serverCount passwords stored on the server. '
            'Resetting the passphrase cannot recover those $serverCount server passwords, and they will become permanently inaccessible.\n\n'
            'Do you still wish to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.t('resetPassphrase'),
                style: const TextStyle(color: AppColors.critical),
              ),
            ),
          ],
        ),
      );
      if (proceedServerMismatch != true || !mounted) return;
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('vaultResetWarnTitle')),
        content: Text(
          l10n
              .t('vaultResetWarnBody')
              .replaceAll('{n}', '$localCount'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.t('resetPassphrase'),
              style: const TextStyle(color: AppColors.critical),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _resetting = true;
      _error = null;
      _acknowledged = false;
      _passphrase.clear();
      _confirm.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgElevated,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
          border: Border.all(color: palette.border),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                    color: AppColors.tealPale,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.tealMist,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: Border.all(color: AppColors.tealPale),
                    ),
                    child:  Icon(Icons.lock_rounded,
                        color: AppColors.primaryGreen, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _resetting
                          ? l10n.t('resetVaultPassphrase')
                          : widget.isFirstTime
                              ? l10n.t('setVaultPassphrase')
                              : l10n.t('unlockYourVault'),
                      style: AppText.title.copyWith(color: palette.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _resetting
                    ? l10n.t('vaultResetIntro')
                    : widget.isFirstTime
                        ? l10n.t('vaultSetupIntro')
                        : l10n.t('vaultUnlockIntro'),
                style: AppText.body.copyWith(
                  color: palette.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passphrase,
                obscureText: _obscure,
                autofocus: true,
                enabled: !_busy,
                textInputAction:
                    _creating ? TextInputAction.next : TextInputAction.done,
                onSubmitted: _creating ? null : (_) => _submit(),
                style: AppText.body.copyWith(color: palette.textPrimary),
                decoration: InputDecoration(
                  labelText: l10n.t('vaultPassphraseLabel'),
                  prefixIcon: const Icon(Icons.key_rounded, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_creating) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: _obscure,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  style: AppText.body.copyWith(color: palette.textPrimary),
                  decoration: InputDecoration(
                    labelText: l10n.t('confirmPassphrase'),
                    prefixIcon: const Icon(Icons.key_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 16),
                // Not a dark pattern and not boilerplate: this is genuinely
                // unrecoverable, and the user must actively acknowledge it
                // before any credential is sealed with a key only they hold.
                InkWell(
                  onTap: _busy
                      ? null
                      : () => setState(() => _acknowledged = !_acknowledged),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.30)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _acknowledged,
                          onChanged: _busy
                              ? null
                              : (v) =>
                                  setState(() => _acknowledged = v ?? false),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              l10n.t('vaultPassphraseAck'),
                              style: AppText.caption.copyWith(
                                color: palette.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 18, color: AppColors.critical),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: AppText.caption
                            .copyWith(color: AppColors.critical),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                  ),
                  child: _busy
                      ? const InoLoader(size: 20, color: Colors.white)
                      : Text(_resetting
                          ? l10n.t('resetPassphrase')
                          : widget.isFirstTime
                              ? l10n.t('createVault')
                              : l10n.t('unlockVault')),
                ),
              ),
              if (!_creating) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _busy ? null : _forgotPassphrase,
                  child: Text(l10n.t('forgotPassphrase')),
                ),
              ],
              if (!widget.isFirstTime) ...[
                TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(false),
                  child: Text(l10n.t('notNow')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
