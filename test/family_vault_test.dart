import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/family_vault_repository.dart';
import 'package:inoapp/models/family_vault_models.dart';
import 'package:inoapp/services/family_vault_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

/// An in-memory fake so the store's logic is testable without Supabase.
class _FakeVaultRepo implements FamilyVaultRepository {
  final List<VaultSummary> vaults = [];
  final List<VaultInvitation> pending = [];
  int _seq = 0;
  bool failCreate = false;
  bool failWrite = false;
  final List<String> accepted = [];
  final List<String> declined = [];

  @override
  Future<List<VaultSummary>> myVaults() async => List.of(vaults);

  @override
  Future<FamilyVault> createVault(String name) async {
    if (failCreate) throw Exception('offline');
    final v = FamilyVault(
      id: 'v${_seq++}',
      name: name.trim(),
      ownerAuthUserId: 'me',
      createdAt: DateTime(2026, 7, 28),
    );
    vaults.insert(0, VaultSummary(vault: v, myRole: VaultRole.owner));
    return v;
  }

  @override
  Future<List<VaultMember>> members(String vaultId) async => const [];

  @override
  Future<void> renameVault(String id, String name) async {
    if (failWrite) throw Exception('offline');
  }

  @override
  Future<void> deleteVault(String id) async {
    if (failWrite) throw Exception('offline');
    vaults.removeWhere((v) => v.vault.id == id);
  }

  @override
  Future<void> updateMemberRole(String memberId, VaultRole role) async {}

  @override
  Future<void> removeMember(String memberId) async {}

  @override
  Future<void> transferOwnership(String vaultId, String newOwner) async {}

  @override
  Future<VaultInvitation> invite(String vaultId, VaultRole role,
      {String? email, String? phone}) async {
    if (failWrite) throw Exception('offline');
    return VaultInvitation(
      id: 'i${_seq++}',
      vaultId: vaultId,
      role: role,
      status: InvitationStatus.pending,
      email: email,
      phone: phone,
    );
  }

  @override
  Future<List<VaultInvitation>> invitationsForVault(String vaultId) async =>
      pending.where((i) => i.vaultId == vaultId).toList();

  @override
  Future<List<VaultInvitation>> myPendingInvitations() async => List.of(pending);

  @override
  Future<void> acceptInvitation(String id) async {
    accepted.add(id);
    pending.removeWhere((i) => i.id == id);
  }

  @override
  Future<void> declineInvitation(String id) async {
    declined.add(id);
    pending.removeWhere((i) => i.id == id);
  }

  @override
  Future<void> cancelInvitation(String id) async {}

  @override
  Future<void> resendInvitation(String id, {VaultRole? role}) async {}

  @override
  Future<List<VaultAuditEntry>> auditLog(String vaultId, {int limit = 50}) async =>
      const [];

  // Realtime is a no-op in tests (no live backend).
  @override
  RealtimeChannel? watchMyVaults(void Function() onChange) => null;

  @override
  RealtimeChannel? watchVault(String vaultId, void Function() onChange) => null;

  @override
  Future<void> unwatch(RealtimeChannel channel) async {}
}

