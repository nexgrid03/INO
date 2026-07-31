import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/password_models.dart';
import '../../models/wallet_models.dart' show WalletCategory;
import '../../services/password_store.dart';
import '../../services/vault_crypto.dart';
import '../../services/vault_guard.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/floating_search_bar.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet_modules/module_kit.dart';
import 'password_form_screen.dart';
import 'vault_passphrase_sheet.dart';

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

  bool _unlocked = false;
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

  /// Two gates, in order.
  ///
  /// 1. **Biometric** - proves it is the device owner. A cancelled prompt
  ///    leaves the vault closed and pops back, so the list is never built and
  ///    nothing sensitive reaches the screen.
  /// 2. **Vault passphrase** - derives the encryption key. Without it the
  ///    stored secrets are ciphertext this app genuinely cannot read, so this
  ///    is not a second lock over the same door: it is the only thing that
  ///    makes the contents legible at all.
  ///
  /// The passphrase step is skipped when the key is already in memory for this
  /// session, and degrades gracefully offline: if we cannot tell whether a
  /// passphrase exists, the vault opens read-only from the local cache rather
  /// than offering to create a second one, which would strand every secret
  /// sealed under the first.
  Future<void> _unlock() async {
    final ok = await VaultGuard.instance.ensureUnlocked(
      context,
      reason: 'Authenticate to open your Password Vault.',
      title: 'Verify your identity',
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _unlocked = false;
        _checking = false;
      });
      Navigator.of(context).maybePop();
      return;
    }

    await _ensureVaultKey();
    if (!mounted) return;
    setState(() {
      _unlocked = true;
      _checking = false;
    });
    // Now that the key is available, pull the encrypted entries down.
    unawaited(_store.reload());
  }

  /// Obtains the encryption key, prompting for the passphrase if needed.
  Future<void> _ensureVaultKey() async {
    if (VaultCrypto.instance.isUnlocked) return;

    final exists = await VaultCrypto.instance.hasPassphrase();
    if (!mounted) return;

    // Unknown (offline / signed out) - do NOT offer to create one.
    if (exists == null) return;

    await showVaultPassphraseSheet(context, isFirstTime: !exists);
  }

  List<PasswordEntry> get _visible =>
      _store.sorted.where((e) => e.matches(_query)).toList();

  Future<void> _add() async {
    final created = await Navigator.of(context).push<PasswordEntry>(
      MaterialPageRoute(builder: (_) => const PasswordFormScreen()),
    );
    if (created == null || !mounted) return;
    await showSuccessBurst(context, 'Saved to your vault');
  }

  Future<void> _edit(PasswordEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PasswordFormScreen(existing: entry),
      ),
    );
  }

  Future<void> _delete(PasswordEntry entry) async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete password?',
      message: 'The password saved as "${entry.nickname}" will be removed. '
          'This cannot be undone.',
    );
    if (!ok || !mounted) return;
    await _store.remove(entry.id);
    if (!mounted) return;
    showModuleToast(context, 'Password deleted');
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.selectionClick();
    showModuleToast(context, '$label copied');
  }

  /// Revealing a password re-checks the biometric session first - a phone left
  /// unlocked on a table shouldn't give a passer-by the plaintext.
  Future<void> _toggleReveal(PasswordEntry entry) async {
    if (_revealedId == entry.id) {
      setState(() => _revealedId = null);
      return;
    }
    final ok = await VaultGuard.instance.ensureUnlocked(
      context,
      reason: 'Authenticate to reveal this password.',
      title: 'Verify your identity',
    );
    if (!ok || !mounted) return;
    setState(() => _revealedId = entry.id);
  }

  Future<void> _openGenerator() async {
    final generated = await showPasswordGeneratorSheet(context);
    if (generated == null || !mounted) return;
    _copy('Password', generated);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Nothing renders until the gate passes.
    if (!_unlocked) {
      return Scaffold(
        backgroundColor: palette.bg,
        body: SafeArea(
          child: Center(
            child: _checking
                ? const CircularProgressIndicator(
                    strokeWidth: 2.6, color: AppColors.primaryGreen)
                : _LockedState(onRetry: _unlock),
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
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: ModuleHeader(
                    title: 'Passwords',
                    subtitle: hasAny
                        ? '${_store.count} saved · unlocked'
                        : 'Locked behind your biometrics',
                    actions: [
                      ModuleIconButton(
                        icon: Icons.auto_awesome_rounded,
                        tooltip: 'Password generator',
                        onTap: _openGenerator,
                      ),
                      ModuleIconButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Add password',
                        onTap: _add,
                      ),
                    ],
                  ),
                ),
              ),
              if (!_store.isLoaded)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: ModuleSkeleton(height: 72, count: 5),
                  ),
                )
              else if (!hasAny)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ModuleEmptyState(
                    icon: Icons.lock_rounded,
                    title: 'Vault is empty',
                    message:
                        'Save a password under a nickname only you understand. '
                        'It is encrypted on this device before it is stored, '
                        'and stays behind your biometrics.',
                    actionLabel: 'Add password',
                    onAction: _add,
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: FloatingSearchBar(
                      hint: 'Search nicknames…',
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
                          'No nickname matches this search.',
                          style: AppText.body
                              .copyWith(color: palette.textSecondary),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final entry = visible[i];
                        return FadeSlideIn(
                          delay: Duration(milliseconds: (i * 35).clamp(0, 300)),
                          offset: 10,
                          child: PasswordTile(
                            entry: entry,
                            revealed: _revealedId == entry.id,
                            onTap: () => _edit(entry),
                            onReveal: () => _toggleReveal(entry),
                            onCopyPassword: () =>
                                _copy('Password', entry.password),
                            onDelete: () => _delete(entry),
                          ),
                        );
                      },
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: hasAny
          ? GradientButton(
              label: 'Add',
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
    const color = AppColors.primaryGreen;
    return PressableScale(
      pressedScale: 0.99,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
          decoration: BoxDecoration(
            gradient: palette.cardGradient,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
            boxShadow: palette.cardShadow,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Monogram tile - the first letter of the nickname.
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
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
                    tooltip: revealed ? 'Hide password' : 'Show password',
                    icon: Icon(
                      revealed
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 19,
                      color: palette.textSecondary,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: palette.textFaint),
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
                              label: 'Copy password',
                              onTap: onCopyPassword,
                            ),
                            const SizedBox(width: 8),
                            _QuickAction(
                              icon: Icons.delete_outline_rounded,
                              label: 'Delete',
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: palette.border),
          ),
          child: Column(
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
          ),
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
    return Tooltip(
      message: '${strength.label} password',
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
  const _LockedState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.large),
              border: Border.all(
                  color: AppColors.tealPale.withValues(alpha: 0.6)),
              boxShadow: AppShadows.floating,
            ),
            child: const Icon(Icons.lock_outline_rounded,
                color: AppColors.primaryGreen, size: 40),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Vault Locked',
              style: AppText.headline
                  .copyWith(color: palette.textPrimary, fontSize: 22)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Use your biometrics to access your secure credentials.',
            textAlign: TextAlign.center,
            style: AppText.body
                .copyWith(color: palette.textSecondary, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),
          GradientButton(
            label: 'Unlock Vault',
            icon: Icons.fingerprint_rounded,
            expand: false,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}
