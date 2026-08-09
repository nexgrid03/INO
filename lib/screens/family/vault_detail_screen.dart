import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, RealtimeChannel;

import '../../data/family_vault_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/family_vault_models.dart';
import '../../services/auth_service.dart';
import '../../services/family_vault_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
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

/// One Family Vault: members, their roles, and (for owners/admins) invitations.
///
/// Owner/admin can invite by email/phone, change a member's role, remove a
/// member, cancel/resend invitations, and — owner only — transfer ownership.
/// Any non-owner member can leave. Every mutation is enforced server-side by
/// the RPCs (see the 20260731 migration); the UI only gates what it shows.
class VaultDetailScreen extends StatefulWidget {
  const VaultDetailScreen({super.key, required this.summary});

  final VaultSummary summary;

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
  bool _loading = true;
  bool _invitesLoading = false;
  bool _auditLoading = false;
  bool _docsLoading = false;
  String? _error;

  /// Search text applied to the members + invitations lists.
  String _query = '';
  bool _showSearch = false;

  /// Live updates for this vault's members + invitations, with a short debounce.
  RealtimeChannel? _channel;
  Timer? _debounce;

  String get _vaultId => widget.summary.vault.id;
  String? get _currentUid =>
      Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _myRole = widget.summary.myRole;
    _refresh();
    _startRealtime();
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

  /// Total size of vault documents for the hero subtitle (no fake GB).
  String get _storageLabel {
    final total =
        _documents.fold<int>(0, (sum, d) => sum + (d.sizeBytes ?? 0));
    if (total <= 0) return '';
    if (total >= 1024 * 1024 * 1024) {
      return '${(total / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB used';
    }
    if (total >= 1024 * 1024) {
      return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB used';
    }
    return '${(total / 1024).round()} KB used';
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
    _toast('Added to $_vaultName');
  }

  /// Opens a shared document in the device's default app.
  ///
  /// The bytes are fetched through the storage layer, where a policy re-checks
  /// vault membership on every read. So a member who was removed a second ago
  /// gets a clean failure here rather than a stale copy — the revocation is
  /// enforced server-side, not by hiding a button.
  Future<void> _openDocument(VaultDocument doc) async {
    _toast('Opening ${doc.name}…');
    try {
      final bytes = await _repo.downloadDocument(doc);
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
      await file.writeAsBytes(bytes);
      final result = await OpenFilex.open(file.path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        _toast('No app on this device can open this file', error: true);
      }
    } catch (e) {
      debugPrint('[FamilyVault] openDocument failed: $e');
      if (!mounted) return;
      // The most likely cause of a denial here is exactly the intended one.
      _toast('You no longer have access to this document', error: true);
      await _loadDocuments();
    }
  }

