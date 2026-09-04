import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/offline_document_store.dart';

/// Guards the rule that an offline copy is identified by where it sits
/// *relative to the app documents directory*, never by an absolute path.
///
/// The app's documents container is re-created at a new path whenever the OS
/// decides to (every iOS update rewrites the UUID in
/// `/var/mobile/Containers/Data/Application/<UUID>/Documents`). The store drops
/// any entry whose file does not exist, so an absolute path written before the
/// move resolves to nothing and the ENTIRE offline library silently empties
/// itself - the one failure the offline library cannot afford, because it is
/// discovered when there is no internet to re-download anything.
///
/// These tests pin the two halves of the fix: new entries carry a relative
/// path, and entries written before it existed have one recovered for them.
void main() {
  OfflineDoc entry({
    required String relPath,
    required String localPath,
  }) =>
      OfflineDoc(
        id: 'doc-1',
        name: 'Passport.pdf',
        wallet: 'Identity Wallet',
        relPath: relPath,
        localPath: localPath,
        objectPath: 'u1/passport.pdf',
        sizeBytes: 2048,
        savedAt: DateTime(2026, 7, 1),
      );

  test('the relative path survives a JSON round trip', () {
    final doc = entry(
      relPath: 'offline_docs/u1/doc-1.pdf',
      localPath: '/old/Documents/offline_docs/u1/doc-1.pdf',
    );
    final restored = OfflineDoc.fromJson(doc.toJson());
    expect(restored.relPath, 'offline_docs/u1/doc-1.pdf');
  });

  test('a container move re-resolves to the file in the NEW container', () {
    final doc = entry(
      relPath: 'offline_docs/u1/doc-1.pdf',
      localPath: '/Containers/OLD-UUID/Documents/offline_docs/u1/doc-1.pdf',
    );

    // What the store does on every launch: rebuild against today's directory.
    final moved = doc.resolvedIn('/Containers/NEW-UUID/Documents');

    expect(
      moved.localPath,
      '/Containers/NEW-UUID/Documents/offline_docs/u1/doc-1.pdf',
    );
    expect(moved.relPath, doc.relPath, reason: 'the durable half is stable');
    expect(moved.id, doc.id);
    expect(moved.sizeBytes, doc.sizeBytes);
  });

  test('a legacy entry with only an absolute path gets one recovered', () {
    // Exactly what `shared_preferences` holds for a doc saved by a build that
    // predates `relPath`. Throwing it away would lose the user's library.
    final restored = OfflineDoc.fromJson({
      'id': 'doc-legacy',
      'name': 'PAN.jpg',
      'wallet': 'Identity Wallet',
      'localPath':
          '/Containers/OLD-UUID/Documents/offline_docs/u1/doc-legacy.jpg',
      'objectPath': 'u1/pan.jpg',
      'sizeBytes': 900,
      'savedAt': '2026-07-01T00:00:00.000',
    });

    expect(restored.relPath, 'offline_docs/u1/doc-legacy.jpg');
    expect(
      restored.resolvedIn('/Containers/NEW-UUID/Documents').localPath,
      '/Containers/NEW-UUID/Documents/offline_docs/u1/doc-legacy.jpg',
    );
  });

  test('a Windows-style legacy path is recovered too', () {
    final restored = OfflineDoc.fromJson({
      'id': 'doc-win',
      'name': 'Notes.pdf',
      'wallet': 'Document Wallet',
      'localPath': r'C:\Users\a\Documents\offline_docs\u1\doc-win.pdf',
      'objectPath': 'u1/notes.pdf',
      'sizeBytes': 512,
      'savedAt': '2026-07-01T00:00:00.000',
    });

    expect(restored.relPath, 'offline_docs/u1/doc-win.pdf');
  });

  test('a path outside the offline tree keeps its absolute path as-is', () {
    // No relative path can be derived, so the stored absolute path stays the
    // only way to find the file - the store falls back to it rather than
    // discarding the entry.
    final restored = OfflineDoc.fromJson({
      'id': 'doc-elsewhere',
      'name': 'Stray.pdf',
      'wallet': 'Document Wallet',
      'localPath': '/somewhere/else/stray.pdf',
      'objectPath': 'u1/stray.pdf',
      'sizeBytes': 100,
      'savedAt': '2026-07-01T00:00:00.000',
    });

    expect(restored.relPath, isEmpty);
    expect(restored.localPath, '/somewhere/else/stray.pdf');
    expect(
      restored.resolvedIn('/Containers/NEW-UUID/Documents').localPath,
      '/somewhere/else/stray.pdf',
      reason: 'with no relative path there is nothing to re-resolve against',
    );
  });

  test('the offline folder name is the one the paths are built from', () {
    // `relPath` recovery keys off this exact segment; renaming the folder
    // without migrating would orphan every saved document.
    expect(OfflineDocumentStore.dirName, 'offline');
  });
}
