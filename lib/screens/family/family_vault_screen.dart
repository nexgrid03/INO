import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import '../../l10n/app_localizations.dart';
import '../../models/family_vault_models.dart';
import '../../services/family_vault_store.dart';
import '../../services/screen_security_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import 'join_family_sheet.dart';
import 'vault_detail_screen.dart';
import '../../widgets/common/ino_loader.dart';

/// The Family Vault home.
///
/// Two ways in, both offered up front: **Create a family** (you become the
/// owner and immediately invite people by phone / name / email) or **Join a
/// family** (look one up by name and ask its owner to let you in). Above the
/// vault list the screen surfaces everything waiting on the user: invitations
/// addressed to them, join requests they must approve (as an owner/admin),
/// and their own outgoing requests.
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
    ScreenSecurityService.instance.enable();
    _store.ensureLoaded();
    // Surface any pending invitations / join requests addressed to this user.
    _store.refreshPendingInvitations();
    _store.startRealtime();
  }

  @override
  void dispose() {
    ScreenSecurityService.instance.disable();
    super.dispose();
  }

  // ---- Invitations ---------------------------------------------------------

  Future<void> _accept(VaultInvitation inv) async {
    final l10n = AppLocalizations.of(context);
    try {
      await _store.acceptInvitation(inv.id);
      if (mounted) {
        _toastOk(
          l10n
              .t('joinedVault')
              .replaceAll('{name}', inv.vaultName ?? l10n.t('theVault')),
        );
      }
    } catch (e) {
      if (mounted) {
        _toast(l10n.t('couldNotAccept').replaceAll('{error}', _errorText(e)));
      }
    }
  }

  Future<void> _decline(VaultInvitation inv) async {
    final l10n = AppLocalizations.of(context);
    try {
      await _store.declineInvitation(inv.id);
    } catch (e) {
      if (mounted) _toast(l10n.t('couldNotDeclineInvitation'));
    }
  }

  // ---- Join requests (incoming: I decide) ----------------------------------

  Future<void> _approve(VaultJoinRequest req) async {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    // The approver picks what the newcomer may do.
    final role = await showModalBottomSheet<VaultRole>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.large),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.t('role'),
                  style: AppText.label.copyWith(color: palette.textFaint),
                ),
              ),
            ),
            for (final r in VaultRoleX.assignable)
              ListTile(
                leading: Icon(r.icon, color: r.color),
                title: Text(r.localizedLabel(l10n)),
                subtitle: Text(r.localizedDescription(l10n)),
                onTap: () => Navigator.of(context).pop(r),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (role == null || !mounted) return;
    try {
      await _store.approveJoinRequest(req.id, role);
      if (mounted) {
        _toastOk(
          l10n
              .t('joinRequestApproved')
              .replaceAll('{name}', req.requesterLabel),
        );
      }
    } catch (e) {
      if (mounted) _toast(l10n.t('couldNotApproveRequest'));
    }
  }

  Future<void> _declineRequest(VaultJoinRequest req) async {
    final l10n = AppLocalizations.of(context);
    try {
      await _store.declineJoinRequest(req.id);
    } catch (e) {
      if (mounted) _toast(l10n.t('couldNotDeclineRequest'));
    }
  }

  Future<void> _cancelRequest(VaultJoinRequest req) async {
    final l10n = AppLocalizations.of(context);
    try {
      await _store.cancelJoinRequest(req.id);
    } catch (e) {
      if (mounted) _toast(l10n.t('couldNotCancelRequest'));
    }
  }

  // ---- Create / join -------------------------------------------------------

  /// The two-option chooser behind the "+" button and the empty state.
  Future<void> _chooseAction() async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.large),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
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
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.t('familyVaultChoose'),
                style: AppText.title.copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: AppSpacing.md),
              _ChoiceCard(
                icon: Icons.add_home_rounded,
                title: l10n.t('createAFamily'),
                subtitle: l10n.t('createAFamilyDesc'),
                onTap: () => Navigator.of(context).pop('create'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ChoiceCard(
                icon: Icons.group_add_rounded,
                title: l10n.t('joinAFamily'),
                subtitle: l10n.t('joinAFamilyDesc'),
                onTap: () => Navigator.of(context).pop('join'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'create') await _create();
    if (action == 'join') await _join();
  }

  Future<void> _join() async {
    final l10n = AppLocalizations.of(context);
    final req = await showJoinFamilySheet(context);
    if (req == null || !mounted) return;
    _toastOk(l10n.t('joinRequestSent'));
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.large),
        ),
      ),
      builder: (_) => const _CreateVaultSheet(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final vault = await _store.create(name.trim());
      if (!mounted) return;
      // Straight into the new vault, with the invite sheet already open: the
      // whole point of creating a family is to put people in it.
      final summary = VaultSummary(vault: vault, myRole: VaultRole.owner);
      final nav = Navigator.of(context);
      await nav.push(
        MaterialPageRoute(
          builder: (_) =>
              VaultDetailScreen(summary: summary, openInviteOnStart: true),
        ),
      );
    } catch (e) {
      // Surface the ACTUAL backend error instead of a generic message.
      if (mounted) {
        _toast(
          l10n.t('vaultCreationFailed').replaceAll('{error}', _errorText(e)),
        );
      }
      return;
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

  void _toastOk(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryGreen,
      ),
    );
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.critical,
      ),
    );
  }

  Widget _header(AppPalette palette) {
    final glass = divineGlassEnabled(context);
    final title = AppLocalizations.of(context).t('familyVault');
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
        builder: (context, _) => _store.isEmpty
            ? const SizedBox.shrink()
            : _AddButton(onTap: _chooseAction),
      ),
      body: InoBackground(
        sky: glass,
        child: SafeArea(
          top: !glass,
          child: Column(
            children: [
              _header(palette),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListenableBuilder(
                  listenable: _store,
                  builder: (context, _) {
                    final loading = _store.isLoading && !_store.isLoaded;
                    final failed = _store.loadError != null && _store.isEmpty;
                    if (loading) {
                      return const Center(child: InoLoader());
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
                              message: _store.loadError!,
                              onRetry: _store.reload,
                            )
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

  /// Pending cards (invites, requests) + the vault list, or the two-option
  /// empty state when the user is in no family yet.
  Widget _list(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    final vaults = _store.vaults;
    final invites = _store.pendingInvites;
    final incoming = _store.incomingJoinRequests;
    final outgoing = _store.myJoinRequests;

    final pending = <Widget>[
      for (final inv in invites)
        _InviteCard(
          invite: inv,
          onAccept: () => _accept(inv),
          onDecline: () => _decline(inv),
        ),
      for (final req in incoming)
        _JoinRequestCard(
          request: req,
          onApprove: () => _approve(req),
          onDecline: () => _declineRequest(req),
        ),
      for (final req in outgoing)
        _OutgoingRequestCard(
          request: req,
          onCancel: () => _cancelRequest(req),
        ),
    ];

    if (vaults.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.xs,
          AppSpacing.screen,
          AppSpacing.xl * 2,
        ),
        children: [
          for (final w in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: w,
            ),
          _EmptyState(onCreate: _create, onJoin: _join),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.xs,
        AppSpacing.screen,
        AppSpacing.xl * 2,
      ),
      itemCount: pending.length + (pending.isEmpty ? 0 : 1) + vaults.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      // No FadeSlideIn: recycled rows replay the entrance every time they
      // scroll back into view.
      itemBuilder: (context, i) {
        if (i < pending.length) return pending[i];
        if (pending.isNotEmpty && i == pending.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              l10n.t('yourFamilies'),
              style: AppText.title.copyWith(color: palette.textPrimary),
            ),
          );
        }
        final v = vaults[i - pending.length - (pending.isEmpty ? 0 : 1)];
        return _VaultCard(
          summary: v,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VaultDetailScreen(summary: v)),
          ),
        );
      },
    );
  }
}

