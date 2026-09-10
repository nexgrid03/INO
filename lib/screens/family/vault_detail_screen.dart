import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, RealtimeChannel;

import '../../data/family_vault_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../core/perf/image_decode.dart';
import '../../models/family_vault_models.dart';
import '../../models/vault_share_field.dart';
import '../../services/auth_service.dart';
import '../../services/family_vault_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/common/liquid_glass.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import '../shell/shell_controller.dart';
import 'add_vault_document_sheet.dart';
import 'family_vault_screen.dart' show VaultRoleBadge;
import 'invite_member_sheet.dart';
import '../../widgets/common/ino_loader.dart';
import '../../widgets/wallet/wallet_grid.dart' show localizedWalletName;

/// One Family Vault: members, their roles, and (for owners/admins) invitations.
///
/// Owner/admin can invite by email/phone, change a member's role, remove a
/// member, cancel/resend invitations, and — owner only — transfer ownership.
/// Any non-owner member can leave. Every mutation is enforced server-side by
/// the RPCs (see the 20260731 migration); the UI only gates what it shows.
class VaultDetailScreen extends StatefulWidget {
  const VaultDetailScreen({
    super.key,
    required this.summary,
    this.openInviteOnStart = false,
  });

  final VaultSummary summary;

  /// Opens the invite sheet as soon as the screen is up - used right after
  /// creating a family, whose whole point is to put people in it.
  final bool openInviteOnStart;

  @override
  State<VaultDetailScreen> createState() => _VaultDetailScreenState();
}

class _VaultDetailScreenState extends State<VaultDetailScreen> {
  final _repo = FamilyVaultRepository.instance;
  final _store = FamilyVaultStore.instance;

  VaultRole _myRole = VaultRole.viewer;
  late String _vaultName = widget.summary.vault.name;

  List<VaultMember> _members = const [];
  List<VaultInvitation> _invitations = const [];
  List<VaultAuditEntry> _audit = const [];
  List<VaultDocument> _documents = const [];
  String? _selectedDocWallet;
  bool _loading = true;
  bool _invitesLoading = false;
  bool _auditLoading = false;
  bool _docsLoading = false;
  bool _walletSwitchBusy = false;
  String? _error;

  /// Search text applied to the members + invitations lists.
  String _query = '';
  bool _showSearch = false;

  /// Live updates for this vault's members + invitations, with a short debounce.
  RealtimeChannel? _channel;
  Timer? _debounce;

  String get _vaultId => widget.summary.vault.id;
  String? get _currentUid => Supabase.instance.client.auth.currentUser?.id;

  /// The PRIMARY owner (family_vaults.owner_auth_user_id). Several members can
  /// hold the owner role, but only this one may delete the vault or hand the
  /// primary role on, and nobody can strip their owner role.
  late String _primaryOwnerId = widget.summary.vault.ownerAuthUserId;
  bool get _isPrimaryOwner => _currentUid == _primaryOwnerId;

