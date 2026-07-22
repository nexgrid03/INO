import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inoapp/models/note_models.dart';
import 'package:inoapp/services/notes_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = NotesStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store.reset();
    await store.ensureLoaded();
  });

  test('starts completely empty', () {
    expect(store.isEmpty, isTrue);
    expect(store.active, isEmpty);
    expect(store.archived, isEmpty);
  });

  test('add creates a note', () async {
    await store.add(
      title: 'Locker code hint',
      description: 'first pet + year',
      category: NoteCategory.personal,
      tags: ['secret'],
    );
    expect(store.isEmpty, isFalse);
    expect(store.active.length, 1);
    expect(store.active.first.title, 'Locker code hint');
    expect(store.active.first.category, NoteCategory.personal);
  });

  test('pinned notes sort ahead of unpinned', () async {
    final a = await store.add(
        title: 'A', description: '', category: NoteCategory.other);
    await store.add(title: 'B', description: '', category: NoteCategory.other);
    await store.togglePin(a.id);
    expect(store.active.first.id, a.id);
    expect(store.active.first.isPinned, isTrue);
  });

  test('archive removes from active and appears in archived', () async {
    final n = await store.add(
        title: 'Old', description: '', category: NoteCategory.tax);
    await store.toggleArchive(n.id);
    expect(store.active, isEmpty);
    expect(store.archived.length, 1);
    expect(store.archived.first.id, n.id);
  });

  test('favorite toggles', () async {
    final n = await store.add(
        title: 'Fav', description: '', category: NoteCategory.banking);
    await store.toggleFavorite(n.id);
    expect(store.byId(n.id)!.isFavorite, isTrue);
  });

  test('update edits the note content', () async {
    final n = await store.add(
        title: 'Draft', description: 'x', category: NoteCategory.business);
    await store.update(n.copyWith(
        title: 'Final', description: 'done', category: NoteCategory.investments));
    final updated = store.byId(n.id)!;
    expect(updated.title, 'Final');
    expect(updated.description, 'done');
    expect(updated.category, NoteCategory.investments);
  });

  test('remove deletes the note', () async {
    final n = await store.add(
        title: 'Temp', description: '', category: NoteCategory.health);
    await store.remove(n.id);
    expect(store.isEmpty, isTrue);
  });

  test('notes persist across a reload (survive app restart)', () async {
    await store.add(
        title: 'Persisted',
        description: 'still here after restart',
        category: NoteCategory.property);

    // Simulate an app restart: drop in-memory state, then hydrate from storage.
    store.reset();
    await store.ensureLoaded();

    expect(store.active.length, 1);
    expect(store.active.first.title, 'Persisted');
  });

  test('clear empties the in-memory cache', () async {
    await store.add(
        title: 'X', description: '', category: NoteCategory.other);
    store.clear();
    expect(store.isEmpty, isTrue);
  });

  test('Note.matches searches title, description, category and tags', () {
    final note = Note(
      id: '1',
      title: 'Wifi password hint',
      description: 'router sticker',
      category: NoteCategory.personal,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
      tags: const ['home'],
    );
    expect(note.matches('wifi'), isTrue);
    expect(note.matches('router'), isTrue);
    expect(note.matches('personal'), isTrue);
    expect(note.matches('home'), isTrue);
    expect(note.matches('office'), isFalse);
    expect(note.matches(''), isTrue);
  });
}
