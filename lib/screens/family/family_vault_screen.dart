import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import '../../models/family_vault_models.dart';
import '../../services/family_vault_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import 'vault_detail_screen.dart';

/// The Family Vault home: the vaults the user belongs to, with a Create action.
/// A vault is a shared space owned by one member; tapping one opens its members.
class FamilyVaultScreen extends StatefulWidget {
  const FamilyVaultScreen({super.key});

  @override
  State<FamilyVaultScreen> createState() => _FamilyVaultScreenState();
}

class _FamilyVaultScreenState extends State<FamilyVaultScreen> {
  final _store = FamilyVaultStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
    // Surface any pending invitations addressed to this user (badge + cards).
    _store.refreshPendingInvitations();
    _store.startRealtime();
  }

  Future<void> _accept(VaultInvitation inv) async {
    try {
      await _store.acceptInvitation(inv.id);
      if (mounted) _toastOk('Joined ${inv.vaultName ?? 'the vault'}');
    } catch (e) {
      if (mounted) _toast('Couldn\'t accept: ${_errorText(e)}');
    }
  }

  Future<void> _decline(VaultInvitation inv) async {
    try {
      await _store.declineInvitation(inv.id);
    } catch (e) {
      if (mounted) _toast('Couldn\'t decline the invitation.');
    }
  }

  void _toastOk(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.primaryGreen,
    ));
  }

  Future<void> _create() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (_) => const _CreateVaultSheet(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final vault = await _store.create(name.trim());
      if (!mounted) return;
      // Drop straight into the new vault so the owner can start inviting.
      final summary = VaultSummary(vault: vault, myRole: VaultRole.owner);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VaultDetailScreen(summary: summary)),
      );
    } catch (e) {
      // Surface the ACTUAL backend error instead of a generic message.
      if (mounted) _toast('Vault creation failed: ${_errorText(e)}');
    }
  }

  /// The human-readable cause from a Supabase error (falls back to the raw
  /// error text) so the snackbar tells the user what actually went wrong.
  String _errorText(Object e) {
    if (e is PostgrestException) {
      return e.message + (e.code != null ? ' (${e.code})' : '');
    }
    if (e is AuthException) return e.message;
    return e.toString();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.critical,
    ));
  }

  Widget _header(AppPalette palette) {
    final glass = divineGlassEnabled(context);
    final title = 'Family Vault';
    if (glass) {
      return DivineGlassAppBar(
        title: title,
        onBack: () => Navigator.of(context).maybePop(),
        centerTitle: false,
        includeStatusBar: true,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md,
        AppSpacing.screen,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          InoBackButton(onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.headline.copyWith(
                color: palette.textPrimary,
                fontSize: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final glass = divineGlassEnabled(context);
    return Scaffold(
      backgroundColor: palette.bg,
      floatingActionButton: ListenableBuilder(
        listenable: _store,
        builder: (context, _) =>
            _store.isEmpty ? const SizedBox.shrink() : _CreateButton(onTap: _create),
      ),
      body: InoBackground(
        sky: glass,
        child: SafeArea(
          top: !glass,
          child: Column(
            children: [
              _header(palette),
              const SizedBox(height: AppSpacing.md),
              // Pending invitations addressed to this user — shown above the
              // vault list (and even when the user has no vaults yet).
              ListenableBuilder(
                listenable: _store,
                builder: (context, _) => _PendingInvites(
                  invites: _store.pendingInvites,
                  onAccept: _accept,
                  onDecline: _decline,
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _store,
                  builder: (context, _) {
                    final loading = _store.isLoading && !_store.isLoaded;
                    final failed = _store.loadError != null && _store.isEmpty;
                    if (loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    Future<void> refreshAll() async {
                      await _store.reload();
                      await _store.refreshPendingInvitations();
                    }

                    return RefreshIndicator(
                      color: AppColors.primaryGreen,
                      onRefresh: refreshAll,
                      child: failed
                          ? _ErrorState(
                            message: _store.loadError!, onRetry: _store.reload)
                        : _store.isEmpty
                            ? _EmptyState(onCreate: _create)
                            : _list(palette),
                  );
                },
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _list(AppPalette palette) {
    final vaults = _store.vaults;
    return ListView.separated(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xl * 2),
      itemCount: vaults.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => FadeSlideIn(
        delay: Duration(milliseconds: (i * 40).clamp(0, 240)),
        child: _VaultCard(
          summary: vaults[i],
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => VaultDetailScreen(summary: vaults[i]),
          )),
        ),
      ),
    );
  }
}

/// The "you've been invited" cards shown at the top of the Family Vault screen.
/// Renders nothing when there are no pending invitations.
class _PendingInvites extends StatelessWidget {
  const _PendingInvites({
    required this.invites,
    required this.onAccept,
    required this.onDecline,
  });

  final List<VaultInvitation> invites;
  final ValueChanged<VaultInvitation> onAccept;
  final ValueChanged<VaultInvitation> onDecline;

  @override
  Widget build(BuildContext context) {
    if (invites.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, AppSpacing.xs, AppSpacing.screen, AppSpacing.sm),
      child: Column(
        children: [
          for (final inv in invites)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _InviteCard(
                invite: inv,
                onAccept: () => onAccept(inv),
                onDecline: () => onDecline(inv),
              ),
            ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  final VaultInvitation invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
            color: AppColors.tealPale.withValues(alpha: 0.9), width: 1.2),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: const Icon(Icons.mark_email_unread_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You\'ve been invited',
                        style: AppText.subtitle.copyWith(
                            color: palette.textPrimary, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(
                      '${invite.vaultName ?? 'Family Vault'} · as '
                      '${invite.role.label}'
                      '${invite.invitedByName != null ? ' · by ${invite.invitedByName}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption
                          .copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: PressableScale(
                  child: GestureDetector(
                    onTap: onDecline,
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palette.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppRadius.button),
                        border: Border.all(color: palette.border),
                      ),
                      child: Text('Decline',
                          style: AppText.subtitle.copyWith(
                              color: palette.textSecondary, fontSize: 14)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: PressableScale(
                  child: GestureDetector(
                    onTap: onAccept,
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                      child: const Text('Accept',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VaultCard extends StatelessWidget {
  const _VaultCard({required this.summary, required this.onTap});

  final VaultSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (divineGlassEnabled(context)) {
      return DivineGlassListRow(
        title: summary.vault.name,
        subtitle: summary.myRole.label,
        icon: Icons.family_restroom_rounded,
        accent: AppColors.primaryGreen,
        onTap: onTap,
      );
    }
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: AppSizes.iconContainer,
            height: AppSizes.iconContainer,
            decoration: BoxDecoration(
              color: AppColors.tealMist,
              borderRadius: BorderRadius.circular(AppRadius.chip + 2),
              border: Border.all(
                  color: AppColors.tealPale.withValues(alpha: 0.7)),
            ),
            child:  Icon(Icons.family_restroom_rounded,
                color: AppColors.primaryGreen, size: 26),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary.vault.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle
                        .copyWith(color: palette.textPrimary, fontSize: 15.5)),
                const SizedBox(height: 4),
                _RoleBadge(role: summary.myRole),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: palette.textFaint),
        ],
      ),
    );
  }
}

/// A small role pill (used on cards and member rows).
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final VaultRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: role.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(role.icon, size: 12, color: role.color),
          const SizedBox(width: 4),
          Text(role.label,
              style: TextStyle(
                  color: role.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Exposed so the detail screen reuses the exact same badge.
class VaultRoleBadge extends StatelessWidget {
  const VaultRoleBadge({super.key, required this.role});
  final VaultRole role;
  @override
  Widget build(BuildContext context) => _RoleBadge(role: role);
}

class _CreateVaultSheet extends StatefulWidget {
  const _CreateVaultSheet();

  @override
  State<_CreateVaultSheet> createState() => _CreateVaultSheetState();
}

class _CreateVaultSheetState extends State<_CreateVaultSheet> {
  final _controller = TextEditingController();
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(
        () => setState(() => _valid = _controller.text.trim().isNotEmpty));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
          Text('Create Family Vault',
              style: AppText.title.copyWith(color: palette.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text('You\'ll be the owner. Invite members after it\'s created.',
              style: AppText.caption.copyWith(color: palette.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (_valid) Navigator.of(context).pop(_controller.text.trim());
            },
            style: AppText.body.copyWith(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. Sharma Family',
              hintStyle: AppText.body.copyWith(color: palette.textFaint),
              filled: true,
              fillColor: palette.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                borderSide:
                    BorderSide(color: AppColors.primaryGreen, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PressableScale(
            child: GestureDetector(
              onTap: _valid
                  ? () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(_controller.text.trim());
                    }
                  : null,
              child: Opacity(
                opacity: _valid ? 1 : 0.5,
                child: Container(
                  height: AppSizes.button,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: AppShadows.glow(AppColors.primaryGreen),
                  ),
                  child: const Center(
                    child: Text('Create Vault',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      border: Border.all(
                          color: AppColors.tealPale.withValues(alpha: 0.6)),
                      boxShadow: AppShadows.floating,
                    ),
                    child:  Icon(Icons.family_restroom_rounded,
                        color: AppColors.primaryGreen, size: 52),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('No Family Vaults Yet',
                      style: AppText.title.copyWith(color: palette.textPrimary)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Create a shared vault for your family, then invite members '
                    'to view and manage documents together.',
                    textAlign: TextAlign.center,
                    style: AppText.body
                        .copyWith(color: palette.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PressableScale(
                    child: GestureDetector(
                      onTap: onCreate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          boxShadow: AppShadows.glow(AppColors.primaryGreen),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Create Family Vault',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 56, color: palette.textFaint),
                  const SizedBox(height: AppSpacing.md),
                  Text('Couldn\'t load vaults',
                      style: AppText.title.copyWith(color: palette.textPrimary)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: AppText.body
                          .copyWith(color: palette.textSecondary, height: 1.5)),
                  const SizedBox(height: AppSpacing.lg),
                  PressableScale(
                    child: GestureDetector(
                      onTap: onRetry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text('Try Again',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: 15),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.36),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: Colors.white, size: 22),
              SizedBox(width: 6),
              Text('New Vault',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}
