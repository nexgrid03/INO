import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/password_models.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../services/password_store.dart';
import '../../services/vault_crypto.dart';
import '../../services/vault_guard.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/floating_search_bar.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/common/liquid_glass.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet_modules/module_kit.dart';
import 'password_form_screen.dart';
import 'vault_passphrase_sheet.dart';
import '../../widgets/common/ino_loader.dart';

/// Why the Password Vault is closed — or [open], meaning it is not.
///
/// Only [open] renders the entry list. Everything else keeps the vault shut
/// and tells the user which specific door is in the way.
enum _VaultGate {
  /// Biometrics passed AND the encryption key is in memory.
  open,

  /// The device-owner check has not passed (or was cancelled).
  biometrics,

  /// A vault passphrase exists and has not been entered this session. The
  /// saved passwords are ciphertext until it is.
  passphrase,

  /// No vault passphrase has ever been set. One must be created before
  /// anything can be sealed, so the vault cannot be used until it is.
  setup,

  /// Could not reach the server to find out whether a passphrase exists.
  /// Deliberately NOT treated as "set one up": creating a second passphrase
  /// would overwrite the salt and strand every secret sealed under the first.
  offline,
}

/// The Password Vault, simplified: a list of NICKNAMES, nothing else.
///
/// Each entry is a decoy name the user invented plus its password - no site,
/// no username, no category. The whole screen is gated behind the app's
/// biometric [VaultGuard]: nothing is rendered until the user authenticates,
/// and a cancelled prompt returns them to the hub. Passwords are masked until
/// explicitly revealed one at a time.
class PasswordVaultScreen extends StatefulWidget {
  const PasswordVaultScreen({super.key, required this.category});

  final WalletCategory category;

  @override
  State<PasswordVaultScreen> createState() => _PasswordVaultScreenState();
}

class _PasswordVaultScreenState extends State<PasswordVaultScreen> {
  final _store = PasswordStore.instance;
  final _searchController = TextEditingController();

  String _query = '';

  /// Only one password is ever revealed at a time.
  String? _revealedId;

