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
      if (PasswordStore.instance.items.isNotEmpty && !PasswordStore.instance.canReseal) {
        setState(() {
          _busy = false;
          _error = 'Passphrase reset aborted: vault entries are not decrypted plaintext.';
        });
        return;
      }
      ok = await VaultCrypto.instance.resetPassphrase(value);
      // Re-seal what this device still holds in plaintext under the new key,
      // so a reset from the phone that has the entries loses nothing.
      if (ok && PasswordStore.instance.canReseal) {
        final resealed = await PasswordStore.instance.resealForNewKey();
        if (!resealed) {
          setState(() {
            _busy = false;
            _error = 'Failed to reseal vault entries.';
          });
          return;
        }
      }
    } else if (widget.isFirstTime) {
      ok = await VaultCrypto.instance.createPassphrase(value);
    } else {
      ok = await VaultCrypto.instance.unlock(value);
    }

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = _creating
            ? l10n.t('vaultPassphraseSetupFailed')
            : l10n.t('vaultPassphraseIncorrect');
      });
    }
  }

  /// "Forgot passphrase?" - the recovery path for a vault whose passphrase is lost.
  ///
  /// If the vault is empty: allows device-authenticated reset directly.
  /// If sealed entries exist: offers an explicit "destroy vault and start over"
  /// flow backed by biometric / device verification, rather than a permanent dead end.
  Future<void> _forgotPassphrase() async {
    final l10n = AppLocalizations.of(context);
    final uid = Supabase.instance.client.auth.currentUser?.id;

    await PasswordStore.instance.reload();
    if (!mounted) return;

    final localCount = PasswordStore.instance.count;
    final hasSealedLocal = PasswordStore.instance.hasSealedEntries || PasswordStore.instance.hydratedWhileLocked;
    int? serverCount;
    try {
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

    final hasEncryptedData = (serverCount != null && serverCount > 0) ||
        (localCount > 0 && hasSealedLocal);

    if (hasEncryptedData) {
      // Sealed entries exist: offer explicit destroy-and-start-over flow
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.t('vaultResetWarnTitle')),
          content: Text(
            'Because the vault is locked and the passphrase was forgotten, existing encrypted passwords cannot be recovered.\n\n'
            'To regain access, you must destroy the ${serverCount != null && serverCount > 0 ? '$serverCount ' : ''}encrypted passwords and start over with a fresh passphrase.\n\n'
            'Do you wish to permanently destroy the vault and start over?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Destroy Vault & Start Over',
                style: TextStyle(color: AppColors.critical, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;

      final proven = await BiometricService.instance.authenticate(
        reason: l10n.t('authResetVaultPassphrase'),
      );
      if (!mounted) return;
      if (!proven) {
        setState(() => _error = l10n.t('vaultPassphraseIncorrect'));
        return;
      }

      setState(() => _busy = true);
      final destroyed = await PasswordStore.instance.destroyVault(uid);
      if (!mounted) return;
      setState(() => _busy = false);

      if (!destroyed) {
        setState(() => _error = 'Failed to reset vault on server. Please check your network.');
        return;
      }

      setState(() {
        _resetting = true;
        _error = null;
        _acknowledged = false;
        _passphrase.clear();
        _confirm.clear();
      });
      return;
    }

    // Empty vault path or legitimately unlocked path:
    final proven = await BiometricService.instance.authenticate(
      reason: l10n.t('authResetVaultPassphrase'),
    );
    if (!mounted) return;
    if (!proven) {
      setState(() => _error = l10n.t('vaultPassphraseIncorrect'));
      return;
    }

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
