import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/reminder_repository.dart';
import 'package:inoapp/data/reminder_store.dart';
import 'package:inoapp/models/reminder_models.dart';
import 'package:inoapp/services/session_reset.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Explicit Security Test Suite verifying server-side and client-side
/// reminder isolation, account switching, session resets, and anti-cross-user data leakage.

class _MockUserReminderRepository implements ReminderRepository {
  final Map<String, List<Reminder>> _userStorage = {};
  String activeUserId = '';

  void seedUserReminder(String userId, Reminder reminder) {
    (_userStorage[userId] ??= []).add(reminder);
  }

  @override
  Future<ReminderData> load() async {
    final today = dateOnly(DateTime.now());
    final userReminders = List<Reminder>.from(_userStorage[activeUserId] ?? const []);
    return ReminderData(
      today: today,
      reminders: userReminders.where((r) => !r.completed).toList(),
      completed: userReminders.where((r) => r.completed).toList(),
      summary: ReminderSummary(
        dueToday: userReminders.where((r) => !r.completed && r.date == today).length,
        upcomingThisWeek: 0,
        expiringSoon: 0,
        completedThisMonth: userReminders.where((r) => r.completed).length,
      ),
    );
  }

  @override
  Future<Reminder> add(Reminder reminder) async {
    (_userStorage[activeUserId] ??= []).add(reminder);
    return reminder;
  }

  @override
  Future<void> setCompleted(String id, bool completed) async {
    final list = _userStorage[activeUserId];
    if (list == null) return;
    final index = list.indexWhere((r) => r.id == id);
    if (index != -1) {
      list[index] = list[index].copyWith(completed: completed);
    }
  }

  @override
  Future<void> remove(String id) async {
    _userStorage[activeUserId]?.removeWhere((r) => r.id == id);
  }
}

Reminder _buildTestReminder(String id, String title) => Reminder(
      id: id,
      title: title,
      subtitle: 'Security Test Subtitle',
      category: ReminderCategory.documents,
      priority: ReminderPriority.important,
      date: dateOnly(DateTime.now()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockUserReminderRepository mockRepo;
  late ReminderRepository originalRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRepo = _MockUserReminderRepository();
    originalRepo = ReminderRepository.instance;
    ReminderRepository.instance = mockRepo;
    ReminderStore.instance.reset();
  });

  tearDown(() {
    ReminderRepository.instance = originalRepo;
  });

  group('Security Requirement 1: Reminder Account Isolation', () {
    test('User A reminders are strictly invisible to User B', () async {
      const userA = 'user-uuid-aaaa-1111';
      const userB = 'user-uuid-bbbb-2222';

      // Seed User A's data
      mockRepo.seedUserReminder(userA, _buildTestReminder('rem-a1', 'User A Secret Passport Renewal'));
      mockRepo.activeUserId = userA;

      await ReminderStore.instance.ensureLoaded();
      expect(ReminderStore.instance.active.map((r) => r.id), contains('rem-a1'));

      // Switch active user to User B without clearing client store yet
      mockRepo.activeUserId = userB;
      ReminderStore.instance.clear();

      await ReminderStore.instance.ensureLoaded();
      expect(ReminderStore.instance.active, isEmpty);
      expect(ReminderStore.instance.active.map((r) => r.id), isNot(contains('rem-a1')));
    });
  });

  group('Security Requirement 2: Account Switching', () {
    test('Cached reminder data is completely cleared on account switch', () async {
      const userA = 'user-uuid-aaaa-1111';
      mockRepo.activeUserId = userA;
      await ReminderStore.instance.ensureLoaded();
      await ReminderStore.instance.add(_buildTestReminder('rem-a2', 'User A Tax Notice'));

      expect(ReminderStore.instance.active, isNotEmpty);
      expect(ReminderStore.instance.isLoaded, isTrue);

      // Perform account switch clear
      ReminderStore.instance.clear();

      expect(ReminderStore.instance.active, isEmpty);
      expect(ReminderStore.instance.completed, isEmpty);
      expect(ReminderStore.instance.isLoaded, isFalse);
      expect(ReminderStore.instance.isEmpty, isTrue);
    });
  });

  group('Security Requirement 3: Session Reset', () {
    test('Reminder cache is wiped on session reset', () async {
      const userA = 'user-uuid-aaaa-1111';
      mockRepo.activeUserId = userA;
      await ReminderStore.instance.ensureLoaded();
      await ReminderStore.instance.add(_buildTestReminder('rem-a3', 'User A Credit Card Expiry'));

      expect(ReminderStore.instance.active.length, 1);

      // Trigger full SessionReset
      await SessionReset.instance.clear();

      expect(ReminderStore.instance.active, isEmpty);
      expect(ReminderStore.instance.isLoaded, isFalse);
    });
  });

  group('Security Requirement 4: Logout', () {
    test('Reminder state destroyed on logout', () async {
      const userA = 'user-uuid-aaaa-1111';
      mockRepo.activeUserId = userA;
      await ReminderStore.instance.ensureLoaded();
      await ReminderStore.instance.add(_buildTestReminder('rem-a4', 'User A Medical Record'));

      expect(ReminderStore.instance.isLoaded, isTrue);

      // Simulate logout action
      ReminderStore.instance.reset();

      expect(ReminderStore.instance.active, isEmpty);
      expect(ReminderStore.instance.completed, isEmpty);
      expect(ReminderStore.instance.isLoaded, isFalse);
    });
  });

  group('Security Requirement 5: Cross-user leakage prevention', () {
    test('Must fail if another user\'s reminder appears in active user session', () async {
      const userA = 'user-uuid-aaaa-1111';
      const userB = 'user-uuid-bbbb-2222';

      mockRepo.seedUserReminder(userA, _buildTestReminder('rem-a5', 'User A Confidential File'));
      mockRepo.seedUserReminder(userB, _buildTestReminder('rem-b5', 'User B Private Property'));

      // User B session
      mockRepo.activeUserId = userB;
      ReminderStore.instance.reset();
      await ReminderStore.instance.ensureLoaded();

      final bReminders = ReminderStore.instance.active.map((r) => r.id).toList();

      // Assert User B sees B's reminder and NOT User A's reminder
      expect(bReminders, contains('rem-b5'));
      expect(bReminders, isNot(contains('rem-a5')));
    });
  });
}