  /// Why the vault is currently closed — which decides what the locked screen
  /// offers, and (crucially) that it stays closed until that reason is
  /// actually resolved. Starts at [_VaultGate.biometrics] because nothing has
  /// been proven yet.
  _VaultGate _gate = _VaultGate.biometrics;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
    _store.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Two gates, in order, and **both** must pass before a single entry is
  /// built.
  ///
  /// 1. **Biometric** - proves it is the device owner. A cancelled prompt
  ///    leaves the vault closed and pops back, so the list is never built and
  ///    nothing sensitive reaches the screen.
  /// 2. **Vault passphrase** - derives the encryption key. Without it the
  ///    stored secrets are ciphertext this app genuinely cannot read, so this
  ///    is not a second lock over the same door: it is the only thing that
  ///    makes the contents legible at all.
  ///
  /// The passphrase step is skipped only when the key is already in memory for
  /// this session. Dismissing the passphrase sheet does **not** open the
  /// vault - it lands on the locked screen for whichever reason applies, which
  /// is the whole point: a vault that opens when you swipe its passphrase
  /// prompt away is not locked. The device-local cache still holds decrypted
  /// entries from an earlier session, so "open the list anyway" would have
  /// shown real passwords to someone who never entered the passphrase.
  Future<void> _unlock() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _checking = true);
    final ok = await VaultGuard.instance.ensureUnlocked(
      context,
      reason: l10n.t('authOpenPasswordVault'),
      title: l10n.t('verifyIdentity'),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _gate = _VaultGate.biometrics;
        _checking = false;
      });
      Navigator.of(context).maybePop();
      return;
    }

    final gate = await _openVaultKey();
    if (!mounted) return;
    setState(() {
      _gate = gate;
      _checking = false;
    });
    // Only now that the key is in hand can the encrypted entries be pulled
    // down and decrypted.
    if (gate == _VaultGate.open) unawaited(_store.reload());
  }

  /// Obtains the encryption key, prompting for the passphrase if needed, and
  /// reports what stands in the way when it could not.
  ///
  /// Offline is deliberately its own outcome rather than "create a passphrase":
  /// we cannot tell whether one already exists, and creating a second would
  /// overwrite the salt and strand every secret sealed under the first.
  Future<_VaultGate> _openVaultKey() async {
    if (VaultCrypto.instance.isUnlocked) return _VaultGate.open;

    final exists = await VaultCrypto.instance.hasPassphrase();
    if (!mounted || exists == null) return _VaultGate.offline;

    final unlocked = await showVaultPassphraseSheet(
      context,
      isFirstTime: !exists,
    );
    if (unlocked) return _VaultGate.open;
    // Dismissed or wrong passphrase - stay shut, and say which door it is.
    return exists ? _VaultGate.passphrase : _VaultGate.setup;
  }

  /// The write-side guard: no password is created or edited without a key.
  ///
  /// The list is only reachable while unlocked, so this is a second line of
  /// defence rather than the first - but a necessary one, because the key can
  /// be dropped mid-session (sign-out, [SessionReset], the app lock). Saving
  /// without it would write a password to `shared_preferences` in the clear
  /// that could never sync, which is exactly the outcome the vault exists to
  /// prevent. Re-prompts rather than just refusing, so the user's next step is
  /// obvious.
  Future<bool> _requireVaultKey() async {
    if (VaultCrypto.instance.isUnlocked) return true;
    final gate = await _openVaultKey();
    if (!mounted) return false;
    setState(() => _gate = gate);
    return gate == _VaultGate.open;
  }

  List<PasswordEntry> get _visible =>
      _store.sorted.where((e) => e.matches(_query)).toList();

  Future<void> _add() async {
    if (!await _requireVaultKey() || !mounted) return;
    final created = await Navigator.of(context).push<PasswordEntry>(
      MaterialPageRoute(builder: (_) => const PasswordFormScreen()),
    );
    if (created == null || !mounted) return;
    await showSuccessBurst(
      context,
      AppLocalizations.of(context).t('savedToYourVault'),
    );
  }

  Future<void> _edit(PasswordEntry entry) async {
    if (!await _requireVaultKey() || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PasswordFormScreen(existing: entry)),
    );
  }

  Future<void> _delete(PasswordEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.t('deletePasswordTitle'),
      message: l10n
          .t('deletePasswordBody')
          .replaceAll('{name}', entry.nickname),
    );
    if (!ok || !mounted) return;
    await _store.remove(entry.id);
    if (!mounted) return;
    showModuleToast(context, l10n.t('passwordDeleted'));
  }

  /// [label] must already be localized - it is shown to the user.
  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.selectionClick();
    showModuleToast(
      context,
      AppLocalizations.of(context).t('copiedLabel').replaceAll('{label}', label),
    );
  }

  /// Revealing a password re-checks the biometric session first - a phone left
  /// unlocked on a table shouldn't give a passer-by the plaintext.
  Future<void> _toggleReveal(PasswordEntry entry) async {
    if (_revealedId == entry.id) {
      setState(() => _revealedId = null);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final ok = await VaultGuard.instance.ensureUnlocked(
      context,
      reason: l10n.t('authRevealPassword'),
      title: l10n.t('verifyIdentity'),
    );
    if (!ok || !mounted) return;
    setState(() => _revealedId = entry.id);
  }

  Future<void> _openGenerator() async {
    final generated = await showPasswordGeneratorSheet(context);
    if (generated == null || !mounted) return;
    _copy(AppLocalizations.of(context).t('password'), generated);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    // Nothing renders until BOTH gates pass. `_gate` says which one is shut,
    // so the locked screen can name the real obstacle instead of always
    // offering a fingerprint the user has already given.
    if (_gate != _VaultGate.open) {
      return Scaffold(
        backgroundColor: palette.bg,
        body: SafeArea(
          child: Center(
            child: _checking
                ? InoLoader(color: AppColors.primaryGreen)
                : _LockedState(gate: _gate, onRetry: _unlock),
          ),
        ),
      );
    }

    final hasAny = _store.items.isNotEmpty;
    final visible = _visible;

    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        sky: divineGlassEnabled(context),
        child: SafeArea(
          top: !divineGlassEnabled(context),
          bottom: false,
          child: Column(
            children: [
              ModuleHeader(
                title: l10n.t('passwordsTitle'),
                subtitle: hasAny
                    ? l10n
                        .t('passwordsSavedUnlocked')
                        .replaceAll('{n}', '${_store.count}')
                    : l10n.t('lockedBehindBiometrics'),
                actions: [
                  ModuleIconButton(
                    icon: Icons.auto_awesome_rounded,
                    tooltip: l10n.t('passwordGenerator'),
                    onTap: _openGenerator,
                  ),
                  ModuleIconButton(
                    icon: Icons.add_rounded,
                    tooltip: l10n.t('addPassword'),
                    onTap: _add,
                  ),
                ],
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    if (!_store.isLoaded)
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: ModuleSkeleton(height: 72, count: 5),
                        ),
                      )
                    else if (!hasAny)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: ModuleEmptyState(
                          icon: Icons.lock_rounded,
                          title: l10n.t('vaultIsEmpty'),
                          message: l10n.t('vaultEmptyMessage'),
                          actionLabel: l10n.t('addPassword'),
                          onAction: _add,
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            16,
                            AppSpacing.md,
                            16,
                            12,
                          ),
                          child: FloatingSearchBar(
                            hint: l10n.t('searchNicknames'),
                            height: 48,
                            controller: _searchController,
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                      ),
                      if (visible.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                l10n.t('noNicknameMatches'),
                                style: AppText.body.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.md),
                            // No FadeSlideIn: recycled rows replay the entrance
                            // every time they scroll back into view.
                            itemBuilder: (context, i) {
                              final entry = visible[i];
                              return PasswordTile(
                                key: ValueKey(entry.id),
                                entry: entry,
                                revealed: _revealedId == entry.id,
                                onTap: () => _edit(entry),
                                onReveal: () => _toggleReveal(entry),
                                onCopyPassword: () =>
                                    _copy(l10n.t('password'), entry.password),
                                onDelete: () => _delete(entry),
                              );
                            },
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: hasAny
          ? GradientButton(
              label: l10n.t('add'),
              icon: Icons.add_rounded,
              expand: false,
              onTap: _add,
            )
          : null,
    );
  }
}

/// One saved password: monogram tile, nickname, masked dots, strength dot and
/// an expanding action row when revealed.
class PasswordTile extends StatelessWidget {
  const PasswordTile({
    super.key,
    required this.entry,
    required this.revealed,
    required this.onTap,
    required this.onReveal,
    required this.onCopyPassword,
    required this.onDelete,
  });

  final PasswordEntry entry;
  final bool revealed;
  final VoidCallback onTap;
  final VoidCallback onReveal;
  final VoidCallback onCopyPassword;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final color = AppColors.primaryGreen;
    return PressableScale(
      pressedScale: 0.99,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AdaptiveGlassCard(
          padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
          child: Column(
            children: [
              Row(
                children: [
                  // Soft round monogram — matches Document / Property list discs.
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      entry.monogram,
                      style: AppText.title.copyWith(color: color, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle.copyWith(
                            color: palette.textPrimary,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          revealed ? entry.password : '••••••••••',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: revealed
                                ? palette.textPrimary
                                : palette.textSecondary,
                            fontFamily: revealed ? 'monospace' : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StrengthDot(strength: entry.strength),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: onReveal,
                    visualDensity: VisualDensity.compact,
                    tooltip: revealed
                        ? l10n.t('hidePassword')
                        : l10n.t('showPassword'),
                    icon: Icon(
                      revealed
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 19,
                      color: palette.textSecondary,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: palette.textFaint,
                  ),
                ],
              ),
              // The revealed state also exposes the quick actions, so the
              // plaintext and the copy button appear together deliberately.
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: revealed
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10, right: 4),
                        child: Row(
                          children: [
                            _QuickAction(
                              icon: Icons.key_rounded,
                              label: l10n.t('copyPassword'),
                              onTap: onCopyPassword,
                            ),
                            const SizedBox(width: 8),
                            _QuickAction(
                              icon: Icons.delete_outline_rounded,
                              label: l10n.t('delete'),
                              onTap: onDelete,
                              danger: true,
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = danger ? AppColors.critical : AppColors.primaryGreen;
    final launcher = divineGlassEnabled(context);
    final body = Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.caption.copyWith(
            color: palette.textSecondary,
            fontSize: 10.5,
          ),
        ),
      ],
    );
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: launcher
            ? LiquidGlass(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                blur: 12,
                frost: 0.95,
                shadow: false,
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: body,
              )
            : Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: palette.border),
                ),
                child: body,
              ),
      ),
    );
  }
}

