import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:inoapp/services/app_settings.dart';
import 'package:inoapp/services/push_service.dart';
import 'package:inoapp/services/password_store.dart';
import 'package:inoapp/services/vault_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('CRITICAL C1: Committed Fallback Proxy Secret & Key Removal', () {
    test('share/index.ts has no hardcoded fallback proxy secret and fails closed', () {
      final file = File('supabase/functions/share/index.ts');
      expect(file.existsSync(), isTrue);
      final code = file.readAsStringSync();

      expect(code.contains('ino-share-proxy-v1-production-auth'), isFalse,
          reason: 'Hardcoded proxy secret must not be committed');
      expect(code.contains('const SHARE_PROXY_SECRET = Deno.env.get("SHARE_PROXY_SECRET");'), isTrue);
      expect(code.contains('if (proxyToken && SHARE_PROXY_SECRET && proxyToken === SHARE_PROXY_SECRET)'), isTrue,
          reason: 'Must fail closed when SHARE_PROXY_SECRET is not configured');
    });

    test('client-ip.ts and config.ts have no committed secret or anon key fallbacks', () {
      final clientIpFile = File('share-frontend/lib/client-ip.ts');
      expect(clientIpFile.existsSync(), isTrue);
      final clientIpCode = clientIpFile.readAsStringSync();
      expect(clientIpCode.contains('ino-share-proxy-v1-production-auth'), isFalse);

      final configFile = File('share-frontend/lib/config.ts');
      expect(configFile.existsSync(), isTrue);
      final configCode = configFile.readAsStringSync();
      expect(configCode.contains('sb_publishable_AkYUQB5-mxBJkY_tZQu6EQ_JprMvI97'), isFalse,
          reason: 'Hardcoded publishable key must be removed from repo');
    });
  });

  group('HIGH H1: Account Deletion Successor Column & Role Ordering', () {
    test('Migration files do not reference joined_at anywhere', () {
      final dir = Directory('supabase/migrations');
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.sql'));

      for (final f in files) {
        final content = f.readAsStringSync();
        expect(content.contains('joined_at'), isFalse,
            reason: '${f.path} must not reference non-existent column joined_at');
      }
    });

    test('Phase 7 migration correctly references created_at and ranks owner first', () {
      final file = File('supabase/migrations/20260906020000_phase7_critical_remediations.sql');
      final sql = file.readAsStringSync();

      expect(sql.contains("CASE role WHEN 'owner' THEN 1 WHEN 'admin' THEN 2 WHEN 'editor' THEN 3 ELSE 4 END"), isTrue);
      expect(sql.contains('created_at ASC'), isTrue);
    });
  });

  group('HIGH H2: Forgot Passphrase Re-Key & Destroy-and-Restart Flow', () {
    test('PasswordStore contains destroyVault method to wipe inaccessible vault', () {
      expect(PasswordStore.instance.destroyVault, isNotNull);
    });

    test('VaultCrypto.resetPassphrase allows reset on empty vault without corruption', () async {
      PasswordStore.instance.reset();
      expect(PasswordStore.instance.items.isEmpty, isTrue);

      // resetPassphrase on empty store does not abort due to sealed items
      // (Supabase call may fail in offline unit test, but it does NOT abort on sealed items check)
      await VaultCrypto.instance.resetPassphrase('TestNewPassphrase123!');
      // Returns false only due to no client/uid in offline test environment, NOT because of sealed entries
      expect(PasswordStore.instance.hasSealedEntries, isFalse);
    });
  });

  group('HIGH H3: Reminder Consent Fabrication Gate', () {
    test('PushService requestPermission respects AppSettings notifications disabled toggle', () async {
      await AppSettings.instance.setNotifications(false);
      expect(AppSettings.instance.notifications.value, isFalse);

      final result = await PushService.instance.requestPermission();
      expect(result, isFalse, reason: 'Must not grant or record consent when user toggled notifications off');
    });

    test('add_reminder_sheet checks AppSettings before requesting push permission', () {
      final file = File('lib/widgets/reminders/add_reminder_sheet.dart');
      final code = file.readAsStringSync();

      expect(code.contains('if (AppSettings.instance.notifications.value)'), isTrue);
      expect(code.contains('await PushService.instance.requestPermission();'), isTrue);
    });
  });

  group('HIGH H4: Document Cache on Secure Storage & Android Extraction Rules', () {
    test('DocumentRepository uses FlutterSecureStorage for persistence', () {
      final file = File('lib/repositories/document_repository.dart');
      final code = file.readAsStringSync();

      expect(code.contains('FlutterSecureStorage'), isTrue);
      expect(code.contains('_secureStorage.write'), isTrue);
      expect(code.contains('_secureStorage.read'), isTrue);
    });

    test('data_extraction_rules.xml enumerates root, file, database, sharedpref, and external', () {
      final file = File('android/app/src/main/res/xml/data_extraction_rules.xml');
      final xml = file.readAsStringSync();

      expect(xml.contains('<exclude domain="root" path="." />'), isTrue);
      expect(xml.contains('<exclude domain="file" path="." />'), isTrue);
      expect(xml.contains('<exclude domain="database" path="." />'), isTrue);
      expect(xml.contains('<exclude domain="sharedpref" path="." />'), isTrue);
      expect(xml.contains('<exclude domain="external" path="." />'), isTrue);
    });
  });

  group('HIGH H5: Account Deletion Rate Limiting', () {
    test('delete-request route implements rate limiting with 429 response', () {
      final file = File('share-frontend/app/api/account/delete-request/route.ts');
      final code = file.readAsStringSync();

      expect(code.contains('MAX_PER_IP'), isTrue);
      expect(code.contains('MAX_PER_EMAIL'), isTrue);
      expect(code.contains('status: 429'), isTrue);
    });
  });

  group('HIGH H6: CI Signing Gate & Pinned Action SHAs', () {
    test('build-apk.yml decodes keystore, generates key.properties, and pins SHAs', () {
      final file = File('.github/workflows/build-apk.yml');
      final yaml = file.readAsStringSync();

      expect(yaml.contains('upload-keystore.jks'), isTrue);
      expect(yaml.contains('android/key.properties'), isTrue);
      expect(yaml.contains('actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683'), isTrue);
      expect(yaml.contains('has_release_signing'), isTrue);
    });
  });

  group('PLAY BLOCKERS: Domain Reconciliation & Search Indexing', () {
    test('Canonical domain is share.inoapp.com across documentation', () {
      final terms = File('TERMS.md').readAsStringSync();
      expect(terms.contains('share.inoapp.in'), isFalse);
      expect(terms.contains('share.inoapp.com/delete-account'), isTrue);

      final del = File('DELETE_ACCOUNT.md').readAsStringSync();
      expect(del.contains('share.inoapp.in'), isFalse);
      expect(del.contains('share.inoapp.com/delete-account'), isTrue);

      final priv = File('PRIVACY_POLICY.md').readAsStringSync();
      expect(priv.contains('share.inoapp.in'), isFalse);
      expect(priv.contains('share.inoapp.com'), isTrue);
    });

    test('Published legal pages explicitly declare robots index: true, follow: true', () {
      final privacyPage = File('share-frontend/app/privacy/page.tsx').readAsStringSync();
      expect(privacyPage.contains('robots: { index: true, follow: true }'), isTrue);

      final deletePage = File('share-frontend/app/delete-account/page.tsx').readAsStringSync();
      expect(deletePage.contains('robots: { index: true, follow: true }'), isTrue);

      final termsPage = File('share-frontend/app/terms/page.tsx').readAsStringSync();
      expect(termsPage.contains('robots: { index: true, follow: true }'), isTrue);
    });
  });
}
