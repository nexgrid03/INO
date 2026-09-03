import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/document_protection_store.dart';
import 'package:inoapp/services/offline_document_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the rule that a document's biometric protection follows the DOCUMENT,
/// not the route used to reach it.
///
/// The offline library used to be a way around the lock: a document marked
/// protected demanded Face ID / fingerprint when opened from its wallet, but
/// its offline copy opened straight off disk with no check at all. Saving a
/// document offline silently downgraded its protection.
///
/// What makes the fix work is that [OfflineDoc.id] is the ORIGINAL document
/// row's id - the same key [DocumentProtectionStore] files the flag under - so
/// `OfflineDocumentsScreen._open` can ask the same store the wallet list asks.
/// These tests pin that relationship, because if the offline entry ever started
/// carrying its own generated id the gate would silently stop matching and the
/// bypass would come back with nothing failing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DocumentProtectionStore.instance.clear();
    OfflineDocumentStore.instance.reset();
  });

  test('an offline copy keeps the document id its protection is keyed to', () {
    const docId = 'doc-abc-123';
    final entry = OfflineDoc(
      id: docId,
      name: 'Passport.pdf',
      wallet: 'Identity Wallet',
      relPath: 'offline_docs/u1/doc-abc-123.pdf',
      localPath: '/data/offline_docs/u1/doc-abc-123.pdf',
      objectPath: 'u1/passport.pdf',
      sizeBytes: 2048,
      savedAt: DateTime(2026, 7, 1),
    );

    // The id is the join between the two stores. Not a copy, not a derivative.
    expect(entry.id, docId);
  });

  test('protecting a document also protects its offline copy', () async {
    const docId = 'doc-protected-1';
    await DocumentProtectionStore.instance.setProtected(docId, true);

    final entry = OfflineDoc(
      id: docId,
      name: 'Aadhaar.jpg',
      wallet: 'Identity Wallet',
      relPath: 'offline_docs/u1/doc-protected-1.jpg',
      localPath: '/data/offline_docs/u1/doc-protected-1.jpg',
      objectPath: 'u1/aadhaar.jpg',
      sizeBytes: 1024,
      savedAt: DateTime(2026, 7, 1),
    );

    // This is the exact lookup the offline screen performs before opening.
    expect(DocumentProtectionStore.instance.isProtected(entry.id), isTrue);
  });

  test('an unprotected document opens offline without a prompt', () async {
    final entry = OfflineDoc(
      id: 'doc-open-1',
      name: 'Notes.pdf',
      wallet: 'Document Wallet',
      relPath: 'offline_docs/u1/doc-open-1.pdf',
      localPath: '/data/offline_docs/u1/doc-open-1.pdf',
      objectPath: 'u1/notes.pdf',
      sizeBytes: 512,
      savedAt: DateTime(2026, 7, 1),
    );
    expect(DocumentProtectionStore.instance.isProtected(entry.id), isFalse);
  });

  test('removing protection releases the offline copy too', () async {
    const docId = 'doc-toggle-1';
    await DocumentProtectionStore.instance.setProtected(docId, true);
    expect(DocumentProtectionStore.instance.isProtected(docId), isTrue);

    await DocumentProtectionStore.instance.setProtected(docId, false);
    expect(DocumentProtectionStore.instance.isProtected(docId), isFalse);
  });

  test('the id survives a JSON round trip through shared_preferences', () {
    // The offline library is persisted as JSON. If the id were dropped or
    // renamed in serialisation, the protection lookup would silently return
    // false for every restored entry - the bypass, reintroduced by a typo.
    const docId = 'doc-roundtrip-1';
    final entry = OfflineDoc(
      id: docId,
      name: 'PAN.jpg',
      wallet: 'Identity Wallet',
      relPath: 'offline_docs/u1/doc-roundtrip-1.jpg',
      localPath: '/data/offline_docs/u1/doc-roundtrip-1.jpg',
      objectPath: 'u1/pan.jpg',
      sizeBytes: 900,
      savedAt: DateTime(2026, 7, 1),
    );

    final restored = OfflineDoc.fromJson(entry.toJson());
    expect(restored.id, docId);
    expect(restored.localPath, entry.localPath);
  });
}
