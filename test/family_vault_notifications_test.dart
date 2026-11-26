import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/notification_center.dart';
import 'package:inoapp/services/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Family Vault notifications migration & edge function', () {
    test('SQL migration configures invite + document share triggers & realtime',
        () {
      final sql = File(
              'supabase/migrations/20261126000000_family_vault_notifications.sql')
          .readAsStringSync();

      // Invite notification trigger
      expect(sql, contains('public.tg_vault_invitation_push()'));
      expect(sql, contains('on public.vault_invitations'));
      expect(sql, contains("'vault.invite'"));
      expect(sql, contains('v_invitee = new.invited_by'));

      // Shared document notification trigger excludes sharer and hidden docs
      expect(sql, contains('public.tg_vault_document_shared_push()'));
      expect(sql, contains('on public.vault_documents'));
      expect(sql, contains('after insert or update of is_hidden'));
      expect(sql, contains("'vault.document_shared'"));
      expect(sql, contains('if coalesce(new.is_hidden, false) then'));
      expect(sql, contains('m.auth_user_id <> new.shared_by'));

      // Realtime enabled for live in-app updates
      expect(
        sql,
        contains('alter publication supabase_realtime add table public.notification_outbox'),
      );
    });

    test('doc share fix SQL handles updates/re-shares & enables vault_documents realtime',
        () {
      final fixSql = File(
              'supabase/migrations/20261126010000_family_vault_doc_share_notif_fix.sql')
          .readAsStringSync();

      expect(fixSql, contains('after insert or update on public.vault_documents'));
      expect(fixSql, contains('m.auth_user_id <> new.shared_by'));
      expect(fixSql, contains("coalesce(new.updated_at, new.created_at)::text"));
      expect(
        fixSql,
        contains('alter publication supabase_realtime add table public.vault_documents'),
      );
    });

    test('send-push edge function includes outbox_id and supports client drainOnly',
        () {
      final fn = File('supabase/functions/send-push/index.ts').readAsStringSync();
      expect(fn, contains('outbox_id: row.id'));
      expect(fn, contains('isAuthenticatedDrain'));
      expect(fn, contains('admin.auth.getUser'));
    });
  });

  group('PushService & NotificationCenter Family Vault integration', () {
    test('reminderNotificationId uses outbox_id deterministically for vault pushes',
        () {
      final a = PushService.reminderNotificationId(
        const {'kind': 'vault.invite', 'outbox_id': 'outbox-123'},
        'fcm-msg-1',
      );
      final b = PushService.reminderNotificationId(
        const {'kind': 'vault.invite', 'outbox_id': 'outbox-123'},
        'fcm-msg-2',
      );
      expect(a, equals(b));
      expect(a, isNonNegative);

      // Explicit reminder_id still takes precedence
      final r1 = PushService.reminderNotificationId(
        const {'reminder_id': 'rem-1', 'outbox_id': 'outbox-123'},
        null,
      );
      final r2 = PushService.reminderNotificationId(
        const {'reminder_id': 'rem-1'},
        null,
      );
      expect(r1, equals(r2));
    });

    test('NotificationCenter.refresh succeeds safely when Supabase is uninitialized',
        () async {
      SharedPreferences.setMockInitialValues({});
      await NotificationCenter.instance.refresh();
      expect(NotificationCenter.instance.isLoaded, isTrue);
    });
  });
}