void main() {
  group('VaultRole permissions', () {
    test('privilege ordering (viewer < editor < admin < owner)', () {
      expect(VaultRole.viewer.index < VaultRole.editor.index, isTrue);
      expect(VaultRole.editor.index < VaultRole.admin.index, isTrue);
      expect(VaultRole.admin.index < VaultRole.owner.index, isTrue);
    });

    test('canView — every role', () {
      for (final r in VaultRole.values) {
        expect(r.canView, isTrue);
      }
    });

    test('canEditDocuments — editor and up', () {
      expect(VaultRole.viewer.canEditDocuments, isFalse);
      expect(VaultRole.editor.canEditDocuments, isTrue);
      expect(VaultRole.admin.canEditDocuments, isTrue);
      expect(VaultRole.owner.canEditDocuments, isTrue);
    });

    test('canManageMembers — admin and owner only', () {
      expect(VaultRole.viewer.canManageMembers, isFalse);
      expect(VaultRole.editor.canManageMembers, isFalse);
      expect(VaultRole.admin.canManageMembers, isTrue);
      expect(VaultRole.owner.canManageMembers, isTrue);
    });

    test('canManageVault — owner only', () {
      expect(VaultRole.admin.canManageVault, isFalse);
      expect(VaultRole.owner.canManageVault, isTrue);
    });

    test('assignable roles never include owner', () {
      expect(VaultRoleX.assignable.contains(VaultRole.owner), isFalse);
      expect(VaultRoleX.assignable,
          [VaultRole.viewer, VaultRole.editor, VaultRole.admin]);
    });

    test('fromName round-trips and defaults to viewer', () {
      expect(VaultRoleX.fromName('owner'), VaultRole.owner);
      expect(VaultRoleX.fromName('admin'), VaultRole.admin);
      expect(VaultRoleX.fromName('editor'), VaultRole.editor);
      expect(VaultRoleX.fromName('viewer'), VaultRole.viewer);
      expect(VaultRoleX.fromName(null), VaultRole.viewer);
      expect(VaultRoleX.fromName('garbage'), VaultRole.viewer);
    });
  });

  group('VaultMember', () {
    VaultMember member({String? name, String? email, String? phone}) =>
        VaultMember(
          id: 'm1',
          vaultId: 'v1',
          authUserId: 'u1',
          role: VaultRole.viewer,
          displayName: name,
          email: email,
          phone: phone,
          joinedAt: DateTime(2026, 7, 28),
        );

    test('label falls back name → email → phone → "Member"', () {
      expect(member(name: 'Asha Rao').label, 'Asha Rao');
      expect(member(email: 'a@x.com').label, 'a@x.com');
      expect(member(phone: '+91 90000 00000').label, '+91 90000 00000');
      expect(member().label, 'Member');
    });

    test('initial derives one/two letters', () {
      expect(member(name: 'Asha Rao').initial, 'AR');
      expect(member(name: 'Asha').initial, 'A');
      expect(member().initial, 'M'); // from "Member"
    });

    test('fromRow parses a membership row', () {
      final m = VaultMember.fromRow({
        'id': 'm2',
        'vault_id': 'v2',
        'auth_user_id': 'u2',
        'role': 'admin',
        'display_name': 'Ravi',
        'email': 'ravi@x.com',
        'created_at': '2026-07-28T10:00:00Z',
      });
      expect(m.role, VaultRole.admin);
      expect(m.displayName, 'Ravi');
      expect(m.label, 'Ravi');
    });
  });

  group('FamilyVaultStore', () {
    late _FakeVaultRepo repo;

    setUp(() {
      repo = _FakeVaultRepo();
      FamilyVaultRepository.instance = repo;
      FamilyVaultStore.instance.reset();
    });

    test('create prepends the new vault as owner', () async {
      final v = await FamilyVaultStore.instance.create('Sharma Family');
      expect(v.name, 'Sharma Family');
      expect(FamilyVaultStore.instance.vaults.length, 1);
      expect(FamilyVaultStore.instance.vaults.first.myRole, VaultRole.owner);
      expect(FamilyVaultStore.instance.isEmpty, isFalse);
    });

    test('delete removes the vault; rolls back + rethrows on failure',
        () async {
      final v = await FamilyVaultStore.instance.create('Temp');
      expect(FamilyVaultStore.instance.vaults.length, 1);

      // Success path.
      await FamilyVaultStore.instance.delete(v.id);
      expect(FamilyVaultStore.instance.isEmpty, isTrue);

      // Failure path rolls the optimistic removal back.
      final v2 = await FamilyVaultStore.instance.create('Keep');
      repo.failWrite = true;
      await expectLater(
          FamilyVaultStore.instance.delete(v2.id), throwsA(isA<Exception>()));
      expect(FamilyVaultStore.instance.vaults.length, 1); // restored
    });

    test('rename updates in place; rolls back on failure', () async {
      final v = await FamilyVaultStore.instance.create('Old Name');
      await FamilyVaultStore.instance.rename(v.id, 'New Name');
      expect(FamilyVaultStore.instance.vaults.first.vault.name, 'New Name');

      repo.failWrite = true;
      await expectLater(FamilyVaultStore.instance.rename(v.id, 'Broken'),
          throwsA(isA<Exception>()));
      expect(FamilyVaultStore.instance.vaults.first.vault.name, 'New Name');
    });

    test('clear empties the cache (sign-out isolation)', () async {
      await FamilyVaultStore.instance.create('A');
      FamilyVaultStore.instance.clear();
      expect(FamilyVaultStore.instance.isEmpty, isTrue);
    });

    test('accept / decline delegate to the repository', () async {
      final repo2 = _FakeVaultRepo();
      FamilyVaultRepository.instance = repo2;
      FamilyVaultStore.instance.reset();

      await FamilyVaultStore.instance.acceptInvitation('inv-1');
      expect(repo2.accepted, contains('inv-1'));

      await FamilyVaultStore.instance.declineInvitation('inv-2');
      expect(repo2.declined, contains('inv-2'));
    });
  });

  group('InvitationStatus', () {
    test('fromName maps values and defaults to pending', () {
      expect(InvitationStatusX.fromName('accepted'), InvitationStatus.accepted);
      expect(InvitationStatusX.fromName('declined'), InvitationStatus.declined);
      expect(InvitationStatusX.fromName('revoked'), InvitationStatus.revoked);
      expect(InvitationStatusX.fromName('expired'), InvitationStatus.expired);
      expect(InvitationStatusX.fromName('pending'), InvitationStatus.pending);
      expect(InvitationStatusX.fromName(null), InvitationStatus.pending);
      expect(InvitationStatusX.fromName('garbage'), InvitationStatus.pending);
    });

    test('revoked reads as "Cancelled"', () {
      expect(InvitationStatus.revoked.label, 'Cancelled');
      expect(InvitationStatus.pending.label, 'Pending');
    });
  });

  group('VaultInvitation', () {
    test('fromRow parses an email invitation with denormalized names', () {
      final inv = VaultInvitation.fromRow({
        'id': 'i1',
        'vault_id': 'v1',
        'role': 'editor',
        'status': 'pending',
        'email': 'asha@example.com',
        'vault_name': 'Sharma Family',
        'invited_by_name': 'Ravi',
        'created_at': '2026-07-28T10:00:00Z',
        'expires_at': '2026-08-27T10:00:00Z',
      });
      expect(inv.role, VaultRole.editor);
      expect(inv.status, InvitationStatus.pending);
      expect(inv.isPending, isTrue);
      expect(inv.target, 'asha@example.com');
      expect(inv.vaultName, 'Sharma Family');
      expect(inv.invitedByName, 'Ravi');
    });

    test('target falls back to phone when no email', () {
      final inv = VaultInvitation.fromRow({
        'id': 'i2',
        'vault_id': 'v2',
        'role': 'viewer',
        'status': 'pending',
        'phone': '+919876543210',
      });
      expect(inv.target, '+919876543210');
      expect(inv.role, VaultRole.viewer);
    });

    test('assignable roles for invites never include owner', () {
      // The invite sheet only ever offers these; owner is created by the DB
      // trigger / transfer, never invited.
      expect(VaultRoleX.assignable, isNot(contains(VaultRole.owner)));
    });

    test('parses lifecycle timestamps (updated_at / accepted_at)', () {
      final inv = VaultInvitation.fromRow({
        'id': 'i9',
        'vault_id': 'v9',
        'role': 'admin',
        'status': 'accepted',
        'email': 'a@x.com',
        'created_at': '2026-07-28T10:00:00Z',
        'expires_at': '2026-08-27T10:00:00Z',
        'updated_at': '2026-07-28T11:00:00Z',
        'accepted_at': '2026-07-28T11:00:00Z',
      });
      expect(inv.updatedAt, isNotNull);
      expect(inv.acceptedAt, isNotNull);
      expect(inv.status, InvitationStatus.accepted);
    });

    test('isExpired reflects an expiry in the past', () {
      final past = VaultInvitation.fromRow({
        'id': 'i10',
        'vault_id': 'v10',
        'role': 'viewer',
        'status': 'pending',
        'email': 'a@x.com',
        'expires_at': '2000-01-01T00:00:00Z',
      });
      expect(past.isExpired, isTrue);
    });

    test('matches() searches target, role and vault name', () {
      final inv = VaultInvitation.fromRow({
        'id': 'i11',
        'vault_id': 'v11',
        'role': 'editor',
        'status': 'pending',
        'email': 'asha@example.com',
        'vault_name': 'Sharma Family',
      });
      expect(inv.matches(''), isTrue); // empty query matches all
      expect(inv.matches('asha'), isTrue); // target
      expect(inv.matches('editor'), isTrue); // role label
      expect(inv.matches('sharma'), isTrue); // vault name
      expect(inv.matches('nope'), isFalse);
    });
  });

  group('VaultMember search', () {
    VaultMember m({String? name, String? email, String? phone}) => VaultMember(
          id: 'm',
          vaultId: 'v',
          authUserId: 'u',
          role: VaultRole.editor,
          displayName: name,
          email: email,
          phone: phone,
          joinedAt: DateTime(2026, 7, 28),
        );

    test('matches name / email / phone / role, empty matches all', () {
      final member = m(name: 'Asha Rao', email: 'asha@x.com', phone: '+91999');
      expect(member.matches(''), isTrue);
      expect(member.matches('asha'), isTrue);
      expect(member.matches('ASHA@X'), isTrue);
      expect(member.matches('999'), isTrue);
      expect(member.matches('editor'), isTrue);
      expect(member.matches('zzz'), isFalse);
    });
  });

  group('VaultAuditEntry', () {
    VaultAuditEntry entry(String action,
            {String? actor, String? target, Map<String, dynamic>? meta}) =>
        VaultAuditEntry.fromRow({
          'id': 'a1',
          'vault_id': 'v1',
          'action': action,
          'actor_name': actor,
          'target_label': target,
          'metadata': meta ?? {},
          'created_at': '2026-07-28T10:00:00Z',
        });

    test('fromRow parses fields + metadata', () {
      final e = entry('role_changed',
          actor: 'Ravi', target: 'Asha', meta: {'from': 'viewer', 'to': 'admin'});
      expect(e.action, 'role_changed');
      expect(e.actorName, 'Ravi');
      expect(e.targetLabel, 'Asha');
      expect(e.metadata['to'], 'admin');
    });

    test('summary reads as a human sentence per action', () {
      expect(
        entry('invite_sent', actor: 'Ravi', target: 'a@x.com', meta: {'role': 'editor'})
            .summary,
        'Ravi invited a@x.com as Editor',
      );
      expect(entry('invite_accepted', target: 'Asha').summary,
          'Asha accepted the invitation');
      expect(
        entry('role_changed', actor: 'Ravi', target: 'Asha', meta: {'from': 'viewer', 'to': 'admin'})
            .summary,
        'Ravi changed Asha\'s role from viewer to admin',
      );
      expect(entry('ownership_transferred', actor: 'Ravi', target: 'Asha').summary,
          'Ravi transferred ownership to Asha');
      expect(entry('member_left', target: 'Asha').summary, 'Asha left the vault');
    });

    test('unknown action falls back to a readable default', () {
      expect(entry('some_new_action', actor: 'Ravi').summary,
          contains('some new action'));
    });
  });
}