  Future<void> _removeDocument(VaultDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from vault?'),
        content: Text(
          '"${doc.name}" will no longer be visible to members of this vault. '
          'Your own copy is not deleted.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove',
                style: TextStyle(color: AppColors.critical)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.removeDocument(doc.id);
      if (!mounted) return;
      setState(() =>
          _documents = _documents.where((d) => d.id != doc.id).toList());
      _toast('Removed from vault');
    } catch (e) {
      debugPrint('[FamilyVault] removeDocument failed: $e');
      if (!mounted) return;
      _toast('Could not remove that document', error: true);
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
        _error = 'Couldn\'t load members. Check your connection.';
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
    ));
  }

  Future<void> _invite() async {
    final sent = await showInviteMemberSheet(context, _vaultId);
    if (sent == true && mounted) {
      _toast('Invitation sent');
      await _loadInvitations();
      await _loadAudit();
    }
  }

  // ---- Member actions ------------------------------------------------------

  Future<void> _memberActions(VaultMember member) async {
    final isMe = member.authUserId == _currentUid;
    final isOwnerRow = member.role == VaultRole.owner;
    final canManage = _myRole.canManageMembers && !isOwnerRow && !isMe;
    final canTransfer = _myRole == VaultRole.owner && !isOwnerRow;
    final canLeave = isMe && !isOwnerRow;
    if (!canManage && !canTransfer && !canLeave) return;

    final palette = AppPalette.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
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
                    borderRadius: BorderRadius.circular(AppRadius.pill))),
            const SizedBox(height: AppSpacing.sm),
            if (canManage) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Change role',
                      style: AppText.label.copyWith(color: palette.textFaint)),
                ),
              ),
              for (final role in VaultRoleX.assignable)
                ListTile(
                  leading: Icon(role.icon, color: role.color),
                  title: Text(role.label),
                  subtitle: Text(role.description),
                  trailing: member.role == role
                      ?  Icon(Icons.check_circle_rounded,
                          color: AppColors.primaryGreen)
                      : null,
                  onTap: () => Navigator.of(context).pop('role:${role.name}'),
                ),
            ],
            if (canTransfer) ...[
              Divider(height: 1, color: palette.border),
              ListTile(
                leading:  Icon(Icons.workspace_premium_rounded,
                    color: AppColors.primaryGreen),
                title: const Text('Make owner'),
                subtitle: const Text('Transfer ownership — you become Admin'),
                onTap: () => Navigator.of(context).pop('transfer'),
              ),
            ],
            if (canManage) ...[
              Divider(height: 1, color: palette.border),
              ListTile(
                leading: const Icon(Icons.person_remove_rounded,
                    color: AppColors.critical),
                title: const Text('Remove from vault',
                    style: TextStyle(color: AppColors.critical)),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
            ],
            if (canLeave)
              ListTile(
                leading: const Icon(Icons.logout_rounded,
                    color: AppColors.critical),
                title: const Text('Leave vault',
                    style: TextStyle(color: AppColors.critical)),
                onTap: () => Navigator.of(context).pop('leave'),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
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
    try {
      if (action == 'remove') {
        await _repo.removeMember(member.id);
        _toast('${member.label} removed');
      } else if (action.startsWith('role:')) {
        final role = VaultRoleX.fromName(action.substring(5));
        if (role == member.role) return;
        await _repo.updateMemberRole(member.id, role);
        _toast('${member.label} is now ${role.label}');
      }
      await _loadMembers();
      await _loadAudit();
    } catch (e) {
      if (mounted) _toast('Couldn\'t update the member.', error: true);
    }
  }

  Future<void> _transferOwnership(VaultMember member) async {
    final palette = AppPalette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: const Text('Transfer ownership?'),
        content: Text(
          'Make ${member.label} the owner of "$_vaultName"? You will become an '
          'Admin. Only the owner can transfer ownership or delete the vault.',
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child:  Text('Transfer',
                style: TextStyle(color: AppColors.primaryGreen)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.transferOwnership(_vaultId, member.authUserId);
      _toast('${member.label} is now the owner');
      await _loadMembers();
      await _loadAudit();
      await _store.reload(); // list roles changed
    } catch (e) {
      if (mounted) _toast('Couldn\'t transfer ownership.', error: true);
    }
  }

  Future<void> _leave(VaultMember me) async {
    final palette = AppPalette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: const Text('Leave vault?'),
        content: Text(
          'You\'ll lose access to "$_vaultName". An owner or admin can invite '
          'you again later.',
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Leave',
                  style: TextStyle(color: AppColors.critical))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.removeMember(me.id);
      await _store.reload();
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) _toast('Couldn\'t leave the vault.', error: true);
    }
  }

  // ---- Invitation actions --------------------------------------------------

  Future<void> _inviteActions(VaultInvitation inv) async {
    if (!_myRole.canManageMembers) return;
    final palette = AppPalette.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
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
                    borderRadius: BorderRadius.circular(AppRadius.pill))),
            const SizedBox(height: AppSpacing.sm),
            if (inv.isPending) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Change role',
                      style: AppText.label.copyWith(color: palette.textFaint)),
                ),
              ),
              for (final role in VaultRoleX.assignable)
                ListTile(
                  leading: Icon(role.icon, color: role.color),
                  title: Text(role.label),
                  trailing: inv.role == role
                      ?  Icon(Icons.check_circle_rounded,
                          color: AppColors.primaryGreen)
                      : null,
                  onTap: () => Navigator.of(context).pop('role:${role.name}'),
                ),
              Divider(height: 1, color: palette.border),
              ListTile(
                leading: const Icon(Icons.cancel_rounded,
                    color: AppColors.critical),
                title: const Text('Cancel invitation',
                    style: TextStyle(color: AppColors.critical)),
                onTap: () => Navigator.of(context).pop('cancel'),
              ),
            ] else
              ListTile(
                leading:  Icon(Icons.refresh_rounded,
                    color: AppColors.primaryGreen),
                title: const Text('Resend invitation'),
                subtitle: Text('Re-send to ${inv.target}'),
                onTap: () => Navigator.of(context).pop('resend'),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'cancel') {
        await _repo.cancelInvitation(inv.id);
        _toast('Invitation cancelled');
      } else if (action == 'resend') {
        await _repo.resendInvitation(inv.id);
        _toast('Invitation resent');
      } else if (action.startsWith('role:')) {
        final role = VaultRoleX.fromName(action.substring(5));
        await _repo.resendInvitation(inv.id, role: role);
        _toast('Invitation role updated to ${role.label}');
      }
      await _loadInvitations();
      await _loadAudit();
    } catch (e) {
      if (mounted) _toast('Couldn\'t update the invitation.', error: true);
    }
  }

  // ---- Vault owner actions -------------------------------------------------

  Future<void> _renameVault() async {
    final controller = TextEditingController(text: _vaultName);
    final palette = AppPalette.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: const Text('Rename vault'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Vault name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child:  Text('Save',
                style: TextStyle(color: AppColors.primaryGreen)),
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
      if (mounted) _toast('Couldn\'t rename the vault.', error: true);
    }
  }

  Future<void> _deleteVault() async {
    final palette = AppPalette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: const Text('Delete vault?'),
        content: Text(
          'This permanently deletes "$_vaultName" and removes all members. This '
          'cannot be undone.',
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.critical))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _store.delete(_vaultId);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) _toast('Couldn\'t delete the vault.', error: true);
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
                      ? const Center(child: CircularProgressIndicator())
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
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.cloud_off_rounded, size: 48, color: palette.textFaint),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: palette.textSecondary)),
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
      'Shared with ${_members.length} member${_members.length == 1 ? '' : 's'}',
      if (storage.isNotEmpty) storage,
    ].join(' · ');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xl * 2),
      children: [
        if (_showSearch) ...[
          _SearchField(
            hint: 'Search members or invitations',
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
                child: const Icon(Icons.folder_shared_rounded,
                    color: Colors.white, size: 28),
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
                          icon: Icons.add_rounded,
                          label: 'Upload',
                          onTap: _addDocument,
                        ),
                      ),
                    if (_myRole.canEditDocuments && _myRole.canManageMembers)
                      const SizedBox(width: 10),
                    if (_myRole.canManageMembers)
                      Expanded(
                        child: _HeroOutlineButton(
                          icon: Icons.ios_share_rounded,
                          label: 'Share',
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
            Text('Vault Members',
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const Spacer(),
            if (_myRole.canManageMembers)
              PressableScale(
                pressedScale: 0.95,
                child: GestureDetector(
                  onTap: _invite,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    'Manage',
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
          _NoMatches(palette: palette, what: 'members')
        else
          AdaptiveGlassCard(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
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
              Text('Invitations',
                  style: AppText.title.copyWith(color: palette.textPrimary)),
              if (pendingCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text('$pendingCount pending',
                      style: AppText.label.copyWith(
                          color: AppColors.darkGreen,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_invitesLoading && _invitations.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (invitations.isEmpty)
            AdaptiveGlassCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              radius: AppRadius.card,
              child: Row(
                children: [
                  Icon(Icons.mail_outline_rounded,
                      size: 20, color: palette.textFaint),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                        _query.isEmpty
                            ? 'No invitations yet. Tap Share to add family.'
                            : 'No invitations match "$_query".',
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                  ),
                ],
              ),
            )
          else
            AdaptiveGlassCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
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

        // Shared documents — compact list under members.
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Text('Shared documents',
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const Spacer(),
            if (_docsLoading)
               SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primaryGreen),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_documents.isEmpty && !_docsLoading)
          AdaptiveGlassCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            radius: AppRadius.card,
            child: Text(
              _myRole.canEditDocuments
                  ? 'Nothing shared yet. Tap Upload to add a document.'
                  : 'Nothing has been shared with you yet.',
              style: AppText.caption
                  .copyWith(color: palette.textSecondary, height: 1.4),
            ),
          )
        else if (_documents.isNotEmpty)
          AdaptiveGlassCard(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            radius: AppRadius.card,
            child: Column(
              children: [
                for (var i = 0; i < _documents.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: palette.border),
                  _VaultDocRow(
                    doc: _documents[i],
                    canRemove: _documents[i]
                        .canBeRemovedBy(_currentUid, _myRole),
                    onOpen: () => _openDocument(_documents[i]),
                    onRemove: () => _removeDocument(_documents[i]),
                  ),
                ],
              ],
            ),
          ),

        // Recent Activity timeline.
        const SizedBox(height: AppSpacing.lg),
        Text('Recent Activity',
            style: AppText.title.copyWith(color: palette.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        if (_auditLoading && _audit.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_audit.isEmpty)
          AdaptiveGlassCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            radius: AppRadius.card,
            child: Row(
              children: [
                Icon(Icons.history_rounded,
                    size: 20, color: palette.textFaint),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('No activity yet.',
                      style: AppText.caption
                          .copyWith(color: palette.textSecondary)),
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
            Icon(Icons.verified_user_rounded,
                size: 14, color: AppColors.primaryGreen.withValues(alpha: 0.85)),
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
    final canManage = _myRole.canManageMembers && !isOwnerRow && !isMe;
    final canTransfer = _myRole == VaultRole.owner && !isOwnerRow;
    final canLeave = isMe && !isOwnerRow;
    return canManage || canTransfer || canLeave;
  }

  Widget _header(AppPalette palette) {
    final canOwn = _myRole.canManageVault;
    final glass = divineGlassEnabled(context);
    final l10n = AppLocalizations.of(context);
    final user = AuthService.instance.currentUser;
    final photo = (user?.userMetadata?['profile_photo'] as String?) ??
        (user?.userMetadata?['avatar_url'] as String?);

    final avatar = GestureDetector(
      onTap: _openProfile,
      child: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.tealMist,
        backgroundImage:
            photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
        child: photo == null || photo.isEmpty
            ? Icon(Icons.person_rounded,
                size: 18, color: AppColors.primaryGreen)
            : null,
      ),
    );

    final glassTrailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DivineGlassHeaderAction(
          icon: _showSearch ? Icons.close_rounded : Icons.search_rounded,
          tooltip: 'Search',
          onTap: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) _query = '';
          }),
        ),
        if (canOwn) ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'More',
            padding: EdgeInsets.zero,
            offset: const Offset(0, 40),
            onSelected: (v) {
              if (v == 'rename') _renameVault();
              if (v == 'delete') _deleteVault();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename vault')),
              PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete vault',
                      style: TextStyle(color: AppColors.critical))),
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
            tooltip: 'Search',
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
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename vault')),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete vault',
                        style: TextStyle(color: AppColors.critical))),
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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text(
                label,
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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryGreen, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primaryGreen, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style:  TextStyle(
                  color: AppColors.primaryGreen,
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

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({required this.entries});

  final List<VaultAuditEntry> entries;

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${d.inDays ~/ 7}w ago';
  }

  static String _title(VaultAuditEntry e) {
    final what = e.targetLabel?.trim() ?? '';
    switch (e.action) {
      case 'invite_sent':
      case 'invite_resent':
        return 'New member added';
      case 'invite_accepted':
        return what.isEmpty ? 'Invitation accepted' : '$what joined';
      case 'role_changed':
        return what.isEmpty ? 'Role updated' : '$what role changed';
      case 'member_removed':
        return what.isEmpty ? 'Member removed' : '$what removed';
      case 'member_left':
        return what.isEmpty ? 'Member left' : '$what left';
      case 'ownership_transferred':
        return 'Ownership transferred';
      case 'vault_renamed':
        return 'Vault renamed';
      default:
        return what.isNotEmpty
            ? what
            : e.action.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
                        child: Icon(entries[i].icon,
                            size: 14, color: AppColors.primaryGreen),
                      ),
                      if (i < entries.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color:
                                AppColors.primaryGreen.withValues(alpha: 0.25),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(
                        bottom: i < entries.length - 1 ? 10 : 0),
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
                                _title(entries[i]),
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
                              _ago(entries[i].createdAt),
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
              child: Text(member.initial,
                  style: TextStyle(
                      color: member.role.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(member.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.subtitle.copyWith(
                                color: palette.textPrimary, fontSize: 14.5)),
                      ),
                      if (isMe)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text('(you)',
                              style: AppText.caption
                                  .copyWith(color: palette.textFaint)),
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
                      style: AppText.caption
                          .copyWith(color: palette.textFaint, fontSize: 11.5),
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
                child: Icon(Icons.more_horiz_rounded,
                    size: 18, color: palette.textFaint),
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
                invite.email != null
                    ? Icons.email_rounded
                    : Icons.phone_rounded,
                size: 18,
                color: palette.textFaint),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invite.target,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                          color: palette.textPrimary, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('Invited as ${invite.role.label}',
                      style: AppText.caption
                          .copyWith(color: palette.textFaint, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _StatusChip(status: invite.status),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.more_horiz_rounded,
                  size: 18, color: palette.textFaint),
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
      child: Text(status.label,
          style: TextStyle(
              color: status.color,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
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
        hintStyle: AppText.body.copyWith(color: palette.textFaint, fontSize: 14),
        prefixIcon:
            Icon(Icons.search_rounded, size: 20, color: palette.textFaint),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close_rounded,
                    size: 18, color: palette.textFaint),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: palette.surfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              BorderSide(color: AppColors.primaryGreen, width: 1.4),
        ),
      ),
    );
  }
}

/// Shown when a search filters every row out of a list.
class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.palette, required this.what});

  final AppPalette palette;
  final String what;

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
            child: Text('No $what match your search.',
                style: AppText.caption.copyWith(color: palette.textSecondary)),
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
class _VaultDocRow extends StatelessWidget {
  const _VaultDocRow({
    required this.doc,
    required this.canRemove,
    required this.onOpen,
    required this.onRemove,
  });

  final VaultDocument doc;
  final bool canRemove;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  IconData get _icon {
    if (doc.isImage) return Icons.image_rounded;
    if (doc.isPdf) return Icons.picture_as_pdf_rounded;
    return Icons.description_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final meta = [
      if (doc.category != null && doc.category!.isNotEmpty) doc.category!,
      if (doc.sizeLabel.isNotEmpty) doc.sizeLabel,
    ].join(' · ');

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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(_icon, size: 19, color: AppColors.primaryGreen),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                          color: palette.textPrimary, fontSize: 14.5),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove from vault',
                  icon: Icon(Icons.remove_circle_outline_rounded,
                      size: 19, color: palette.textSecondary),
                )
              else
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: palette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
