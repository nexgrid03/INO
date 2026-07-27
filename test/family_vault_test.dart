import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/family_vault_repository.dart';
import 'package:inoapp/models/family_vault_models.dart';
import 'package:inoapp/services/family_vault_store.dart';

/// An in-memory fake so the store's logic is testable without Supabase.
class _FakeVaultRepo implements FamilyVaultRepository {
  final List<VaultSummary> vaults = [];
  int _seq = 0;
  bool failCreate = false;
  bool failWrite = false;

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
  });
}
