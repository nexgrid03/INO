import 'package:flutter/material.dart';

import '../../services/vault_crypto.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

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
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: !isFirstTime,
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

    if (widget.isFirstTime) {
      if (value.length < _minLength) {
        setState(() => _error =
            'Use at least $_minLength characters - this is the only thing '
            'protecting your credentials.');
        return;
      }
      if (value != _confirm.text) {
        setState(() => _error = 'The two entries do not match.');
        return;
      }
      if (!_acknowledged) {
        setState(() =>
            _error = 'Please confirm you understand it cannot be recovered.');
        return;
      }
    } else if (value.isEmpty) {
      setState(() => _error = 'Enter your vault passphrase.');
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
          ? 'Could not set up the vault. Check your connection and try again.'
          : 'That passphrase is not right.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;

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
                          ? 'Set a vault passphrase'
                          : 'Unlock your vault',
                      style: AppText.title.copyWith(color: palette.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.isFirstTime
                    ? 'Your passwords are encrypted on this device before they '
                        'are saved, so nobody else - not even we - can read '
                        'them. This passphrase is the key.'
                    : 'Enter your passphrase to decrypt your saved passwords.',
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
                  labelText: 'Vault passphrase',
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
                  decoration: const InputDecoration(
                    labelText: 'Confirm passphrase',
                    prefixIcon: Icon(Icons.key_rounded, size: 20),
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
                              'I understand that if I forget this passphrase, '
                              'my saved passwords cannot be recovered by '
                              'anyone.',
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
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(widget.isFirstTime
                          ? 'Create vault'
                          : 'Unlock vault'),
                ),
              ),
              if (!widget.isFirstTime) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Not now'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