/// One of the two entry options (create / join).
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: AppSizes.iconContainer,
                height: AppSizes.iconContainer,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.chip + 2),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppText.caption.copyWith(
                        color: palette.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: palette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pending card frame shared by invitations and join requests.
class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.icon,
    required this.title,
    required this.details,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String details;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.tealPale.withValues(alpha: 0.9),
          width: 1.2,
        ),
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
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (secondaryLabel != null) ...[
                Expanded(
                  child: PressableScale(
                    child: GestureDetector(
                      onTap: onSecondary,
                      child: Container(
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppRadius.button),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          secondaryLabel!,
                          style: AppText.subtitle.copyWith(
                            color: palette.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: PressableScale(
                  child: GestureDetector(
                    onTap: onPrimary,
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                      child: Text(
                        primaryLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
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
    final l10n = AppLocalizations.of(context);
    final by = invite.invitedByName;
    final details = [
      invite.vaultName ?? l10n.t('familyVault'),
      l10n.t('asRoleLabel').replaceAll('{role}', invite.role.localizedLabel(l10n)),
      if (by != null) l10n.t('byName').replaceAll('{name}', by),
    ].join(' · ');
    return _PendingCard(
      icon: Icons.mark_email_unread_rounded,
      title: l10n.t('youveBeenInvited'),
      details: details,
      primaryLabel: l10n.t('accept'),
      onPrimary: onAccept,
      secondaryLabel: l10n.t('decline'),
      onSecondary: onDecline,
    );
  }
}

/// Someone asked to join a family this user owns/administers.
class _JoinRequestCard extends StatelessWidget {
  const _JoinRequestCard({
    required this.request,
    required this.onApprove,
    required this.onDecline,
  });

  final VaultJoinRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final contact = [
      if ((request.requesterEmail ?? '').isNotEmpty) request.requesterEmail!,
      if ((request.requesterPhone ?? '').isNotEmpty) request.requesterPhone!,
    ].join(' · ');
    return _PendingCard(
      icon: Icons.person_add_alt_1_rounded,
      title: l10n
          .t('wantsToJoin')
          .replaceAll('{name}', request.requesterLabel)
          .replaceAll('{vault}', request.vaultName ?? l10n.t('familyVault')),
      details: contact.isEmpty ? l10n.t('joinRequests') : contact,
      primaryLabel: l10n.t('approve'),
      onPrimary: onApprove,
      secondaryLabel: l10n.t('decline'),
      onSecondary: onDecline,
    );
  }
}

/// This user's own request, still waiting on the family's owner.
class _OutgoingRequestCard extends StatelessWidget {
  const _OutgoingRequestCard({
    required this.request,
    required this.onCancel,
  });

  final VaultJoinRequest request;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _PendingCard(
      icon: Icons.hourglass_top_rounded,
      title: request.vaultName ?? l10n.t('familyVault'),
      details: l10n
          .t('waitingForOwner')
          .replaceAll('{name}', request.vaultName ?? l10n.t('theVault')),
      primaryLabel: l10n.t('cancelRequest'),
      onPrimary: onCancel,
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
        subtitle: summary.myRole.localizedLabel(AppLocalizations.of(context)),
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
                color: AppColors.tealPale.withValues(alpha: 0.7),
              ),
            ),
            child: Icon(
              Icons.family_restroom_rounded,
              color: AppColors.primaryGreen,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.vault.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(
                    color: palette.textPrimary,
                    fontSize: 15.5,
                  ),
                ),
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
          Text(
            role.localizedLabel(AppLocalizations.of(context)),
            style: TextStyle(
              color: role.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
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
      () => setState(() => _valid = _controller.text.trim().isNotEmpty),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
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
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.t('createAFamily'),
            style: AppText.title.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.t('createVaultSubtitle'),
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
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
              hintText: l10n.t('vaultNameHint'),
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
                borderSide: BorderSide(
                  color: AppColors.primaryGreen,
                  width: 1.6,
                ),
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
                  child: Center(
                    child: Text(
                      l10n.t('createVault'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
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

/// No family yet: the two ways in, side by side.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate, required this.onJoin});

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.large),
              border: Border.all(
                color: AppColors.tealPale.withValues(alpha: 0.6),
              ),
              boxShadow: AppShadows.floating,
            ),
            child: Icon(
              Icons.family_restroom_rounded,
              color: AppColors.primaryGreen,
              size: 52,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.t('noFamilyVaultsYet'),
            style: AppText.title.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.t('noFamilyVaultsBody'),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ChoiceCard(
            icon: Icons.add_home_rounded,
            title: l10n.t('createAFamily'),
            subtitle: l10n.t('createAFamilyDesc'),
            onTap: onCreate,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ChoiceCard(
            icon: Icons.group_add_rounded,
            title: l10n.t('joinAFamily'),
            subtitle: l10n.t('joinAFamilyDesc'),
            onTap: onJoin,
          ),
        ],
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
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 56,
                    color: palette.textFaint,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    AppLocalizations.of(context).t('couldNotLoadVaults'),
                    style: AppText.title.copyWith(color: palette.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(
                      color: palette.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PressableScale(
                    child: GestureDetector(
                      onTap: onRetry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.refresh_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              AppLocalizations.of(context).t('tryAgain'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
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

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 15,
          ),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context).t('createOrJoin'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
