import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/reminder_repository.dart';
import 'package:inoapp/data/reminder_store.dart';
import 'package:inoapp/models/property_models.dart';
import 'package:inoapp/models/reminder_models.dart';
import 'package:inoapp/services/property_store.dart';

class _FakeReminderRepository implements ReminderRepository {
  final List<Reminder> items = [];

  @override
  Future<ReminderData> load() async {
    final today = dateOnly(DateTime.now());
    return ReminderData(
      today: today,
      reminders: List.from(items),
      completed: const [],
      summary: ReminderSummary(
        dueToday: 0,
        upcomingThisWeek: items.length,
        expiringSoon: items.length,
        completedThisMonth: 0,
      ),
    );
  }

  @override
  Future<Reminder> add(Reminder reminder) async {
    items.removeWhere((r) => r.id == reminder.id);
    items.add(reminder);
    return reminder;
  }

  @override
  Future<void> remove(String id) async {
    items.removeWhere((r) => r.id == id);
  }

  @override
  Future<void> setCompleted(String id, bool completed) async {
    final idx = items.indexWhere((r) => r.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(completed: completed);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeReminderRepository fakeRepo;

  setUp(() {
    fakeRepo = _FakeReminderRepository();
    ReminderRepository.instance = fakeRepo;
    ReminderStore.instance.clear();
  });

  group('Property Model & Store Reminder Mapping', () {
    test('Property serializes and deserializes reminderDate correctly', () {
      final dueDate = DateTime.utc(2026, 10, 20, 14, 30);
      final property = Property(
        id: 'prop-1',
        name: 'Hilltop Villa',
        type: PropertyType.villa,
        status: PropertyStatus.owned,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        reminderNote: 'Property tax due',
        reminderDate: dueDate,
      );

      final json = property.toJson();
      expect(json['reminderDate'], dueDate.toIso8601String());
      expect(json['reminderNote'], 'Property tax due');

      final restored = Property.fromJson(json);
      expect(restored.reminderDate, dueDate);
      expect(restored.reminderNote, 'Property tax due');
    });

    test('Property.copyWith updates and clears reminderDate properly', () {
      final dueDate = DateTime.utc(2026, 11, 1, 9, 0);
      final property = Property(
        id: 'prop-2',
        name: 'Sunny Apartment',
        type: PropertyType.apartment,
        status: PropertyStatus.rented,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        reminderDate: dueDate,
      );

      // Update date
      final newDate = DateTime.utc(2026, 12, 1, 10, 0);
      final updated = property.copyWith(reminderDate: newDate);
      expect(updated.reminderDate, newDate);

      // Clear date
      final cleared = updated.copyWith(clearReminderDate: true);
      expect(cleared.reminderDate, isNull);
    });

    test('PropertyStore toRow and fromRow maps reminder_date', () async {
      final dueDate = DateTime.utc(2026, 12, 15, 9, 0);
      final property = Property(
        id: 'prop-3',
        name: 'Commercial Complex',
        type: PropertyType.commercial,
        status: PropertyStatus.owned,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        reminderNote: 'Fire inspection due',
        reminderDate: dueDate,
      );

      final store = PropertyStore.instance;
      final row = await store.toRow(property);
      expect(row['reminder_date'], dueDate.toIso8601String());
      expect(row['reminder_note'], 'Fire inspection due');

      final fromRow = await store.fromRow({...row, 'id': 'db-uuid-123'});
      expect(fromRow.id, 'db-uuid-123');
      expect(fromRow.reminderDate, dueDate);
      expect(fromRow.reminderNote, 'Fire inspection due');
    });
  });

  group('Property Reminder Integration with ReminderStore', () {
    test('Property reminder is added to ReminderStore under property category', () async {
      final dueDate = DateTime.now().add(const Duration(days: 10));
      const propertyId = 'prop_abc123';
      const propertyName = 'Palm Grove Residency';
      const note = 'Semi-annual property tax';

      final reminder = Reminder(
        id: 'prop-$propertyId',
        title: propertyName,
        subtitle: 'Property · $note',
        category: ReminderCategory.property,
        priority: ReminderPriority.important,
        date: dueDate,
      );

      final added = await ReminderStore.instance.add(reminder);
      expect(added.id, 'prop-$propertyId');
      expect(added.category, ReminderCategory.property);
      expect(added.priority, ReminderPriority.important);
      expect(added.title, propertyName);
      expect(added.subtitle, contains(note));

      // Verifying presence in ReminderStore
      expect(ReminderStore.instance.active.length, 1);
      final matching = ReminderStore.instance.activeMatching(ReminderFilterKind.property);
      expect(matching.length, 1);
      expect(matching.first.id, 'prop-$propertyId');
    });

    test('Clearing or deleting removes property reminder from ReminderStore', () async {
      const reminderId = 'prop-prop_def456';
      final reminder = Reminder(
        id: reminderId,
        title: 'Sunset Villa',
        subtitle: 'Property · Lease renewal',
        category: ReminderCategory.property,
        priority: ReminderPriority.important,
        date: DateTime.now().add(const Duration(days: 30)),
      );

      await ReminderStore.instance.add(reminder);
      expect(ReminderStore.instance.active.any((r) => r.id == reminderId), isTrue);

      // Simulate property reminder removal on delete or date cleared
      final toRemove = ReminderStore.instance.active.firstWhere((r) => r.id == reminderId);
      ReminderStore.instance.remove(toRemove);

      expect(ReminderStore.instance.active.any((r) => r.id == reminderId), isFalse);
    });
  });
}
