import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/family_vault_models.dart';

void main() {
  group('VaultDocument Visibility & Custom Disclosure Tests', () {
    test('default document has isHidden == false and isVisibleToMembers == true', () {
      final doc = VaultDocument(
        id: 'doc-1',
        vaultId: 'vault-1',
        sharedBy: 'user-1',
        objectPath: 'user-1/records/doc-1.pdf',
        name: 'Aadhaar Card',
        createdAt: DateTime.now(),
      );

      expect(doc.isHidden, isFalse);
      expect(doc.isVisibleToMembers, isTrue);
      expect(doc.customDisclosure, isNull);
    });

    test('document with hidden: true in note is parsed correctly', () {
      final doc = VaultDocument(
        id: 'doc-2',
        vaultId: 'vault-1',
        sharedBy: 'user-1',
        objectPath: 'user-1/records/doc-2.pdf',
        name: 'PAN Card',
        note: jsonEncode({
          'hidden': true,
          'is_hidden': true,
          'active': false,
        }),
        createdAt: DateTime.now(),
      );

      expect(doc.isHidden, isTrue);
      expect(doc.isVisibleToMembers, isFalse);
    });

    test('document with custom disclosure fields extracts them correctly', () {
      final fields = {
        'name': true,
        'file': false,
        'price': true,
        'location': false,
        'registration_number': true,
      };

      final doc = VaultDocument(
        id: 'doc-3',
        vaultId: 'vault-1',
        sharedBy: 'user-1',
        objectPath: 'user-1/records/doc-3.json',
        name: 'Green Villa',
        category: 'Residential',
        sourceTable: 'Property Wallet',
        note: jsonEncode({
          'hidden': false,
          'fields': fields,
          'user_note': 'Shared without deed attachment',
        }),
        createdAt: DateTime.now(),
      );

      expect(doc.isHidden, isFalse);
      expect(doc.isVisibleToMembers, isTrue);
      expect(doc.customDisclosure, isNotNull);
      expect(doc.customDisclosure!['price'], isTrue);
      expect(doc.customDisclosure!['file'], isFalse);
      expect(doc.customDisclosure!['location'], isFalse);
      expect(doc.displayNote, 'Shared without deed attachment');
    });

    test('viewer sees only visible documents while admin sees all', () {
      final allDocs = [
        VaultDocument(
          id: '1',
          vaultId: 'v1',
          sharedBy: 'u1',
          objectPath: 'path1',
          name: 'Public Doc',
          createdAt: DateTime.now(),
        ),
        VaultDocument(
          id: '2',
          vaultId: 'v1',
          sharedBy: 'u1',
          objectPath: 'path2',
          name: 'Hidden Property',
          note: jsonEncode({'hidden': true}),
          createdAt: DateTime.now(),
        ),
      ];

      final viewerDocs = allDocs.where((d) => d.isVisibleToMembers).toList();
      final adminDocs = allDocs;

      expect(viewerDocs.length, 1);
      expect(viewerDocs.first.name, 'Public Doc');
      expect(adminDocs.length, 2);
    });
  });
}
