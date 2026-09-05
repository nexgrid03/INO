import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/config/share_config.dart';
import 'package:inoapp/services/deep_link_service.dart';
import 'package:inoapp/utils/share_link_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HIGH H1: Legacy Share Password Hash Replay Protection', () {
    test('Migration cleanses all non-bcrypt password hashes', () {
      final migrationFile = File('supabase/migrations/20260904080000_share_security_hardening.sql');
      expect(migrationFile.existsSync(), isTrue, reason: 'Migration file must exist');

      final sql = migrationFile.readAsStringSync();
      expect(sql.contains("password_hash not like '\$2%'"), isTrue);
      expect(sql.contains("set status = 'revoked'"), isTrue);
    });

    test('Edge function strictly enforces bcrypt and disallows plain hash comparison', () {
      final edgeFunc = File('supabase/functions/share/index.ts');
      expect(edgeFunc.existsSync(), isTrue);

      final code = edgeFunc.readAsStringSync();

      // Ensure direct comparison between submitted value and stored hash is REMOVED
      expect(code.contains('timingSafeEqual(raw.toLowerCase(), expected.toLowerCase())'), isFalse);
      expect(code.contains('timingSafeEqual(hashed, expected.toLowerCase())'), isFalse);

      // Verify bcrypt prefix requirement ($2)
      expect(code.contains(r'expected.startsWith("$2') || code.contains(r"expected.startsWith('$2"), isTrue);
      expect(code.contains('bcrypt.compareSync(raw, expected)'), isTrue);
    });
  });

  group('HIGH H2: Rate Limiting & Postgres Lockout', () {
    test('Migration creates persistent share_rate_limits table with 5-attempt/15-min lockout', () {
      final migrationFile = File('supabase/migrations/20260904080000_share_security_hardening.sql');
      final sql = migrationFile.readAsStringSync();

      expect(sql.contains('create table if not exists public.share_rate_limits'), isTrue);
      expect(sql.contains('ip text not null'), isTrue);
      expect(sql.contains('token text not null'), isTrue);
      expect(sql.contains('attempts integer not null default 0'), isTrue);
      expect(sql.contains('lock_until timestamptz'), isTrue);
      expect(sql.contains("interval '15 minutes'"), isTrue);
      expect(sql.contains('share_rate_limits.attempts + 1 >= 5'), isTrue);
      expect(sql.contains('check_share_password_lock'), isTrue);
      expect(sql.contains('record_share_password_attempt'), isTrue);
    });

    test('Edge function resolves client IP via cf-connecting-ip and last hop of XFF', () {
      final edgeFunc = File('supabase/functions/share/index.ts');
      final code = edgeFunc.readAsStringSync();

      // Preferred cf-connecting-ip
      expect(code.contains('req.headers.get("cf-connecting-ip")'), isTrue);

      // Must take LAST hop from x-forwarded-for, never first
      expect(code.contains('hops[hops.length - 1]'), isTrue);
      expect(code.contains('forwarded.split(",")[0]'), isFalse);

      // Lockout functions must check database
      expect(code.contains('check_share_password_lock'), isTrue);
      expect(code.contains('record_share_password_attempt'), isTrue);
    });
  });

  group('HIGH H3: App Links & Deep Linking Canonical Host Unification', () {
    const canonicalHost = 'share.inoapp.com';

    test('ShareConfig uses canonical host for public and view-once links', () {
      expect(ShareConfig.publicBase, equals('https://$canonicalHost/s'));
      expect(ShareConfig.viewOncePublicBase, equals('https://$canonicalHost/v'));

      final shareUrl = ShareConfig.publicUrl('a8f9x2k40b1c');
      expect(shareUrl, equals('https://$canonicalHost/s/a8f9x2k40b1c'));

      final viewOnceUrl = ShareConfig.viewOncePublicUrl('a1b2c3d4e5f60718293a4b5c6d7e8f90');
      expect(viewOnceUrl, equals('https://$canonicalHost/v/a1b2c3d4e5f60718293a4b5c6d7e8f90'));
    });

    test('ShareLinkValidator recognizes canonical host as approved', () {
      expect(ShareLinkValidator.isApprovedHost(canonicalHost), isTrue);
      expect(ShareLinkValidator.isApprovedHost('https://$canonicalHost/s/abc'), isFalse); // expects host string
      expect(ShareLinkValidator.isApprovedHost('evil-$canonicalHost'), isFalse);
    });

    test('AndroidManifest.xml specifies canonical host with autoVerify on /s/, /v/, and /share/', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      final content = manifestFile.readAsStringSync();

      expect(content.contains('android:host="$canonicalHost"'), isTrue);
      expect(content.contains('android:autoVerify="true"'), isTrue);
      expect(content.contains('android:pathPrefix="/s/"'), isTrue);
      expect(content.contains('android:pathPrefix="/v/"'), isTrue);
      expect(content.contains('android:pathPrefix="/share/"'), isTrue);
    });

    test('Runner.entitlements contains canonical applinks domain', () {
      final entitlementsFile = File('ios/Runner/Runner.entitlements');
      final content = entitlementsFile.readAsStringSync();

      expect(content.contains('applinks:$canonicalHost'), isTrue);
    });

    test('Xcode project references Runner.entitlements for code signing', () {
      final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');
      final content = pbxproj.readAsStringSync();

      expect(content.contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'), isTrue);
    });

    test('Android assetlinks.json is served with correct package name and SHA256 fingerprint', () {
      final assetlinksFile = File('share-frontend/public/.well-known/assetlinks.json');
      expect(assetlinksFile.existsSync(), isTrue);

      final jsonContent = jsonDecode(assetlinksFile.readAsStringSync()) as List<dynamic>;
      expect(jsonContent.isNotEmpty, isTrue);

      final target = jsonContent[0]['target'] as Map<String, dynamic>;
      expect(target['package_name'], equals('com.ino.app'));
      expect(target['namespace'], equals('android_app'));

      final certs = target['sha256_cert_fingerprints'] as List<dynamic>;
      expect(certs, contains('EC:37:23:6C:C2:09:86:E3:A6:88:75:90:DE:97:E9:D3:F6:95:4F:D8:8E:16:5F:31:00:84:DB:94:ED:AC:0A:52'));
    });

    test('iOS apple-app-site-association is served with correct bundle ID and paths', () {
      final aasaWellKnown = File('share-frontend/public/.well-known/apple-app-site-association');
      final aasaRoot = File('share-frontend/public/apple-app-site-association');
      expect(aasaWellKnown.existsSync(), isTrue);
      expect(aasaRoot.existsSync(), isTrue);

      final aasa = jsonDecode(aasaWellKnown.readAsStringSync()) as Map<String, dynamic>;
      final applinks = aasa['applinks'] as Map<String, dynamic>;
      final details = applinks['details'] as List<dynamic>;
      expect(details.isNotEmpty, isTrue);

      final detail = details[0] as Map<String, dynamic>;
      expect(detail['appID'], contains('com.ino.app'));
      expect(detail['paths'], containsAll(['/s/*', '/v/*', '/share/*']));
    });

    test('DeepLinkService routes canonical URLs to correct tokens without cross-contamination', () {
      const shareToken = 'a8f9x2k40b1c';
      const viewOnceToken = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

      // Standard /s/ link
      final sUri = Uri.parse('https://$canonicalHost/s/$shareToken');
      expect(DeepLinkService.parseShareId(sUri), equals(shareToken));
      expect(DeepLinkService.parseViewOnceToken(sUri), isNull);

      // View Once /v/ link
      final vUri = Uri.parse('https://$canonicalHost/v/$viewOnceToken');
      expect(DeepLinkService.parseViewOnceToken(vUri), equals(viewOnceToken));
      expect(DeepLinkService.parseShareId(vUri), isNull);

      // Legacy /share/ link
      final shareUri = Uri.parse('https://$canonicalHost/share/$shareToken');
      expect(DeepLinkService.parseShareId(shareUri), equals(shareToken));
      expect(DeepLinkService.parseViewOnceToken(shareUri), isNull);
    });
  });
}
