import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/property_models.dart';
import 'package:inoapp/services/document_protection_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PropertyAttachment Tests', () {
    test('roundtrip serialization with all fields including biometrics and size',
        () {
      final attachment = PropertyAttachment(
        id: 'att_123',
        kind: PropertyDocKind.saleDeed,
        name: 'Sale Deed 2026',
        path: '/storage/emulated/0/Documents/deed.pdf',
        linkedDocumentId: 'doc_vault_99',
        addedAt: DateTime(2026, 9, 8, 12, 0, 0),
        isBiometricProtected: true,
        fileSize: 2500000,
        mimeType: 'application/pdf',
      );

      expect(attachment.isPdf, isTrue);
      expect(attachment.isImage, isFalse);
      expect(attachment.fileExtension, 'pdf');
      expect(attachment.formattedSize, '2.4 MB');

      final json = attachment.toJson();
      expect(json['id'], 'att_123');
      expect(json['kind'], 'saleDeed');
      expect(json['name'], 'Sale Deed 2026');
      expect(json['path'], '/storage/emulated/0/Documents/deed.pdf');
      expect(json['documentId'], 'doc_vault_99');
      expect(json['isBiometricProtected'], isTrue);
      expect(json['fileSize'], 2500000);
      expect(json['mimeType'], 'application/pdf');

      final deserialized = PropertyAttachment.fromJson(json);
      expect(deserialized.id, attachment.id);
      expect(deserialized.kind, attachment.kind);
      expect(deserialized.name, attachment.name);
      expect(deserialized.path, attachment.path);
      expect(deserialized.linkedDocumentId, attachment.linkedDocumentId);
      expect(deserialized.isBiometricProtected, isTrue);
      expect(deserialized.fileSize, 2500000);
      expect(deserialized.mimeType, 'application/pdf');
    });

    test('image getters identify image extensions correctly', () {
      final img = PropertyAttachment(
        id: 'att_456',
        kind: PropertyDocKind.buildingPlan,
        name: 'Blueprint.png',
        path: '/storage/emulated/0/Pictures/Blueprint.png',
        fileSize: 512000,
      );

      expect(img.isImage, isTrue);
      expect(img.isPdf, isFalse);
      expect(img.fileExtension, 'png');
      expect(img.formattedSize, '500.0 KB');
    });

    test('copyWith updates fields while preserving others', () {
      final orig = PropertyAttachment(
        id: 'att_789',
        kind: PropertyDocKind.taxReceipt,
        name: 'Tax 2025',
        isBiometricProtected: false,
      );

      final updated = orig.copyWith(
        name: 'Tax 2026',
        isBiometricProtected: true,
      );

      expect(updated.id, 'att_789');
      expect(updated.kind, PropertyDocKind.taxReceipt);
      expect(updated.name, 'Tax 2026');
      expect(updated.isBiometricProtected, isTrue);
    });

    test('DocumentProtectionStore toggles protection for attachment IDs',
        () async {
      final store = DocumentProtectionStore.instance;
      await store.load();

      expect(store.isProtected('att_test_protect'), isFalse);

      await store.setProtected('att_test_protect', true);
      expect(store.isProtected('att_test_protect'), isTrue);

      await store.setProtected('att_test_protect', false);
      expect(store.isProtected('att_test_protect'), isFalse);
    });
  });
}
