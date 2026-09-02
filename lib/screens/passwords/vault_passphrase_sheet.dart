import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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

    if (widget.isFirstTime) {
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

    final ok = widget.isFirstTime
        ? await VaultCrypto.instance.createPassphrase(value)
        : await VaultCrypto.instance.unlock(value);

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = widget.isFirstTime
          ? l10n.t('vaultSetupFailed')
          : l10n.t('vaultPassphraseIncorrect');
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
                      widget.isFirstTime
                          ? l10n.t('setVaultPassphrase')
                          : l10n.t('unlockYourVault'),
                      style: AppText.title.copyWith(color: palette.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.isFirstTime
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
                textInputAction: widget.isFirstTime
                    ? TextInputAction.next
                    : TextInputAction.done,
                onSubmitted: widget.isFirstTime ? null : (_) => _submit(),
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
              if (widget.isFirstTime) ...[
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
                      : Text(widget.isFirstTime
                          ? l10n.t('createVault')
                          : l10n.t('unlockVault')),
                ),
              ),
              if (!widget.isFirstTime) ...[
                const SizedBox(height: 8),
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
