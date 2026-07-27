import 'package:flutter/material.dart';

import '../../data/family_vault_repository.dart';
import '../../models/family_vault_models.dart';
import '../../services/family_vault_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import 'family_vault_screen.dart' show VaultRoleBadge;

/// One Family Vault: its members and their roles. Owners/admins can assign
/// roles and remove members here (item 7). Inviting new members arrives in
/// Phase 2 — the affordance is present and gated to those who may manage
/// members. Documents scoped to the vault come in a later phase.
class VaultDetailScreen extends StatefulWidget {
  const VaultDetailScreen({super.key, required this.summary});

  final VaultSummary summary;

  @override
  State<VaultDetailScreen> createState() => _VaultDetailScreenState();
}

class _VaultDetailScreenState extends State<VaultDetailScreen> {
  final _repo = FamilyVaultRepository.instance;
  final _store = FamilyVaultStore.instance;

  late final VaultRole _myRole = widget.summary.myRole;
  late String _vaultName = widget.summary.vault.name;

  List<VaultMember> _members = const [];
  bool _loading = true;
  String? _error;

  String get _vaultId => widget.summary.vault.id;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await _repo.members(_vaultId);
      if (!mounted) return;
      setState(() {
        _members = members;
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

  void _toast(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
    ));
  }

  void _invite() {
    // Phase 2: invite by phone / Google / device contacts. The entry point is
    // here now so the flow has a home.
    _toast('Member invitations arrive in the next update.');
  }

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
            child: const Text('Save',
                style: TextStyle(color: AppColors.primaryGreen)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == _vaultName || !mounted) return;
    try {
      await _store.rename(_vaultId, name);
      if (mounted) setState(() => _vaultName = name);
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

  Future<void> _memberActions(VaultMember member) async {
    // Only admins/owner manage members, and never the owner row or yourself.
    if (!_myRole.canManageMembers ||
        member.role == VaultRole.owner ||
        member.authUserId == widget.summary.vault.ownerAuthUserId) {
      return;
    }
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text('Change role',
                  style: AppText.label.copyWith(color: palette.textFaint)),
            ),
            for (final role in VaultRoleX.assignable)
              ListTile(
                leading: Icon(role.icon, color: role.color),
                title: Text(role.label),
                subtitle: Text(role.description),
                trailing: member.role == role
                    ? const Icon(Icons.check_circle_rounded,
                        color: AppColors.primaryGreen)
                    : null,
                onTap: () => Navigator.of(context).pop('role:${role.name}'),
              ),
            Divider(height: 1, color: palette.border),
            ListTile(
              leading: const Icon(Icons.person_remove_rounded,
                  color: AppColors.critical),
              title: const Text('Remove from vault',
                  style: TextStyle(color: AppColors.critical)),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
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
    } catch (e) {
      if (mounted) _toast('Couldn\'t update the member.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      floatingActionButton: _myRole.canManageMembers
          ? _InviteButton(onTap: _invite)
          : null,
      body: SafeArea(
        child: Column(
          children: [
            _header(palette),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primaryGreen,
                onRefresh: _loadMembers,
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
    );
  }

  Widget _errorBody(AppPalette palette) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
    return ListView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xl * 2),
      children: [
        // Vault hero.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.internal),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.family_restroom_rounded,
                  color: Colors.white, size: 30),
              const SizedBox(height: AppSpacing.sm),
              Text(_vaultName,
                  style: AppText.headline
                      .copyWith(color: Colors.white, fontSize: 22)),
              const SizedBox(height: 2),
              Text(
                '${_members.length} member${_members.length == 1 ? '' : 's'} · '
                'you are ${_myRole.label}',
                style: AppText.caption
                    .copyWith(color: Colors.white.withValues(alpha: 0.9)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Text('Members',
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const Spacer(),
            if (_myRole.canManageMembers)
              PressableScale(
                pressedScale: 0.95,
                child: GestureDetector(
                  onTap: _invite,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      const Icon(Icons.person_add_alt_1_rounded,
                          size: 18, color: AppColors.primaryGreen),
                      const SizedBox(width: 4),
                      Text('Invite',
                          style: AppText.subtitle.copyWith(
                              color: AppColors.primaryGreen, fontSize: 13.5)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        InoCard(
          radius: AppRadius.card,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (var i = 0; i < _members.length; i++) ...[
                if (i > 0) Divider(height: 1, color: palette.border),
                _MemberRow(
                  member: _members[i],
                  canManage: _myRole.canManageMembers &&
                      _members[i].role != VaultRole.owner &&
                      _members[i].authUserId !=
                          widget.summary.vault.ownerAuthUserId,
                  onTap: () => _memberActions(_members[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(AppPalette palette) {
    final canOwn = _myRole.canManageVault;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
          AppSpacing.screen, AppSpacing.md),
      child: Row(
        children: [
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 21, color: palette.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('Vault',
                style: AppText.headline
                    .copyWith(color: palette.textPrimary, fontSize: 21)),
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
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.canManage,
    required this.onTap,
  });

  final VaultMember member;
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: canManage ? onTap : null,
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
                  Text(member.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                          color: palette.textPrimary, fontSize: 14.5)),
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
            if (canManage)
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

class _InviteButton extends StatelessWidget {
  const _InviteButton({required this.onTap});

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
              Icon(Icons.person_add_alt_1_rounded,
                  color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text('Invite',
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
