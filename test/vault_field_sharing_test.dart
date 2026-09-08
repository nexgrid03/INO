import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/family_vault_models.dart';
import 'package:inoapp/models/vault_share_field.dart';
import 'package:inoapp/services/wallet_media_sync.dart';

/// A property as PropertyStore.toJson() writes it, trimmed to the fields these
/// tests care about — including the empty and plumbing ones, because half of
/// what the checklist has to get right is what it LEAVES OUT.
Map<String, dynamic> _property() => {
      'id': 'prop_123',
      'name': 'Lake House',
      'type': 'house',
      'createdAt': '2026-01-01T00:00:00.000',
      'updatedAt': '2026-02-01T00:00:00.000',
      'imagePath': 'uid/1757.jpg',
      'purchasePrice': 4500000,
      'currentValue': 6200000,
      'city': 'Hyderabad',
      'address': '12 Lake Road',
      'nomineeName': null,
      'legalHeirs': <String>[],
      'attachments': <Map<String, dynamic>>[],
      'isFavorite': false,
      'registrationNumber': 'REG-99',
    };

void main() {
  group('VaultShareFields — what the checklist offers', () {
    test('skips plumbing keys and fields with nothing in them', () {
      final fields = VaultShareFields.forRecord(_property(), hasFile: false);
      final keys = fields.map((f) => f.key).toSet();

      // Identity and sync bookkeeping are not disclosure decisions.
      expect(keys, isNot(contains('id')));
      expect(keys, isNot(contains('createdAt')));
      expect(keys, isNot(contains('updatedAt')));
      expect(keys, isNot(contains('isFavorite')));
      // The file has its own entry; imagePath must not appear as a data field.
      expect(keys, isNot(contains('imagePath')));
      expect(keys, isNot(contains('attachments')));
      // An empty nominee is no data, not withheld data — offering a switch for
      // it just buries the real choices.
      expect(keys, isNot(contains('nomineeName')));
      expect(keys, isNot(contains('legalHeirs')));

      expect(keys, containsAll(<String>{
        'name',
        'purchasePrice',
        'currentValue',
        'city',
        'address',
        'registrationNumber',
      }));
    });

    test('the file is offered first, and only when there is one', () {
      final without = VaultShareFields.forRecord(_property(), hasFile: false);
      expect(without.any((f) => f.isFile), isFalse);

      final with_ = VaultShareFields.forRecord(_property(), hasFile: true);
      expect(with_.first.key, VaultShareField.fileKey);
      expect(with_.first.isFile, isTrue);
    });

    test('money, IDs and addresses are flagged sensitive; a name is not', () {
      final fields = {
        for (final f in VaultShareFields.forRecord(_property(), hasFile: false))
          f.key: f,
      };
      expect(fields['purchasePrice']!.sensitive, isTrue);
      expect(fields['registrationNumber']!.sensitive, isTrue);
      expect(fields['address']!.sensitive, isTrue);
      expect(fields['name']!.sensitive, isFalse);
    });

    test('a field added to a model tomorrow still gets a readable label', () {
      // No entry in the label table — the de-camel-caser has to carry it, which
      // is the whole reason the checklist is built from the record rather than
      // from a hand-written list per wallet.
      expect(VaultShareFields.labelFor('solarPanelCapacity'),
          'Solar Panel Capacity');
      expect(VaultShareFields.labelFor('purchasePrice'), 'Purchase Price');
      expect(VaultShareFields.labelFor('pinCode'), 'PIN Code');
    });

    test('previews render dates, lists and booleans readably', () {
      expect(VaultShareFields.describe('2026-02-01T00:00:00.000'), '01/02/2026');
      expect(VaultShareFields.describe(true), 'Yes');
      expect(VaultShareFields.describe(['a', 'b', 'c', 'd']), 'a, b, c +1');
      expect(VaultShareFields.describe(''), isNull);
      expect(VaultShareFields.describe(0), isNull);
      expect(VaultShareFields.describe(null), isNull);
    });

    test('a wallet-wide checklist is the union, most common field first', () {
      final fields = VaultShareFields.forWallet(
        [
          {'name': 'A', 'city': 'Hyderabad', 'currentValue': 10},
          {'name': 'B', 'city': 'Pune'},
          {'name': 'C'},
        ],
        anyHasFile: true,
      );
      expect(fields.first.key, VaultShareField.fileKey);
      final dataKeys = [for (final f in fields.skip(1)) f.key];
      expect(dataKeys, ['name', 'city', 'currentValue']);
    });
  });

  group('VaultShareFields.applyMask — what actually travels', () {
    test('a field switched off is absent, not blanked', () {
      final masked = VaultShareFields.applyMask(_property(), {
        'purchasePrice': false,
        'currentValue': false,
        'city': true,
      });
      expect(masked.containsKey('purchasePrice'), isFalse);
      expect(masked.containsKey('currentValue'), isFalse);
      expect(masked['city'], 'Hyderabad');
    });

    test('a field the checklist never offered defaults to shared', () {
      // Not being asked about a field is not the same as withholding it —
      // silently dropping data the user believes they sent is the worse failure.
      final masked = VaultShareFields.applyMask(_property(), const {});
      expect(masked['name'], 'Lake House');
      expect(masked['registrationNumber'], 'REG-99');
    });

    test('plumbing and empty fields never travel, mask or no mask', () {
      final masked = VaultShareFields.applyMask(_property(), const {});
      expect(masked.containsKey('id'), isFalse);
      expect(masked.containsKey('imagePath'), isFalse);
      expect(masked.containsKey('nomineeName'), isFalse);
      expect(masked.containsKey('legalHeirs'), isFalse);
    });
  });

  group('VaultDocument — columns win, note JSON is the fallback', () {
    VaultDocument doc({
      bool? hiddenColumn,
      Map<String, dynamic> sharedFields = const {},
      Map<String, dynamic>? sharedData,
      String? note,
    }) =>
        VaultDocument(
          id: 'd1',
          vaultId: 'v1',
          sharedBy: 'me',
          objectPath: 'uid/file.pdf',
          name: 'Deed',
          hiddenColumn: hiddenColumn,
          sharedFields: sharedFields,
          sharedData: sharedData,
          note: note,
          createdAt: DateTime(2026, 9, 9),
        );

    test('the is_hidden column decides once the migration is applied', () {
      expect(doc(hiddenColumn: true).isHidden, isTrue);
      // The column wins even when a stale note says otherwise, so a row
      // rewritten by the RPC is not overruled by leftover JSON.
      expect(
        doc(hiddenColumn: false, note: jsonEncode({'hidden': true})).isHidden,
        isFalse,
      );
    });

    test('before the migration the note flag still works', () {
      // hiddenColumn null = the column is not in the row at all. Treating that
      // as "false" would silently un-hide every document already hidden.
      expect(doc(note: jsonEncode({'hidden': true})).isHidden, isTrue);
      expect(doc(note: jsonEncode({'active': false})).isHidden, isTrue);
      expect(doc(note: jsonEncode({'hidden': false})).isHidden, isFalse);
    });

    test('a plain human note is not mistaken for config', () {
      expect(doc(note: 'Keep this for the bank').isHidden, isFalse);
      expect(doc(note: '{not really json}').isHidden, isFalse);
      expect(doc(note: '{not really json}').customDisclosure, isNull);
    });

    test('disclosure and data read from columns, then from the note', () {
      final fromColumns = doc(
        sharedFields: {'price': false},
        sharedData: {'city': 'Pune'},
      );
      expect(fromColumns.customDisclosure, {'price': false});
      expect(fromColumns.disclosedData, {'city': 'Pune'});
      expect(fromColumns.isRedacted, isTrue);

      final fromNote = doc(
        note: jsonEncode({
          'fields': {'price': false},
          'data': {'city': 'Pune'},
        }),
      );
      expect(fromNote.customDisclosure, {'price': false});
      expect(fromNote.disclosedData, {'city': 'Pune'});
      expect(fromNote.isRedacted, isTrue);
    });

    test('nothing withheld is not reported as a partial share', () {
      expect(doc(sharedFields: {'price': true, 'city': true}).isRedacted,
          isFalse);
      expect(doc().isRedacted, isFalse);
    });

    test('fromRow tolerates a database without the new columns', () {
      final row = <String, dynamic>{
        'id': 'd1',
        'vault_id': 'v1',
        'shared_by': 'me',
        'object_path': 'uid/file.pdf',
        'name': 'Deed',
        'source_id': '11111111-2222-3333-4444-555555555555',
        'note': jsonEncode({'hidden': true}),
        'created_at': '2026-09-09T00:00:00Z',
      };
      final parsed = VaultDocument.fromRow(row);
      expect(parsed.hiddenColumn, isNull);
      expect(parsed.isHidden, isTrue);
      expect(parsed.sharedFields, isEmpty);
      // source_ref falls back to source_id so provenance still resolves.
      expect(parsed.sourceRef, '11111111-2222-3333-4444-555555555555');
    });
  });

  group('WalletMediaSync — is this an upload or a device file?', () {
    test('a bucket object path is recognised', () {
      expect(
        WalletMediaSync.isRemote(
            '3f2504e0-4f89-11d3-9a0c-0305e82c3301/1757000000.jpg'),
        isTrue,
      );
    });

    test('a device path is not', () {
      // The exact shape the image picker hands back — the value that used to be
      // written straight into w_property_wallet.image_path and synced as if it
      // meant something on another phone.
      expect(
        WalletMediaSync.isRemote(
            '/data/user/0/com.ino/cache/image_picker_1757.jpg'),
        isFalse,
      );
      expect(WalletMediaSync.isRemote(r'C:\Users\me\deed.pdf'), isFalse);
      expect(WalletMediaSync.isRemote(''), isFalse);
      expect(WalletMediaSync.isRemote(null), isFalse);
    });

    test('a uuid with no object after it is not an object path', () {
      expect(
        WalletMediaSync.isRemote('3f2504e0-4f89-11d3-9a0c-0305e82c3301/'),
        isFalse,
      );
      expect(
        WalletMediaSync.isRemote('3f2504e0-4f89-11d3-9a0c-0305e82c3301'),
        isFalse,
      );
    });
  });
}
