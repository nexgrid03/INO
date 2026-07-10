import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/reminder_store.dart';
import 'package:inoapp/models/reminder_models.dart';
import 'package:inoapp/services/app_settings.dart';
import 'package:inoapp/services/category_store.dart';
import 'package:inoapp/services/global_search_service.dart';
import 'package:inoapp/services/notification_center.dart';
import 'package:inoapp/services/session_reset.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifies **client-side data isolation**: when one account signs out, none of
/// the process-wide singletons keep the previous user's data, so the next
/// account that signs in on the same device starts from a blank slate.
///
/// (The server-side half — Row Level Security — is enforced by
/// `supabase/migrations/20260710000000_user_data_isolation.sql` and can only be
/// exercised against a live Supabase project; see DATA_ISOLATION.md for the SQL
/// two-user test.)
Reminder _reminder(String id, String title) => Reminder(
      id: id,
      title: title,
      subtitle: 'test',
      category: ReminderCategory.documents,
      priority: ReminderPriority.important,
      date: dateOnly(DateTime.now()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReminderStore.instance.reset();
  });

  group('ReminderStore.clear (account switch)', () {
    test('drops all reminders and the loaded flag', () async {
      // Simulate "User A" having loaded and created reminders.
      await ReminderStore.instance.ensureLoaded(); // marks the store loaded
      ReminderStore.instance.add(_reminder('a1', 'User A · Passport'));
      ReminderStore.instance.add(_reminder('a2', 'User A · Insurance'));
      expect(ReminderStore.instance.active, isNotEmpty);
      expect(ReminderStore.instance.isLoaded, isTrue);

      // User A signs out.
      ReminderStore.instance.clear();

      // Nothing of User A's remains, and the store is un-loaded so User B's
      // ensureLoaded() actually re-hydrates instead of returning A's cache.
      expect(ReminderStore.instance.active, isEmpty);
      expect(ReminderStore.instance.completed, isEmpty);
      expect(ReminderStore.instance.isEmpty, isTrue);
      expect(ReminderStore.instance.isLoaded, isFalse);
    });
  });

  group('CategoryStore.clear (account switch)', () {
    test('removes user-created custom categories but keeps built-ins', () async {
      await CategoryStore.instance.load();
      await CategoryStore.instance.add(const DocumentCategory(
        name: 'User A Secret Project',
        iconKey: 'folder',
        colorValue: 0xFF16A34A,
      ));
      expect(CategoryStore.instance.exists('User A Secret Project'), isTrue);

      await CategoryStore.instance.clear();

      expect(CategoryStore.instance.custom, isEmpty);
      expect(CategoryStore.instance.exists('User A Secret Project'), isFalse);
      // Built-in categories are const and always available.
      expect(CategoryStore.instance.exists('Identity'), isTrue);
    });
  });

  group('NotificationCenter.clear (account switch)', () {
    test('empties the feed and its read/dismissed state', () async {
      // Persisted read/dismissed ids are stored under GLOBAL keys.
      await NotificationCenter.instance.markRead('rem-a1');
      await NotificationCenter.instance.dismiss('doc-a2');

      await NotificationCenter.instance.clear();

      expect(NotificationCenter.instance.notifications, isEmpty);
      expect(NotificationCenter.instance.unreadCount, 0);
      expect(NotificationCenter.instance.isLoaded, isFalse);
    });
  });

  group('GlobalSearchService.clear (account switch)', () {
    test('drops recent search history', () async {
      await GlobalSearchService.instance.addRecent('Aadhaar');
      await GlobalSearchService.instance.addRecent('Passport');
      expect(await GlobalSearchService.instance.recentSearches(), isNotEmpty);

      await GlobalSearchService.instance.clear();

      expect(await GlobalSearchService.instance.recentSearches(), isEmpty);
    });
  });

  group('AppSettings.resetAccountScoped (account switch)', () {
    test('resets account state to defaults but keeps the device language',
        () async {
      await AppSettings.instance.setLanguage('hi');
      await AppSettings.instance.setTwoFactor(true);
      await AppSettings.instance.setNotifications(false);
      await AppSettings.instance.markBackedUpNow();

      await AppSettings.instance.resetAccountScoped();

      expect(AppSettings.instance.twoFactor.value, isFalse);
      expect(AppSettings.instance.notifications.value, isTrue); // default
      expect(AppSettings.instance.lastBackupAt.value, isNull);
      // Language is a DEVICE preference — preserved across the account switch.
      expect(AppSettings.instance.language.value, 'hi');
    });
  });

  group('SessionReset.clear (full sign-out)', () {
    test('wipes every user-scoped cache in one call', () async {
      await ReminderStore.instance.ensureLoaded();
      ReminderStore.instance.add(_reminder('a1', 'User A · Passport'));
      await CategoryStore.instance.load();
      await CategoryStore.instance.add(const DocumentCategory(
        name: 'User A Category',
        iconKey: 'folder',
        colorValue: 0xFF16A34A,
      ));
      await GlobalSearchService.instance.addRecent('User A search');
      await AppSettings.instance.setTwoFactor(true);

      await SessionReset.instance.clear();

      expect(ReminderStore.instance.isEmpty, isTrue);
      expect(ReminderStore.instance.isLoaded, isFalse);
      expect(CategoryStore.instance.custom, isEmpty);
      expect(NotificationCenter.instance.isLoaded, isFalse);
      expect(await GlobalSearchService.instance.recentSearches(), isEmpty);
      expect(AppSettings.instance.twoFactor.value, isFalse);
    });
  });
}
