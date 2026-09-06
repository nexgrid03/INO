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

    test('Runner.entitlements contains canonical applinks domain without placeholders', () {
      final entitlementsFile = File('ios/Runner/Runner.entitlements');
      expect(entitlementsFile.existsSync(), isTrue);
      final content = entitlementsFile.readAsStringSync();

      expect(content.contains('<string>applinks:$canonicalHost</string>'), isTrue);
      expect(content.contains('your-share-domain'), isFalse, reason: 'Runner.entitlements must not contain your-share-domain placeholder');
    });

    test('Xcode project references Runner.entitlements for code signing', () {
      final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');
      final content = pbxproj.readAsStringSync();

      expect(content.contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'), isTrue);
    });

    test('Android assetlinks.json is served with correct package name and dual production SHA256 fingerprints', () {
      final filesToCheck = [
        File('share-frontend/public/.well-known/assetlinks.json'),
        File('deep-linking/assetlinks.json'),
      ];

      const uploadKeySha256 = '2C:CE:7C:AA:04:E7:8A:E8:16:1C:9F:B0:FA:2B:F9:B0:B5:AA:C0:0F:6D:4A:2C:E6:BD:BF:5D:85:84:93:21:ED';
      const playSigningSha256 = 'EC:37:23:6C:C2:09:86:E3:A6:88:75:90:DE:97:E9:D3:F6:95:4F:D8:8E:16:5F:31:00:84:DB:94:ED:AC:0A:52';
      final sha256Regex = RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$');

      for (final assetlinksFile in filesToCheck) {
        expect(assetlinksFile.existsSync(), isTrue, reason: '${assetlinksFile.path} must exist');

        final jsonContent = jsonDecode(assetlinksFile.readAsStringSync()) as List<dynamic>;
        expect(jsonContent.isNotEmpty, isTrue);

        final entry = jsonContent[0] as Map<String, dynamic>;
        expect(entry['relation'], contains('delegate_permission/common.handle_all_urls'));

        final target = entry['target'] as Map<String, dynamic>;
        expect(target['package_name'], equals('com.ino.app'));
        expect(target['namespace'], equals('android_app'));

        final certs = target['sha256_cert_fingerprints'] as List<dynamic>;
        expect(certs, contains(uploadKeySha256), reason: 'Must contain upload key SHA-256 in ${assetlinksFile.path}');
        expect(certs, contains(playSigningSha256), reason: 'Must contain Play App Signing SHA-256 in ${assetlinksFile.path}');

        for (final cert in certs) {
          expect(sha256Regex.hasMatch(cert as String), isTrue, reason: 'Invalid SHA256 format: $cert in ${assetlinksFile.path}');
          expect(cert, isNot(contains('EXAMPLE')));
          expect(cert, isNot(contains('PLACEHOLDER')));
        }
      }
    });

    test('iOS apple-app-site-association strictly enforces valid Apple Developer Team ID and rejects placeholders', () {
      final filesToCheck = [
        File('share-frontend/public/.well-known/apple-app-site-association'),
        File('share-frontend/public/apple-app-site-association'),
      ];

      const expectedTeamId = '9JA6MVCD82';
      const expectedAppId = '$expectedTeamId.com.ino.app';
      final appIDRegex = RegExp(r'^[A-Z0-9]{10}\.com\.ino\.app$');
      final teamIdRegex = RegExp(r'^[A-Z0-9]{10}$');

      for (final aasaFile in filesToCheck) {
        expect(aasaFile.existsSync(), isTrue, reason: '${aasaFile.path} must exist');
        final raw = aasaFile.readAsStringSync();

        // Strict rejection of placeholders
        expect(raw, isNot(contains('TEAMID')), reason: 'Must not contain literal placeholder TEAMID in ${aasaFile.path}');
        expect(raw, isNot(contains('YOUR_TEAM_ID')));
        expect(raw, isNot(contains('<TEAMID>')));
        expect(raw, isNot(contains('<REAL_TEAM_ID>')));

        final aasa = jsonDecode(raw) as Map<String, dynamic>;
        final applinks = aasa['applinks'] as Map<String, dynamic>;
        final details = applinks['details'] as List<dynamic>;
        expect(details.isNotEmpty, isTrue);

        final detail = details[0] as Map<String, dynamic>;
        final appID = detail['appID'] as String;

        // Strict pattern validation
        expect(appIDRegex.hasMatch(appID), isTrue, reason: 'App ID $appID in ${aasaFile.path} must match [A-Z0-9]{10}.com.ino.app');
        expect(appID, equals(expectedAppId));

        final teamId = appID.split('.').first;
        expect(teamIdRegex.hasMatch(teamId), isTrue);
        expect(teamId.length, equals(10), reason: 'Apple Developer Team ID must be exactly 10 alphanumeric chars');
        expect(teamId, equals(expectedTeamId));

        // Exact paths matching
        expect(detail['paths'], equals(['/s/*', '/v/*', '/share/*']));

        // Webcredentials apps validation
        final webcredentials = aasa['webcredentials'] as Map<String, dynamic>;
        final webApps = webcredentials['apps'] as List<dynamic>;
        expect(webApps, contains(expectedAppId));
        expect(webApps, isNot(contains('TEAMID.com.ino.app')));
        for (final app in webApps) {
          expect(appIDRegex.hasMatch(app as String), isTrue);
          expect(app, isNot(contains('TEAMID')));
        }
      }
    });

    test('Apple App ID validator strictly rejects TEAMID, lowercase, short, or placeholder values', () {
      final appIDRegex = RegExp(r'^[A-Z0-9]{10}\.com\.ino\.app$');
      bool isValidAppId(String candidate) {
        if (candidate.contains('TEAMID') ||
            candidate.contains('YOUR_TEAM_ID') ||
            candidate.contains('PLACEHOLDER') ||
            candidate.contains('<') ||
            candidate.contains('>')) {
          return false;
        }
        return appIDRegex.hasMatch(candidate);
      }

      // Proves previous broken states FAIL:
      expect(isValidAppId('TEAMID.com.ino.app'), isFalse, reason: 'TEAMID placeholder must be rejected');
      expect(isValidAppId('com.ino.app'), isFalse, reason: 'Missing Team ID prefix must be rejected');
      expect(isValidAppId('YOUR_TEAM_ID.com.ino.app'), isFalse, reason: 'YOUR_TEAM_ID placeholder must be rejected');
      expect(isValidAppId('<TEAMID>.com.ino.app'), isFalse, reason: 'Bracketed placeholder must be rejected');
      expect(isValidAppId('teamid1234.com.ino.app'), isFalse, reason: 'Lowercase or invalid prefix must be rejected');
      expect(isValidAppId('12345.com.ino.app'), isFalse, reason: 'Prefix with length != 10 must be rejected');
      expect(isValidAppId('ABC12345678.com.ino.app'), isFalse, reason: 'Prefix with length > 10 must be rejected');

      // Proves production state PASSES:
      expect(isValidAppId('9JA6MVCD82.com.ino.app'), isTrue, reason: 'Valid 10-char uppercase alphanumeric Team ID must pass');
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