  @override
  void initState() {
    super.initState();
    _myRole = widget.summary.myRole;
    _refresh();
    _startRealtime();
    if (widget.openInviteOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _invite();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final ch = _channel;
    if (ch != null) _repo.unwatch(ch);
    super.dispose();
  }

  void _startRealtime() {
    _channel = _repo.watchVault(_vaultId, () {
      // Debounce a burst of row changes into a single refresh. Matches the
      // store's window: under membership churn this screen refreshes at most
      // ~once a second instead of once per row event.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) _refresh();
      });
    });
  }

  Future<void> _refresh() async {
    await _loadMembers();
    // Documents load for EVERY role - being able to see the family's shared
    // documents is the point of joining, not an admin privilege.
    await _loadDocuments();
    // Activity timeline is part of the Figma layout for every role; the RPC
    // still enforces who may read the audit log.
    await _loadAudit();
    if (_myRole.canManageMembers) {
      await _loadInvitations();
    }
  }

  /// What this user may see in the list.
  ///
  /// Once the 20260909 migration is applied the server already withholds hidden
  /// rows from plain members, so this is defence in depth rather than the
  /// gate — but it has to include the two cases the server also includes, or a
  /// contributor would lose sight of the document they just switched off and
  /// have no way to switch it back on.
  List<VaultDocument> get _effectiveDocuments {
    if (_myRole.canManageMembers) return _documents;
    final uid = _currentUid;
    return _documents
        .where((d) => d.isVisibleToMembers || (uid != null && d.sharedBy == uid))
        .toList();
  }

  /// The wallet group a shared document belongs to, normalised the same way
  /// everywhere: the filter pills, the group switch and the server RPC.
  static String walletOf(VaultDocument d) =>
      d.sourceTable ??
      (d.category?.contains('Wallet') == true ? d.category! : null) ??
      'Document Wallet';

  static bool _sameWallet(String a, String b) {
    String norm(String s) =>
        s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
    return norm(a) == norm(b);
  }

  /// The documents in the wallet the user is currently filtered to (all of them
  /// when the filter is "All") that this user is allowed to switch.
  List<VaultDocument> get _switchableInView {
    final uid = _currentUid;
    return _effectiveDocuments.where((d) {
      if (!(_myRole.canManageMembers || (uid != null && d.sharedBy == uid))) {
        return false;
      }
      final filter = _selectedDocWallet;
      return filter == null || _sameWallet(walletOf(d), filter);
    }).toList();
  }

  /// Total size of vault documents for the hero subtitle (no fake GB).
  String get _storageLabel {
    final total = _effectiveDocuments.fold<int>(0, (sum, d) => sum + (d.sizeBytes ?? 0));
    if (total <= 0) return '';
    final l10n = AppLocalizations.of(context);
    String used(String size) => l10n.t('storageUsed').replaceAll('{size}', size);
    if (total >= 1024 * 1024 * 1024) {
      return used('${(total / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB');
    }
    if (total >= 1024 * 1024) {
      return used('${(total / (1024 * 1024)).toStringAsFixed(1)} MB');
    }
    return used('${(total / 1024).round()} KB');
  }

  Future<void> _toggleDocVisibility(VaultDocument doc, bool isVisible) async {
    final l10n = AppLocalizations.of(context);
    // Optimistic: the switch has to move under the thumb. _loadDocuments()
    // below replaces this with what the server actually stored.
    setState(() {
      _documents = [
        for (final d in _documents)
          d.id == doc.id ? d.copyWith(hiddenColumn: !isVisible) : d,
      ];
    });
    try {
      await _repo.updateDocumentVisibility(doc.id, isVisible);
      await _loadDocuments();
      if (!mounted) return;
      _toast(isVisible ? l10n.t('documentNowVisible') : l10n.t('documentNowHidden'));
    } catch (e) {
      debugPrint('[FamilyVault] toggleDocVisibility failed: $e');
      await _loadDocuments();
      if (mounted) _toast(l10n.t('couldNotUpdateVisibility'), error: true);
    }
  }

  /// The switch at the top of a wallet: show or hide everything in it at once.
  Future<void> _toggleWalletVisibility(bool isVisible) async {
    final l10n = AppLocalizations.of(context);
    final wallet = _selectedDocWallet;
    // Snapshot the ids ONCE. _switchableInView reads _documents, which the
    // optimistic update below replaces — evaluating it inside the loop would
    // both re-scan per row and read a list that is mid-swap.
    final targetIds = {
      for (final d in _switchableInView)
        if (d.isVisibleToMembers != isVisible) d.id,
    };
    if (targetIds.isEmpty) return;

    setState(() {
      _walletSwitchBusy = true;
      // Same optimistic move as the per-document switch, for the same reason.
      _documents = [
        for (final d in _documents)
          targetIds.contains(d.id)
              ? d.copyWith(hiddenColumn: !isVisible)
              : d,
      ];
    });

    try {
      final changed =
          await _repo.setWalletVisibility(_vaultId, wallet, isVisible);
      await _loadDocuments();
      if (!mounted) return;
      _toast(
        (isVisible ? l10n.t('walletNowVisible') : l10n.t('walletNowHidden'))
            .replaceAll('{n}', '$changed'),
      );
    } catch (e) {
      debugPrint('[FamilyVault] toggleWalletVisibility failed: $e');
      await _loadDocuments();
      if (mounted) _toast(l10n.t('couldNotUpdateVisibility'), error: true);
    } finally {
      if (mounted) setState(() => _walletSwitchBusy = false);
    }
  }

  void _openProfile() {
    ShellController.tab.value = 4;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Adds a document to this vault - either one already in a wallet, or a file
  /// uploaded from the device.
  Future<void> _addDocument() async {
    final added = await showAddVaultDocumentSheet(
      context,
      vaultId: _vaultId,
      vaultName: _vaultName,
    );
    if (!mounted || !added) return;
    await _loadDocuments();
    if (!mounted) return;
    _toast(
      AppLocalizations.of(
        context,
      ).t('addedToVault').replaceAll('{name}', _vaultName),
    );
  }

  Future<void> _showDocumentDetail(VaultDocument doc) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VaultDocumentDetailSheet(
        doc: doc,
        canRemove: doc.canBeRemovedBy(_currentUid, _myRole),
        canToggleVisibility: doc.canBeRemovedBy(_currentUid, _myRole),
        onOpenDocument: () => _openDocument(doc),
        onRemove: () => _removeDocument(doc),
        onToggleVisibility: (isVisible) =>
            _toggleDocVisibility(doc, isVisible),
      ),
    );
  }

  /// Opens a shared document in the device's default app.
  ///
  /// The bytes are fetched through the storage layer, where a policy re-checks
  /// vault membership on every read. So a member who was removed a second ago
  /// gets a clean failure here rather than a stale copy — the revocation is
  /// enforced server-side, not by hiding a button.
  Future<void> _openDocument(VaultDocument doc) async {
    final l10n = AppLocalizations.of(context);
    _toast(l10n.t('openingFile').replaceAll('{name}', doc.name));
    try {
      final dir = await getTemporaryDirectory();
      var safe = doc.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      // The extension is load-bearing: OpenFilex resolves the handler app from
      // it, so a file written without one silently fails to open. Take it from
      // the stored object path when the display name doesn't carry it.
      final ext = doc.extension;
      if (ext.isNotEmpty && !safe.toLowerCase().endsWith('.$ext')) {
        safe = '$safe.$ext';
      }
      final file = File('${dir.path}/vault_${doc.id}_$safe');
      // Streamed to disk rather than buffered: OpenFilex needs a file, so the
      // bytes never have to exist in RAM all at once.
      await _repo.downloadDocumentToFile(doc, file);
      final result = await OpenFilex.open(file.path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        _toast(l10n.t('noAppToOpenFile'), error: true);
      }
    } catch (e) {
      debugPrint('[FamilyVault] openDocument failed: $e');
      if (!mounted) return;
      // The most likely cause of a denial here is exactly the intended one.
      _toast(l10n.t('noLongerHaveAccessToDoc'), error: true);
      await _loadDocuments();
    }
  }

  Future<void> _removeDocument(VaultDocument doc) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('removeFromVaultTitle')),
        content: Text(
          l10n.t('removeFromVaultBody').replaceAll('{name}', doc.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.t('remove'),
              style: const TextStyle(color: AppColors.critical),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.removeDocument(doc.id);
      if (!mounted) return;
      setState(
        () => _documents = _documents.where((d) => d.id != doc.id).toList(),
      );
      _toast(l10n.t('removedFromVault'));
    } catch (e) {
      debugPrint('[FamilyVault] removeDocument failed: $e');
      if (!mounted) return;
      _toast(l10n.t('couldNotRemoveDocument'), error: true);
    }
  }

  Future<void> _loadDocuments() async {
    setState(() => _docsLoading = true);
    try {
      final docs = await _repo.documents(_vaultId);
      if (mounted) setState(() => _documents = docs);
    } catch (e) {
      // Non-fatal: the roster still works. An empty list here is also what a
      // just-removed member sees, because RLS stops returning the rows.
      debugPrint('[FamilyVault] loadDocuments failed: $e');
      if (mounted) setState(() => _documents = const []);
    } finally {
      if (mounted) setState(() => _docsLoading = false);
    }
  }

  Future<void> _loadAudit() async {
    setState(() => _auditLoading = true);
    try {
      final audit = await _repo.auditLog(_vaultId, limit: 30);
      if (mounted) setState(() => _audit = audit);
    } catch (e) {
      // Non-fatal — the roster still works without the activity trail.
      debugPrint('[FamilyVault] loadAudit failed: $e');
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await _repo.members(_vaultId);
      if (!mounted) return;
      // Keep my own role in sync (e.g. after an ownership transfer).
      final me = members.where((m) => m.authUserId == _currentUid);
      setState(() {
        _members = members;
        if (me.isNotEmpty) _myRole = me.first.role;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).t('couldNotLoadMembers');
        _loading = false;
      });
    }
  }

  Future<void> _loadInvitations() async {
    setState(() => _invitesLoading = true);
    try {
      final invites = await _repo.invitationsForVault(_vaultId);
      if (mounted) setState(() => _invitations = invites);
    } catch (e) {
      // Non-fatal — the members list still works without the invite roster.
      debugPrint('[FamilyVault] loadInvitations failed: $e');
    } finally {
      if (mounted) setState(() => _invitesLoading = false);
    }
  }

  void _toast(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
      ),
    );
  }

  Future<void> _invite() async {
    final sent = await showInviteMemberSheet(context, _vaultId);
    if (sent == true && mounted) {
      _toast(AppLocalizations.of(context).t('invitationSent'));
      await _loadInvitations();
      await _loadAudit();
    }
  }

  // ---- Member actions ------------------------------------------------------

  Future<void> _memberActions(VaultMember member) async {
    final isMe = member.authUserId == _currentUid;
    final isOwnerRow = member.role == VaultRole.owner;
    final isPrimaryRow = member.authUserId == _primaryOwnerId;
    final iAmOwner = _myRole == VaultRole.owner;
    final canManage = _myRole.canManageMembers && !isOwnerRow && !isMe;
    // Any owner may add a co-owner; only an owner may demote a NON-primary
    // co-owner; only the primary owner may hand the primary role on.
    final canPromote = iAmOwner && !isOwnerRow && !isMe;
    final canDemote = iAmOwner && isOwnerRow && !isMe && !isPrimaryRow;
    final canTransfer = _isPrimaryOwner && !isMe;
    final canLeave = isMe && !isPrimaryRow;
    if (!canManage && !canPromote && !canDemote && !canTransfer && !canLeave) {
      return;
    }

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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
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
                if (canManage) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.t('changeRole'),
                        style: AppText.label.copyWith(color: palette.textFaint),
                      ),
                    ),
                  ),
                  for (final role in VaultRoleX.assignable)
                    ListTile(
                      leading: Icon(role.icon, color: role.color),
                      title: Text(role.localizedLabel(l10n)),
                      subtitle: Text(role.localizedDescription(l10n)),
                      trailing: member.role == role
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.primaryGreen,
                            )
                          : null,
                      onTap: () =>
                          Navigator.of(context).pop('role:${role.name}'),
                    ),
                ],
                if (canPromote) ...[
                  Divider(height: 1, color: palette.border),
                  ListTile(
                    leading: Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.primaryGreen,
                    ),
                    title: Text(l10n.t('makeCoOwner')),
                    subtitle: Text(l10n.t('makeCoOwnerSubtitle')),
                    onTap: () => Navigator.of(context).pop('promote'),
                  ),
                ],
                if (canDemote) ...[
                  Divider(height: 1, color: palette.border),
                  ListTile(
                    leading: const Icon(
                      Icons.remove_moderator_rounded,
                      color: AppColors.warning,
                    ),
                    title: Text(l10n.t('removeOwnerRole')),
                    subtitle: Text(l10n.t('removeOwnerRoleSubtitle')),
                    onTap: () => Navigator.of(context).pop('demote'),
                  ),
                ],
                if (canTransfer) ...[
                  Divider(height: 1, color: palette.border),
                  ListTile(
                    leading: Icon(
                      Icons.swap_horiz_rounded,
                      color: AppColors.primaryGreen,
                    ),
                    title: Text(l10n.t('transferPrimaryOwnership')),
                    subtitle: Text(l10n.t('transferOwnershipSubtitle')),
                    onTap: () => Navigator.of(context).pop('transfer'),
                  ),
                ],
                if (canManage) ...[
                  Divider(height: 1, color: palette.border),
                  ListTile(
                    leading: const Icon(
                      Icons.person_remove_rounded,
                      color: AppColors.critical,
                    ),
                    title: Text(
                      l10n.t('removeFromVault'),
                      style: const TextStyle(color: AppColors.critical),
                    ),
                    onTap: () => Navigator.of(context).pop('remove'),
                  ),
                ],
                if (canLeave)
                  ListTile(
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.critical,
                    ),
                    title: Text(
                      l10n.t('leaveVault'),
                      style: const TextStyle(color: AppColors.critical),
                    ),
                    onTap: () => Navigator.of(context).pop('leave'),
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'transfer') {
      await _transferOwnership(member);
      return;
    }
    if (action == 'leave') {
      await _leave(member);
      return;
    }
    if (action == 'promote' || action == 'demote') {
      try {
        if (action == 'promote') {
          await _repo.promoteToOwner(member.id);
          _toast(l10n
              .t('memberIsNowCoOwner')
              .replaceAll('{name}', member.localizedLabel(l10n)));
        } else {
          await _repo.updateMemberRole(member.id, VaultRole.admin);
          _toast(l10n
              .t('memberRoleChanged')
              .replaceAll('{name}', member.localizedLabel(l10n))
              .replaceAll('{role}', VaultRole.admin.localizedLabel(l10n)));
        }
        await _loadMembers();
        await _loadAudit();
        await _store.reload();
      } catch (e) {
        debugPrint('[FamilyVault] owner role change failed: $e');
        if (mounted) _toast(l10n.t('couldNotUpdateOwnerRole'), error: true);
      }
      return;
    }
    try {
      if (action == 'remove') {
        await _repo.removeMember(member.id);
        _toast(
          l10n
              .t('memberRemovedNamed')
              .replaceAll('{name}', member.localizedLabel(l10n)),
        );
      } else if (action.startsWith('role:')) {
        final role = VaultRoleX.fromName(action.substring(5));
        if (role == member.role) return;
        await _repo.updateMemberRole(member.id, role);
        _toast(
          l10n
              .t('memberRoleChanged')
              .replaceAll('{name}', member.localizedLabel(l10n))
              .replaceAll('{role}', role.localizedLabel(l10n)),
        );
      }
      await _loadMembers();
      await _loadAudit();
    } catch (e) {
      if (mounted) _toast(l10n.t('couldNotUpdateMember'), error: true);
    }
  }

  Future<void> _transferOwnership(VaultMember member) async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(l10n.t('transferOwnershipTitle')),
        content: Text(
          l10n
              .t('transferOwnershipBody')
              .replaceAll('{name}', member.localizedLabel(l10n))
              .replaceAll('{vault}', _vaultName),
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.t('transfer'),
              style: TextStyle(color: AppColors.primaryGreen),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.transferOwnership(_vaultId, member.authUserId);
      _primaryOwnerId = member.authUserId;
      _toast(
        l10n
            .t('memberIsNowOwner')
            .replaceAll('{name}', member.localizedLabel(l10n)),
      );
      await _loadMembers();
      await _loadAudit();
      await _store.reload(); // list roles changed
    } catch (e) {
      if (mounted) _toast(l10n.t('couldNotTransferOwnership'), error: true);
    }
  }

  Future<void> _leave(VaultMember me) async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(l10n.t('leaveVaultTitle')),
        content: Text(
          l10n.t('leaveVaultBody').replaceAll('{name}', _vaultName),
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.t('leave'),
              style: const TextStyle(color: AppColors.critical),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.removeMember(me.id);
      await _store.reload();
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) _toast(l10n.t('couldNotLeaveVault'), error: true);
    }
  }

  // ---- Invitation actions --------------------------------------------------

  Future<void> _inviteActions(VaultInvitation inv) async {
    if (!_myRole.canManageMembers) return;
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
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
                if (inv.isPending) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.t('changeRole'),
                        style: AppText.label.copyWith(color: palette.textFaint),
                      ),
                    ),
                  ),
                  for (final role in VaultRoleX.assignable)
                    ListTile(
                      leading: Icon(role.icon, color: role.color),
                      title: Text(role.localizedLabel(l10n)),
                      trailing: inv.role == role
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.primaryGreen,
                            )
                          : null,
                      onTap: () =>
                          Navigator.of(context).pop('role:${role.name}'),
                    ),
                  Divider(height: 1, color: palette.border),
                  ListTile(
                    leading: const Icon(
                      Icons.cancel_rounded,
                      color: AppColors.critical,
                    ),
                    title: Text(
                      l10n.t('cancelInvitation'),
                      style: const TextStyle(color: AppColors.critical),
                    ),
                    onTap: () => Navigator.of(context).pop('cancel'),
                  ),
                ] else
                  ListTile(
                    leading: Icon(
                      Icons.refresh_rounded,
                      color: AppColors.primaryGreen,
                    ),
                    title: Text(l10n.t('resendInvitation')),
                    subtitle: Text(
                      l10n
                          .t('resendInvitationTo')
                          .replaceAll('{target}', inv.target),
                    ),
                    onTap: () => Navigator.of(context).pop('resend'),
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'cancel') {
        await _repo.cancelInvitation(inv.id);
        _toast(l10n.t('invitationCancelled'));
      } else if (action == 'resend') {
        await _repo.resendInvitation(inv.id);
        _toast(l10n.t('invitationResent'));
      } else if (action.startsWith('role:')) {
        final role = VaultRoleX.fromName(action.substring(5));
        await _repo.resendInvitation(inv.id, role: role);
        _toast(
          l10n
              .t('invitationRoleUpdated')
              .replaceAll('{role}', role.localizedLabel(l10n)),
        );
      }
      await _loadInvitations();
      await _loadAudit();
    } catch (e) {
      if (mounted) _toast(l10n.t('couldNotUpdateInvitation'), error: true);
    }
  }

  // ---- Vault owner actions -------------------------------------------------

  Future<void> _renameVault() async {
    final controller = TextEditingController(text: _vaultName);
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(l10n.t('renameVault')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: l10n.t('vaultName')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(
              l10n.t('save'),
              style: TextStyle(color: AppColors.primaryGreen),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == _vaultName || !mounted) return;
    try {
      await _store.rename(_vaultId, name);
      if (mounted) setState(() => _vaultName = name);
      await _loadAudit();
    } catch (e) {
      if (mounted) _toast(l10n.t('couldNotRenameVault'), error: true);
    }
  }

  Future<void> _deleteVault() async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(l10n.t('deleteVaultTitle')),
        content: Text(
          l10n.t('deleteVaultBody').replaceAll('{name}', _vaultName),
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.t('delete'),
              style: const TextStyle(color: AppColors.critical),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _store.delete(_vaultId);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) _toast(l10n.t('couldNotDeleteVault'), error: true);
    }
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final launcher = divineGlassEnabled(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        sky: launcher,
        child: SafeArea(
          top: !launcher,
          bottom: false,
          child: Column(
            children: [
              _header(palette),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primaryGreen,
                  onRefresh: _refresh,
                  child: _loading
                      ? const Center(child: InoLoader())
                      : _error != null
                      ? _errorBody(palette)
                      : _body(palette),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBody(AppPalette palette) => ListView(
    children: [
      const SizedBox(height: 120),
      Icon(Icons.cloud_off_rounded, size: 48, color: palette.textFaint),
      const SizedBox(height: AppSpacing.sm),
      Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: palette.textSecondary),
        ),
      ),
    ],
  );

  Widget _body(AppPalette palette) {
    final l10n = AppLocalizations.of(context);
    final pendingCount = _invitations.where((i) => i.isPending).length;
    final members = _members.where((m) => m.matches(_query)).toList();
    final invitations = _invitations.where((i) => i.matches(_query)).toList();
    final storage = _storageLabel;
    final subtitle = [
      _members.length == 1
          ? l10n.t('sharedWithOneMember')
          : l10n
                .t('sharedWithMembers')
                .replaceAll('{count}', '${_members.length}'),
      if (storage.isNotEmpty) storage,
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        AppSpacing.xl * 2,
      ),
      children: [
        if (_showSearch) ...[
          _SearchField(
            hint: l10n.t('searchMembersOrInvitations'),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // Hero — Figma Family Assets card.
        AdaptiveGlassCard(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          radius: AppRadius.large,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.folder_shared_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _vaultName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 16),
              if (_myRole.canEditDocuments || _myRole.canManageMembers)
                Row(
                  children: [
                    if (_myRole.canEditDocuments)
                      Expanded(
                        child: _HeroFilledButton(
                          icon: Icons.folder_shared_rounded,
                          label: l10n.t('shareWithFamily'),
                          onTap: _addDocument,
                        ),
                      ),
                    if (_myRole.canEditDocuments && _myRole.canManageMembers)
                      const SizedBox(width: 10),
                    if (_myRole.canManageMembers)
                      Expanded(
                        child: _HeroOutlineButton(
                          icon: Icons.ios_share_rounded,
                          label: l10n.t('share'),
                          onTap: _invite,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Vault Members.
        Row(
          children: [
            Text(
              l10n.t('vaultMembers'),
              style: AppText.title.copyWith(color: palette.textPrimary),
            ),
            const Spacer(),
            if (_myRole.canManageMembers)
              PressableScale(
                pressedScale: 0.95,
                child: GestureDetector(
                  onTap: _invite,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    l10n.t('manage'),
                    style: AppText.subtitle.copyWith(
                      color: AppColors.primaryGreen,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (members.isEmpty)
          _NoMatches(palette: palette, message: l10n.t('noMembersMatchSearch'))
        else
          AdaptiveGlassCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            radius: AppRadius.card,
            child: Column(
              children: [
                for (var i = 0; i < members.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: palette.border),
                  _MemberRow(
                    member: members[i],
                    isMe: members[i].authUserId == _currentUid,
                    actionable: _canActOn(members[i]),
                    onTap: () => _memberActions(members[i]),
                  ),
                ],
              ],
            ),
          ),

        // Invitations (owner/admin only).
        if (_myRole.canManageMembers) ...[
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text(
                l10n.t('invitations'),
                style: AppText.title.copyWith(color: palette.textPrimary),
              ),
              if (pendingCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    l10n
                        .t('pendingCount')
                        .replaceAll('{count}', '$pendingCount'),
                    style: AppText.label.copyWith(
                      color: AppColors.darkGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_invitesLoading && _invitations.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: InoLoader()),
            )
          else if (invitations.isEmpty)
            AdaptiveGlassCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              radius: AppRadius.card,
              child: Row(
                children: [
                  Icon(
                    Icons.mail_outline_rounded,
                    size: 20,
                    color: palette.textFaint,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _query.isEmpty
                          ? l10n.t('noInvitationsYet')
                          : l10n
                                .t('noInvitationsMatch')
                                .replaceAll('{query}', _query),
                      style: AppText.caption.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            AdaptiveGlassCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              radius: AppRadius.card,
              child: Column(
                children: [
                  for (var i = 0; i < invitations.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: palette.border),
                    _InvitationRow(
                      invite: invitations[i],
                      onTap: () => _inviteActions(invitations[i]),
                    ),
                  ],
                ],
              ),
            ),
        ],

        // Shared documents — segregated by wallet with filter tabs.
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Text(
              l10n.t('sharedDocuments'),
              style: AppText.title.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(width: 8),
            // The count has to match the list beneath it. _documents includes
            // rows a plain member is not shown, so counting it made the badge
            // promise documents that were nowhere on screen.
            if (_effectiveDocuments.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${_effectiveDocuments.length}',
                  style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const Spacer(),
            if (_docsLoading)
              InoLoader(size: 14, color: AppColors.primaryGreen)
            else if (_myRole.canEditDocuments)
              PressableScale(
                pressedScale: 0.95,
                child: GestureDetector(
                  onTap: _addDocument,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded,
                          size: 16, color: AppColors.primaryGreen),
                      const SizedBox(width: 3),
                      Text(
                        l10n.t('shareWithFamily'),
                        style: AppText.subtitle.copyWith(
                          color: AppColors.primaryGreen,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_effectiveDocuments.isEmpty && !_docsLoading)
          AdaptiveGlassCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            radius: AppRadius.card,
            child: Text(
              _myRole.canEditDocuments
                  ? l10n.t('nothingSharedYetEditor')
                  : l10n.t('nothingSharedWithYou'),
              style: AppText.caption.copyWith(
                color: palette.textSecondary,
                height: 1.4,
              ),
            ),
          )
        else if (_effectiveDocuments.isNotEmpty) ...[
          // Wallet filter chips for shared documents
          Builder(
            builder: (context) {
              final docWallets = <String>{
                for (final d in _effectiveDocuments) walletOf(d),
              };
              if (docWallets.length <= 1) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _DocWalletFilterPill(
                        label: l10n.t('all'),
                        count: _effectiveDocuments.length,
                        selected: _selectedDocWallet == null,
                        accentColor: AppColors.primaryGreen,
                        onTap: () => setState(() => _selectedDocWallet = null),
                      ),
                      const SizedBox(width: 6),
                      for (final w in docWallets)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _DocWalletFilterPill(
                            label: localizedWalletName(l10n, w),
                            count: _effectiveDocuments
                                .where((d) => _sameWallet(walletOf(d), w))
                                .length,
                            selected: _selectedDocWallet == w,
                            accentColor: AppColors.vaultAccentFor(w),
                            onTap: () => setState(() {
                              _selectedDocWallet = _selectedDocWallet == w ? null : w;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

          // The switch at the top of the wallet. Everything the user may
          // control in the current filter, shown to the family or withheld
          // from them in one move.
          if (_switchableInView.isNotEmpty) ...[
            _WalletVisibilitySwitch(
              walletLabel: _selectedDocWallet == null
                  ? l10n.t('allSharedDocuments')
                  : localizedWalletName(l10n, _selectedDocWallet!),
              total: _switchableInView.length,
              visibleCount:
                  _switchableInView.where((d) => d.isVisibleToMembers).length,
              busy: _walletSwitchBusy,
              onChanged: _toggleWalletVisibility,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          AdaptiveGlassCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            radius: AppRadius.card,
            child: Builder(
              builder: (context) {
                final list = _selectedDocWallet == null
                    ? _effectiveDocuments
                    : _effectiveDocuments
                        .where((d) =>
                            _sameWallet(walletOf(d), _selectedDocWallet!))
                        .toList();

                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Center(
                      child: Text(
                        l10n.t('noDocumentsMatchSearch'),
                        style: AppText.caption.copyWith(color: palette.textSecondary),
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: palette.border),
                      _VaultDocRow(
                        doc: list[i],
                        canRemove: list[i].canBeRemovedBy(
                          _currentUid,
                          _myRole,
                        ),
                        // Same reach as removal: your own contributions, or
                        // anything at all if you run the vault.
                        canToggleVisibility: list[i].canBeRemovedBy(
                          _currentUid,
                          _myRole,
                        ),
                        onOpen: () => _showDocumentDetail(list[i]),
                        onRemove: () => _removeDocument(list[i]),
                        onToggleVisibility: (isVisible) =>
                            _toggleDocVisibility(list[i], isVisible),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],

        // Recent Activity timeline.
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.t('recentActivity'),
          style: AppText.title.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_auditLoading && _audit.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: InoLoader()),
          )
        else if (_audit.isEmpty)
          AdaptiveGlassCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            radius: AppRadius.card,
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 20, color: palette.textFaint),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.t('noActivityYet'),
                    style: AppText.caption.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          _ActivityTimeline(entries: _audit),

        const SizedBox(height: AppSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_rounded,
              size: 14,
              color: AppColors.primaryGreen.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 6),
            Text(
              l10n.t('aesEncryptionActive'),
              style: TextStyle(
                color: AppColors.primaryGreen.withValues(alpha: 0.85),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  bool _canActOn(VaultMember member) {
    final isMe = member.authUserId == _currentUid;
    final isOwnerRow = member.role == VaultRole.owner;
    final isPrimaryRow = member.authUserId == _primaryOwnerId;
    final iAmOwner = _myRole == VaultRole.owner;
    final canManage = _myRole.canManageMembers && !isOwnerRow && !isMe;
    final canPromote = iAmOwner && !isOwnerRow && !isMe;
    final canDemote = iAmOwner && isOwnerRow && !isMe && !isPrimaryRow;
    final canTransfer = _isPrimaryOwner && !isMe;
    final canLeave = isMe && !isPrimaryRow;
    return canManage || canPromote || canDemote || canTransfer || canLeave;
  }

  Widget _header(AppPalette palette) {
    final canOwn = _myRole.canManageVault;
    final glass = divineGlassEnabled(context);
    final l10n = AppLocalizations.of(context);
    final user = AuthService.instance.currentUser;
    final photo =
        (user?.userMetadata?['profile_photo'] as String?) ??
        (user?.userMetadata?['avatar_url'] as String?);

    final avatar = GestureDetector(
      onTap: _openProfile,
      child: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.tealMist,
        // ResizeImage: a full-resolution profile photo decoded for a 32px
        // circle evicts far cheaper entries from the image cache.
        backgroundImage: photo != null && photo.isNotEmpty
            ? ResizeImage(NetworkImage(photo), width: 96)
            : null,
        child: photo == null || photo.isEmpty
            ? Icon(
                Icons.person_rounded,
                size: 18,
                color: AppColors.primaryGreen,
              )
            : null,
      ),
    );

    final glassTrailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DivineGlassHeaderAction(
          icon: _showSearch ? Icons.close_rounded : Icons.search_rounded,
          tooltip: l10n.t('search'),
          onTap: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) _query = '';
          }),
        ),
        if (canOwn) ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: l10n.t('more'),
            padding: EdgeInsets.zero,
            offset: const Offset(0, 40),
            onSelected: (v) {
              if (v == 'rename') _renameVault();
              if (v == 'delete') _deleteVault();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'rename',
                child: Text(l10n.t('renameVault')),
              ),
              if (_isPrimaryOwner)
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    l10n.t('deleteVault'),
                    style: const TextStyle(color: AppColors.critical),
                  ),
                ),
            ],
            child: LiquidGlass(
              circle: true,
              blur: 12,
              frost: 0.9,
              shadow: false,
              padding: EdgeInsets.zero,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 4),
        avatar,
      ],
    );

    if (glass) {
      return DivineGlassAppBar(
        title: l10n.t('familyVault'),
        onBack: () => Navigator.of(context).maybePop(),
        trailing: glassTrailing,
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
          InoBackButton(
            size: 42,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.t('familyVault'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.headline.copyWith(
                color: palette.textPrimary,
                fontSize: 22,
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.t('search'),
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) _query = '';
            }),
            icon: Icon(
              _showSearch ? Icons.close_rounded : Icons.search_rounded,
              color: AppColors.primaryGreen,
            ),
          ),
          if (canOwn)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: palette.textSecondary),
              onSelected: (v) {
                if (v == 'rename') _renameVault();
                if (v == 'delete') _deleteVault();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(l10n.t('renameVault')),
                ),
                if (_isPrimaryOwner)
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      l10n.t('deleteVault'),
                      style: const TextStyle(color: AppColors.critical),
                    ),
                  ),
              ],
            ),
          avatar,
        ],
      ),
    );
  }
}

class _HeroFilledButton extends StatelessWidget {
  const _HeroFilledButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 19),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroOutlineButton extends StatelessWidget {
  const _HeroOutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryGreen, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.primaryGreen, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({required this.entries});

  final List<VaultAuditEntry> entries;

  static String _ago(AppLocalizations l10n, DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return l10n.t('justNow');
    if (d.inMinutes < 60) return '${d.inMinutes} ${l10n.t('minutesAgo')}';
    if (d.inHours < 24) return '${d.inHours} ${l10n.t('hoursAgo')}';
    if (d.inDays == 1) return l10n.t('yesterday');
    if (d.inDays < 7) return '${d.inDays} ${l10n.t('daysAgo')}';
    return '${d.inDays ~/ 7} ${l10n.t('weeksAgo')}';
  }

  static String _title(AppLocalizations l10n, VaultAuditEntry e) {
    final what = e.targetLabel?.trim() ?? '';
    String named(String key) => l10n.t(key).replaceAll('{name}', what);
    switch (e.action) {
      case 'invite_sent':
      case 'invite_resent':
        return l10n.t('auditNewMemberAdded');
      case 'invite_accepted':
        return what.isEmpty
            ? l10n.t('auditInvitationAccepted')
            : named('auditJoined');
      case 'role_changed':
        return what.isEmpty
            ? l10n.t('auditRoleUpdated')
            : named('auditRoleChangedNamed');
      case 'member_removed':
        return what.isEmpty
            ? l10n.t('auditMemberRemoved')
            : named('auditRemovedNamed');
      case 'member_left':
        return what.isEmpty
            ? l10n.t('auditMemberLeft')
            : named('auditLeftNamed');
      case 'ownership_transferred':
        return l10n.t('auditOwnershipTransferred');
      case 'owner_added':
        return l10n.t('auditOwnerAdded');
      case 'join_requested':
        return l10n.t('auditJoinRequested');
      case 'join_approved':
        return l10n.t('auditJoinApproved');
      case 'join_declined':
        return l10n.t('auditJoinDeclined');
      case 'vault_renamed':
        return l10n.t('auditVaultRenamed');
      default:
        return what.isNotEmpty ? what : e.action.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          entries[i].icon,
                          size: 14,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      if (i < entries.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: AppColors.primaryGreen.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(
                      bottom: i < entries.length - 1 ? 10 : 0,
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _title(l10n, entries[i]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.subtitle.copyWith(
                                  color: palette.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              _ago(l10n, entries[i].createdAt),
                              style: AppText.caption.copyWith(
                                color: palette.textFaint,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entries[i].summary,
                          style: AppText.caption.copyWith(
                            color: palette.textSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isMe,
    required this.actionable,
    required this.onTap,
  });

  final VaultMember member;
  final bool isMe;
  final bool actionable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: actionable ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: AppSizes.iconContainerSm,
              height: AppSizes.iconContainerSm,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: member.role.color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Text(
                member.initial,
                style: TextStyle(
                  color: member.role.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.localizedLabel(
                            AppLocalizations.of(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle.copyWith(
                            color: palette.textPrimary,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      if (isMe)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            AppLocalizations.of(context).t('youParen'),
                            style: AppText.caption.copyWith(
                              color: palette.textFaint,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (member.email?.isNotEmpty == true ||
                      member.phone?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      member.email?.isNotEmpty == true
                          ? member.email!
                          : member.phone!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: palette.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            VaultRoleBadge(role: member.role),
            if (actionable)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: palette.textFaint,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InvitationRow extends StatelessWidget {
  const _InvitationRow({required this.invite, required this.onTap});

  final VaultInvitation invite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(
              invite.email != null ? Icons.email_rounded : Icons.phone_rounded,
              size: 18,
              color: palette.textFaint,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invite.target,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(
                      color: palette.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context).t('invitedAs').replaceAll(
                      '{role}',
                      invite.role.localizedLabel(AppLocalizations.of(context)),
                    ),
                    style: AppText.caption.copyWith(
                      color: palette.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _StatusChip(status: invite.status),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: palette.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final InvitationStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        status.localizedLabel(AppLocalizations.of(context)),
        style: TextStyle(
          color: status.color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A compact search box that filters the members + invitations lists locally.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      style: AppText.body.copyWith(color: palette.textPrimary, fontSize: 14.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: AppText.body.copyWith(
          color: palette.textFaint,
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: palette.textFaint,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: palette.textFaint,
                ),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: palette.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
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
          borderSide: BorderSide(color: AppColors.primaryGreen, width: 1.4),
        ),
      ),
    );
  }
}

/// Shown when a search filters every row out of a list.
class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.palette, required this.message});

  final AppPalette palette;
  final String message;

  @override
  Widget build(BuildContext context) {
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.search_off_rounded, size: 20, color: palette.textFaint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// One shared document in the vault's list.
///
/// The remove control is shown only to someone who may actually remove it, but
/// that is presentation only — `remove_vault_document()` re-checks server-side,
/// so hiding the button is never what enforces the rule.
/// The switch at the top of a wallet in the Family Vault.
///
/// One control for "can the family see what I put in here". It reads as ON only
/// when EVERY document it covers is visible — a half-on state would claim the
/// family can see things they cannot, which is exactly the assurance this
/// switch exists to give. The mixed case says so in words instead.
class _WalletVisibilitySwitch extends StatelessWidget {
  const _WalletVisibilitySwitch({
    required this.walletLabel,
    required this.total,
    required this.visibleCount,
    required this.busy,
    required this.onChanged,
  });

  final String walletLabel;
  final int total;
  final int visibleCount;
  final bool busy;
  final ValueChanged<bool> onChanged;

  bool get _allVisible => total > 0 && visibleCount == total;
  bool get _mixed => visibleCount > 0 && visibleCount < total;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final on = _allVisible;

    final subtitle = _mixed
        ? l10n
            .t('visibleCountOfTotal')
            .replaceAll('{n}', '$visibleCount')
            .replaceAll('{total}', '$total')
        : on
            ? l10n.t('familyCanSeeThese').replaceAll('{n}', '$total')
            : l10n.t('familyCannotSeeThese').replaceAll('{n}', '$total');

    return AdaptiveGlassCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, 6, 6),
      radius: AppRadius.card,
      child: Row(
        children: [
          Icon(
            on
                ? Icons.visibility_rounded
                : _mixed
                    ? Icons.remove_red_eye_outlined
                    : Icons.visibility_off_rounded,
            size: 20,
            color: on
                ? AppColors.primaryGreen
                : _mixed
                    ? AppColors.warning
                    : palette.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n
                      .t('showToFamilySwitch')
                      .replaceAll('{wallet}', walletLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppText.caption.copyWith(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: InoLoader(size: 16),
            )
          else
            Switch.adaptive(
              value: on,
              activeTrackColor: AppColors.primaryGreen,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _VaultDocRow extends StatelessWidget {
  const _VaultDocRow({
    required this.doc,
    required this.canRemove,
    this.canToggleVisibility = false,
    required this.onOpen,
    required this.onRemove,
    this.onToggleVisibility,
  });

  final VaultDocument doc;
  final bool canRemove;
  final bool canToggleVisibility;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final ValueChanged<bool>? onToggleVisibility;

  String get _walletName => _VaultDetailScreenState.walletOf(doc);

  Color get _walletColor => AppColors.vaultAccentFor(_walletName);

  /// "Address · Nominee · Registration Number" — the fields the family can read
  /// on this share. Null when the item is a plain file with no data behind it.
  String? get _disclosedSummary {
    final data = doc.disclosedData;
    if (data == null || data.isEmpty) return null;
    final labels = [
      for (final k in data.keys.take(4)) VaultShareFields.labelFor(k),
    ];
    if (labels.isEmpty) return null;
    final more = data.length - labels.length;
    return more > 0 ? '${labels.join(' · ')} +$more' : labels.join(' · ');
  }

  IconData get _icon {
    if (doc.isImage) return Icons.image_rounded;
    if (doc.isPdf) return Icons.picture_as_pdf_rounded;
    final cat = (doc.category ?? '').toLowerCase();
    if (cat.contains('identity') || cat.contains('aadhaar') || cat.contains('pan')) {
      return Icons.badge_rounded;
    }
    if (cat.contains('property') || cat.contains('deed')) {
      return Icons.home_work_rounded;
    }
    if (cat.contains('health') || cat.contains('medical')) {
      return Icons.favorite_rounded;
    }
    if (cat.contains('insurance') || cat.contains('policy')) {
      return Icons.shield_rounded;
    }
    if (cat.contains('investment') || cat.contains('stock')) {
      return Icons.trending_up_rounded;
    }
    if (cat.contains('bank') || cat.contains('card')) {
      return Icons.account_balance_rounded;
    }
    return Icons.description_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = _walletColor;
    final walletLabel = localizedWalletName(AppLocalizations.of(context), _walletName);

    return PressableScale(
      pressedScale: 0.99,
      child: GestureDetector(
        onTap: onOpen,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(_icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            doc.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.subtitle.copyWith(
                              color: palette.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (doc.isRedacted) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              AppLocalizations.of(context).t('partialShare'),
                              style: const TextStyle(
                                color: AppColors.warning,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        if (doc.isHidden) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.critical.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppColors.critical.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Text(
                              'Hidden',
                              style: TextStyle(
                                color: AppColors.critical,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            walletLabel,
                            style: TextStyle(
                              color: color,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (doc.category != null &&
                            doc.category!.isNotEmpty &&
                            doc.category != _walletName) ...[
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '· ${doc.category}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(
                                color: palette.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                        if (doc.sizeLabel.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '· ${doc.sizeLabel}',
                            style: AppText.caption.copyWith(
                              color: palette.textFaint,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // What the contributor actually let through. A property
                    // shared with its price withheld should say so on the row —
                    // otherwise a member reads a blank field as missing data
                    // rather than a deliberate choice.
                    if (_disclosedSummary != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _disclosedSummary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: palette.textFaint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (canToggleVisibility && onToggleVisibility != null)
                IconButton(
                  onPressed: () => onToggleVisibility!(!doc.isVisibleToMembers),
                  visualDensity: VisualDensity.compact,
                  tooltip: doc.isVisibleToMembers ? 'Hide from members' : 'Show to members',
                  icon: Icon(
                    doc.isVisibleToMembers
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 19,
                    color: doc.isVisibleToMembers
                        ? AppColors.primaryGreen
                        : AppColors.critical,
                  ),
                ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  tooltip: AppLocalizations.of(context).t('removeFromVault'),
                  icon: Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 19,
                    color: palette.textSecondary,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: palette.textFaint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocWalletFilterPill extends StatelessWidget {
  const _DocWalletFilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isSelected = selected;
    return PressableScale(
      pressedScale: 0.95,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.16)
                : palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: isSelected ? accentColor : palette.border,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? accentColor : palette.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor
                      : palette.textFaint.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : palette.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal detail sheet that displays the disclosed fields and a prominent button to open the attached doc/image.
class _VaultDocumentDetailSheet extends StatelessWidget {
  const _VaultDocumentDetailSheet({
    required this.doc,
    required this.canRemove,
    required this.canToggleVisibility,
    required this.onOpenDocument,
    required this.onRemove,
    required this.onToggleVisibility,
  });

  final VaultDocument doc;
  final bool canRemove;
  final bool canToggleVisibility;
  final VoidCallback onOpenDocument;
  final VoidCallback onRemove;
  final ValueChanged<bool> onToggleVisibility;

  String get _walletName => _VaultDetailScreenState.walletOf(doc);
  Color get _walletColor => AppColors.vaultAccentFor(_walletName);

  bool get _hasFile {
    final path = doc.objectPath.toLowerCase().trim();
    if (path.isEmpty) return false;
    if (path.contains('/vault_') && path.endsWith('.json')) {
      return false;
    }
    return true;
  }

  IconData get _fileIcon {
    if (doc.isImage) return Icons.image_rounded;
    if (doc.isPdf) return Icons.picture_as_pdf_rounded;
    return Icons.description_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final color = _walletColor;
    final walletLabel = localizedWalletName(l10n, _walletName);
    final disclosed = doc.disclosedData ?? const {};

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: palette.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_fileIcon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title.copyWith(
                            color: palette.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                walletLabel,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (doc.category != null &&
                                doc.category!.isNotEmpty &&
                                doc.category != _walletName)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: palette.surfaceVariant,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: palette.border),
                                ),
                                child: Text(
                                  doc.category!,
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (doc.isRedacted)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.warning.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  l10n.t('partialShare'),
                                  style: const TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  // Attachment card with Open button
                  if (_hasFile) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(
                          color: color.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_fileIcon, color: color, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Attached ${doc.isImage ? "Image" : (doc.isPdf ? "PDF Document" : "File")}',
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (doc.extension.isNotEmpty)
                                          doc.extension.toUpperCase(),
                                        if (doc.sizeLabel.isNotEmpty)
                                          doc.sizeLabel,
                                      ].join(' · '),
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (doc.isImage) ...[
                            const SizedBox(height: 12),
                            _VaultImagePreview(
                              doc: doc,
                              onTap: () {
                                Navigator.of(context).pop();
                                onOpenDocument();
                              },
                            ),
                          ],
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              onOpenDocument();
                            },
                            icon: const Icon(Icons.open_in_new_rounded, size: 18),
                            label: Text(
                              doc.isImage ? 'View Photo' : 'Open Document',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 18, color: palette.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No document file attached (details shared directly).',
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // Disclosed Fields section
                  Text(
                    'SHARED INFORMATION',
                    style: TextStyle(
                      color: palette.textFaint,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (disclosed.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: palette.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: palette.border),
                      ),
                      child: Column(
                        children: [
                          for (var entry in disclosed.entries) ...[
                            if (entry.key != disclosed.keys.first)
                              Divider(height: 1, color: palette.border),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      VaultShareFields.labelFor(entry.key),
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 6,
                                    child: Text(
                                      _formatDisclosedValue(
                                          entry.key, entry.value),
                                      textAlign: TextAlign.end,
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: palette.border),
                      ),
                      child: Text(
                        _hasFile
                            ? 'Full document shared without additional field filters.'
                            : 'No specific data fields were shared.',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  if (canToggleVisibility || canRemove) ...[
                    Row(
                      children: [
                        if (canToggleVisibility)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onToggleVisibility(!doc.isVisibleToMembers);
                              },
                              icon: Icon(
                                doc.isVisibleToMembers
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 16,
                              ),
                              label: Text(
                                doc.isVisibleToMembers
                                    ? 'Hide from Family'
                                    : 'Show to Family',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: doc.isVisibleToMembers
                                    ? palette.textSecondary
                                    : AppColors.primaryGreen,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                ),
                              ),
                            ),
                          ),
                        if (canToggleVisibility && canRemove)
                          const SizedBox(width: 10),
                        if (canRemove)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onRemove();
                              },
                              icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                  size: 16),
                              label: Text(
                                l10n.t('remove'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.critical,
                                side: const BorderSide(
                                    color: AppColors.critical, width: 1),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDisclosedValue(String key, dynamic value) {
    if (value == null) return '—';
    final norm = key.toLowerCase().replaceAll('_', '');
    if ((norm.contains('price') ||
            norm.contains('value') ||
            norm.contains('amount') ||
            norm.contains('loan') ||
            norm.contains('emi') ||
            norm.contains('tax') ||
            norm.contains('income') ||
            norm.contains('expense') ||
            norm.contains('charge')) &&
        (value is num || (value is String && num.tryParse(value) != null))) {
      final n = value is num ? value : num.parse(value as String);
      return rupees(n);
    }
    if (norm.contains('percent') || norm.contains('share')) {
      if (value is num) return '${indianGroup(value)}%';
    }
    return VaultShareFields.describe(value) ?? value.toString();
  }
}

/// In-sheet preview for image attachments in the vault.
class _VaultImagePreview extends StatefulWidget {
  const _VaultImagePreview({required this.doc, required this.onTap});

  final VaultDocument doc;
  final VoidCallback onTap;

  @override
  State<_VaultImagePreview> createState() => _VaultImagePreviewState();
}

class _VaultImagePreviewState extends State<_VaultImagePreview> {
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final url = await FamilyVaultRepository.instance.documentUrl(widget.doc);
      if (mounted) {
        setState(() {
          _url = url;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: InoLoader(size: 20)),
      );
    }
    if (_url == null || _url!.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Image.network(
              _url!,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              // 180px of chrome must not pull a full-resolution photo into the
              // image cache — that is what evicts every other thumbnail and,
              // on a big enough source, OOMs the process.
              cacheHeight: context.decodeWidthFor(180),
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fullscreen_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Tap to view photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

