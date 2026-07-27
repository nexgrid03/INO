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
import '../wallet/wallet_detail_screen.dart';
import 'password_form_screen.dart';
import 'vault_passphrase_sheet.dart';

/// The Password Vault - a modern password manager.
///
/// The whole screen is gated behind the app's biometric [VaultGuard]: nothing
/// is rendered until the user authenticates, and a cancelled prompt returns
/// them to the hub. Inside, credentials are grouped by category, searchable,
/// and masked until explicitly revealed one at a time.
class PasswordVaultScreen extends StatefulWidget {
  const PasswordVaultScreen({super.key, required this.category});

  final WalletCategory category;

  @override
  State<PasswordVaultScreen> createState() => _PasswordVaultScreenState();
}

enum _VaultView { all, favorites, recent, weak }

extension _VaultViewX on _VaultView {
  String get label => switch (this) {
        _VaultView.all => 'All',
        _VaultView.favorites => 'Favourites',
        _VaultView.recent => 'Recent',
        _VaultView.weak => 'Weak',
      };

  IconData get icon => switch (this) {
        _VaultView.all => Icons.grid_view_rounded,
        _VaultView.favorites => Icons.star_rounded,
        _VaultView.recent => Icons.schedule_rounded,
        _VaultView.weak => Icons.gpp_maybe_rounded,
      };
}

class _PasswordVaultScreenState extends State<PasswordVaultScreen> {
  final _store = PasswordStore.instance;
  final _searchController = TextEditingController();

  String _query = '';
  _VaultView _view = _VaultView.all;
  PasswordCategory? _categoryFilter;

  /// Only one credential is ever revealed at a time.
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

  List<PasswordEntry> get _visible {
    Iterable<PasswordEntry> base = switch (_view) {
      _VaultView.all => _store.sorted,
      _VaultView.favorites => _store.sorted.where((e) => e.isFavorite),
      _VaultView.recent => _store.recentlyAdded,
      _VaultView.weak => _store.sorted.where((e) =>
          e.strength == PasswordStrength.weak ||
          e.strength == PasswordStrength.fair),
    };
    if (_categoryFilter != null) {
      base = base.where((e) => e.category == _categoryFilter);
    }
    return base.where((e) => e.matches(_query)).toList();
  }

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
      title: 'Delete credential?',
      message: 'The saved password for "${entry.title}" will be removed from '
          'this device. This cannot be undone.',
    );
    if (!ok || !mounted) return;
    await _store.remove(entry.id);
    if (!mounted) return;
    showModuleToast(context, 'Credential deleted');
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

  void _openDocuments() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalletDetailScreen(category: widget.category),
      ),
    );
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
    final categories = _store.usedCategories;

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
                        ? '${_store.count} credential${_store.count == 1 ? '' : 's'} · unlocked'
                        : 'Locked behind your biometrics',
                    actions: [
                      ModuleIconButton(
                        icon: Icons.auto_awesome_rounded,
                        tooltip: 'Password generator',
                        onTap: _openGenerator,
                      ),
                      ModuleIconButton(
                        icon: Icons.folder_shared_rounded,
                        tooltip: 'Vault documents',
                        onTap: _openDocuments,
                      ),
                      ModuleIconButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Add credential',
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
                        'Save the logins you use every day. Passwords stay on '
                        'this device, masked by default and behind your biometrics.',
                    actionLabel: 'Add credential',
                    onAction: _add,
                  ),
                )
              else ...[
                // Health strip.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: FadeSlideIn(
                      child: Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              value: '${_store.count}',
                              label: 'Saved',
                              icon: Icons.vpn_key_rounded,
                              accent: AppColors.primaryGreen,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: StatTile(
                              value: '${_store.weakCount}',
                              label: 'Weak or fair',
                              icon: Icons.gpp_maybe_rounded,
                              accent: _store.weakCount > 0
                                  ? AppColors.warning
                                  : AppColors.success,
                              onTap: () =>
                                  setState(() => _view = _VaultView.weak),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: StatTile(
                              value: '${_store.reusedCount}',
                              label: 'Reused',
                              icon: Icons.content_copy_rounded,
                              accent: _store.reusedCount > 0
                                  ? AppColors.critical
                                  : AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: FloatingSearchBar(
                      hint: 'Search passwords…',
                      height: 48,
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ModuleChipRow(
                    labels: [for (final v in _VaultView.values) v.label],
                    icons: [for (final v in _VaultView.values) v.icon],
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    selectedIndex: _VaultView.values.indexOf(_view),
                    onSelect: (i) =>
                        setState(() => _view = _VaultView.values[i]),
                  ),
                ),
                if (categories.length > 1) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          ModuleChip(
                            label: 'Every category',
                            selected: _categoryFilter == null,
                            onTap: () =>
                                setState(() => _categoryFilter = null),
                          ),
                          for (final c in categories) ...[
                            const SizedBox(width: 8),
                            ModuleChip(
                              label: c.label,
                              icon: c.icon,
                              count: _store.countIn(c),
                              accent: c.color,
                              selected: _categoryFilter == c,
                              onTap: () =>
                                  setState(() => _categoryFilter = c),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Nothing matches this view.',
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
                            onCopyUsername: entry.accountLine.isEmpty
                                ? null
                                : () => _copy('Username', entry.accountLine),
                            onFavorite: () => _store.toggleFavorite(entry.id),
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

/// One credential row: monogram tile, title, account line, strength dot and an
/// expanding action row. Matches the clean list rhythm of the reference while
/// using the app's own card surface.
class PasswordTile extends StatelessWidget {
  const PasswordTile({
    super.key,
    required this.entry,
    required this.revealed,
    required this.onTap,
    required this.onReveal,
    required this.onCopyPassword,
    required this.onFavorite,
    required this.onDelete,
    this.onCopyUsername,
  });

  final PasswordEntry entry;
  final bool revealed;
  final VoidCallback onTap;
  final VoidCallback onReveal;
  final VoidCallback onCopyPassword;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final VoidCallback? onCopyUsername;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = entry.category.color;
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
                  // Monogram tile in the category colour - the stand-in for a
                  // brand logo the app can't ship.
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.subtitle.copyWith(
                                  color: palette.textPrimary,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                            if (entry.isFavorite) ...[
                              const SizedBox(width: 5),
                              const Icon(Icons.star_rounded,
                                  size: 14, color: AppColors.warning),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          revealed
                              ? entry.password
                              : (entry.accountLine.isEmpty
                                  ? '••••••••••'
                                  : entry.accountLine),
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
              // plaintext and the copy buttons appear together deliberately.
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: revealed
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10, right: 4),
                        child: Row(
                          children: [
                            if (onCopyUsername != null) ...[
                              _QuickAction(
                                icon: Icons.person_rounded,
                                label: 'Copy user',
                                onTap: onCopyUsername!,
                              ),
                              const SizedBox(width: 8),
                            ],
                            _QuickAction(
                              icon: Icons.key_rounded,
                              label: 'Copy password',
                              onTap: onCopyPassword,
                            ),
                            const SizedBox(width: 8),
                            _QuickAction(
                              icon: entry.isFavorite
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              label: 'Favourite',
                              onTap: onFavorite,
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
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.brandGradient,
              boxShadow: AppShadows.glow(AppColors.primaryGreen, opacity: 0.28),
            ),
            child: const Icon(Icons.lock_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Vault locked',
              style: AppText.title.copyWith(color: palette.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'Authenticate to view your saved passwords.',
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          GradientButton(
            label: 'Unlock',
            icon: Icons.fingerprint_rounded,
            expand: false,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}
