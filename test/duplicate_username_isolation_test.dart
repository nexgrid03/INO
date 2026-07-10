import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/reminder_repository.dart';
import 'package:inoapp/data/reminder_store.dart';
import 'package:inoapp/models/reminder_models.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/services/category_store.dart';
import 'package:inoapp/services/global_search_service.dart';
import 'package:inoapp/services/notification_center.dart';
import 'package:inoapp/services/session_reset.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Proves that user identity/ownership is keyed **exclusively on auth_user_id**,
/// never on username / display name / full name / email / phone. Two users who
/// share the *same* name "Ramesh" (and identical profile fields) must remain
/// completely isolated — no data, cache, or search crossover.
///
/// The database half is enforced by RLS (`auth_user_id = auth.uid()`) and can
/// only run against a live Supabase; here we model that partitioning with a fake
/// repository keyed on auth_user_id and drive the REAL `ReminderStore` /
/// `SessionReset` / caches through a same-name account switch.

/// A fake reminders backend that partitions rows by auth_user_id — exactly what
/// RLS + the `.eq('auth_user_id', uid)` filter do server-side. Ownership is the
/// uid, never the user's name.
class _FakeReminderRepository implements ReminderRepository {
  final Map<String, List<Reminder>> _byUser = {};

  /// The currently "signed-in" user's auth id (stand-in for auth.uid()).
  String currentUid = '';

  void seed(String uid, Reminder r) => (_byUser[uid] ??= []).add(r);

  @override
  Future<ReminderData> load() async {
    final today = dateOnly(DateTime.now());
    final mine = List<Reminder>.from(_byUser[currentUid] ?? const <Reminder>[]);
    return ReminderData(
      today: today,
      reminders: mine.where((r) => !r.completed).toList(),
      completed: mine.where((r) => r.completed).toList(),
      summary: const ReminderSummary(
        dueToday: 0,
        upcomingThisWeek: 0,
        expiringSoon: 0,
        completedThisMonth: 0,
      ),
    );
  }

  @override
  Future<Reminder> add(Reminder reminder) async {
    (_byUser[currentUid] ??= []).add(reminder);
    return reminder;
  }

  @override
  Future<void> setCompleted(String id, bool completed) async {
    final list = _byUser[currentUid];
    if (list == null) return;
    final i = list.indexWhere((e) => e.id == id);
    if (i != -1) list[i] = list[i].copyWith(completed: completed);
  }

  @override
  Future<void> remove(String id) async =>
      _byUser[currentUid]?.removeWhere((e) => e.id == id);
}

Reminder _reminder(String id, String title) => Reminder(
      id: id,
      title: title,
      subtitle: '',
      category: ReminderCategory.documents,
      priority: ReminderPriority.normal,
      date: dateOnly(DateTime.now()),
    );

/// A profile for a user literally named "Ramesh". Same name for both users; only
/// [authUserId] differs.
UserProfile _ramesh({required String authUserId, required String id}) =>
    UserProfile(
      id: id,
      authUserId: authUserId,
      fullName: 'Ramesh',
      email: 'ramesh@example.com', // identical email prefix on purpose
      phone: '+919999999999', // identical phone on purpose
      preferredLanguage: 'en',
      biometricEnabled: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fake = _FakeReminderRepository();
  final realRepo = ReminderRepository.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReminderRepository.instance = fake;
    fake._byUser.clear();
    ReminderStore.instance.reset();
  });

  tearDown(() {
    ReminderRepository.instance = realRepo; // don't leak the fake to other files
  });

  group('reminders are owned by auth_user_id, not username', () {
    test('two users both named "Ramesh" never see each other\'s reminders',
        () async {
      const uidA = 'auth-uid-A';
      const uidB = 'auth-uid-B';

      // Ramesh A signs in and has a reminder.
      fake.seed(uidA, _reminder('a1', "Ramesh A · Passport"));
      fake.currentUid = uidA;
      ReminderStore.instance.reset();
      await ReminderStore.instance.ensureLoaded();
      expect(ReminderStore.instance.active.map((r) => r.id), ['a1']);

      // Ramesh A signs out (cache reset) → Ramesh B (same name!) signs in.
      await SessionReset.instance.clear();
      fake.currentUid = uidB;
      await ReminderStore.instance.ensureLoaded();

      // B sees NONE of A's reminders despite the identical name.
      expect(ReminderStore.instance.active, isEmpty,
          reason: 'duplicate username must not leak reminders');

      // B creates their own; still no crossover.
      fake.seed(uidB, _reminder('b1', "Ramesh B · Insurance"));
      ReminderStore.instance.reset();
      await ReminderStore.instance.ensureLoaded();
      expect(ReminderStore.instance.active.map((r) => r.id), ['b1']);

      // Switch back to A → only A's reminder, never B's.
      await SessionReset.instance.clear();
      fake.currentUid = uidA;
      await ReminderStore.instance.ensureLoaded();
      expect(ReminderStore.instance.active.map((r) => r.id), ['a1']);
    });
  });

  group('device caches do not cross over between two same-named users', () {
    test('custom categories are cleared on sign-out (no username crossover)',
        () async {
      await CategoryStore.instance.load();
      await CategoryStore.instance.add(const DocumentCategory(
        name: 'Ramesh A Private',
        iconKey: 'folder',
        colorValue: 0xFF16A34A,
      ));
      expect(CategoryStore.instance.exists('Ramesh A Private'), isTrue);

      // Ramesh A → Ramesh B account switch.
      await SessionReset.instance.clear();

      expect(CategoryStore.instance.exists('Ramesh A Private'), isFalse);
      expect(CategoryStore.instance.custom, isEmpty);
    });

    test('recent search history is cleared on sign-out', () async {
      await GlobalSearchService.instance.addRecent('Ramesh A secret query');
      expect(await GlobalSearchService.instance.recentSearches(), isNotEmpty);

      await SessionReset.instance.clear();

      expect(await GlobalSearchService.instance.recentSearches(), isEmpty);
    });

    test('notification read/dismissed state is cleared on sign-out', () async {
      await NotificationCenter.instance.markRead('rem-a1');
      await NotificationCenter.instance.dismiss('doc-a1');

      await SessionReset.instance.clear();

      expect(NotificationCenter.instance.unreadCount, 0);
      expect(NotificationCenter.instance.notifications, isEmpty);
    });
  });

  group('identity model keys on authUserId, not name/email/phone', () {
    test('two identical-name profiles are distinguished only by authUserId', () {
      final a = _ramesh(authUserId: 'auth-uid-A', id: 'row-A');
      final b = _ramesh(authUserId: 'auth-uid-B', id: 'row-B');

      // Same human-facing identity …
      expect(a.fullName, b.fullName);
      expect(a.email, b.email);
      expect(a.phone, b.phone);

      // … but distinct owners. Ownership must derive from authUserId only.
      expect(a.authUserId, isNot(b.authUserId));
      expect(a.id, isNot(b.id));
    });
  });
}