class _StrengthDot extends StatelessWidget {
  const _StrengthDot({required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n
          .t('strengthPasswordTooltip')
          .replaceAll('{strength}', passwordStrengthLabel(l10n, strength)),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: strength.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: strength.color.withValues(alpha: 0.5),
              blurRadius: 5,
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedState extends StatelessWidget {
  const _LockedState({required this.gate, required this.onRetry});

  final _VaultGate gate;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final launcher = divineGlassEnabled(context);

    // Each closed gate names its own obstacle and its own next step. Showing
    // "Unlock Vault" + a fingerprint for a missing passphrase would send the
    // user back through biometrics they have already passed.
    final (String title, String subtitle, String action, IconData icon) =
        switch (gate) {
      _VaultGate.open ||
      _VaultGate.biometrics =>
        (
          l10n.t('vaultLocked'),
          l10n.t('vaultLockedSubtitle'),
          l10n.t('unlockVault'),
          Icons.fingerprint_rounded,
        ),
      _VaultGate.passphrase => (
          l10n.t('vaultPassphraseTitle'),
          l10n.t('vaultPassphraseGateSubtitle'),
          l10n.t('enterPassphrase'),
          Icons.key_rounded,
        ),
      _VaultGate.setup => (
          l10n.t('vaultSetupTitle'),
          l10n.t('vaultSetupGateSubtitle'),
          l10n.t('setUpVault'),
          Icons.shield_moon_rounded,
        ),
      _VaultGate.offline => (
          l10n.t('vaultOfflineTitle'),
          l10n.t('vaultOfflineSubtitle'),
          l10n.t('tryAgain'),
          Icons.cloud_off_rounded,
        ),
    };

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (launcher)
            DivineGlassEmptyPanel(
              title: title,
              subtitle: subtitle,
              icon: Icons.lock_outline_rounded,
            )
          else ...[
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(AppRadius.large),
                border: Border.all(
                  color: AppColors.tealPale.withValues(alpha: 0.6),
                ),
                boxShadow: AppShadows.floating,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primaryGreen,
                size: 40,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.headline.copyWith(
                color: palette.textPrimary,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          GradientButton(
            label: action,
            icon: icon,
            expand: false,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}
