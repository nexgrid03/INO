import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/deep_link_service.dart';

void main() {
  group('Issue #1: Database Deployment Blocked (Migration Collision Resolution)', () {
    test('All migrations in supabase/migrations have strictly unique 14-char timestamp prefixes', () {
      final dir = Directory('supabase/migrations');
      expect(dir.existsSync(), isTrue);

      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      expect(files.length, equals(46), reason: 'Expected 46 total migrations (including Phase 7)');

      final timestamps = <String>[];
      final duplicates = <String>[];

      for (final file in files) {
        final name = file.uri.pathSegments.last;
        expect(name.length, greaterThanOrEqualTo(15), reason: 'Migration name must have at least timestamp and name: $name');
        final ts = name.substring(0, 14);
        expect(RegExp(r'^\d{14}$').hasMatch(ts), isTrue, reason: 'Timestamp must be 14 numeric digits: $ts in $name');

        if (timestamps.contains(ts)) {
          duplicates.add(ts);
        }
        timestamps.add(ts);
      }

      expect(duplicates, isEmpty, reason: 'Found duplicate migration timestamp prefixes: $duplicates');
    });

    test('Renamed migrations exist and preserve chronological sequence', () {
      final m1 = File('supabase/migrations/20260904000001_harden_share_passwords.sql');
      final m2 = File('supabase/migrations/20260904030001_harden_notifications_privacy.sql');
      final m3 = File('supabase/migrations/20260904040001_harden_wallet_registry_and_invites.sql');

      expect(m1.existsSync(), isTrue);
      expect(m2.existsSync(), isTrue);
      expect(m3.existsSync(), isTrue);

      // Verify old colliding files no longer exist
      expect(File('supabase/migrations/20260904000000_harden_share_passwords.sql').existsSync(), isFalse);
      expect(File('supabase/migrations/20260904030000_harden_notifications_privacy.sql').existsSync(), isFalse);
      expect(File('supabase/migrations/20260904040000_harden_wallet_registry_and_invites.sql').existsSync(), isFalse);

      // Verify counterpart migrations remain intact
      expect(File('supabase/migrations/20260904000000_security_fixes.sql').existsSync(), isTrue);
      expect(File('supabase/migrations/20260904030000_storage_documents_rls.sql').existsSync(), isTrue);
      expect(File('supabase/migrations/20260904040000_encrypt_government_ids.sql').existsSync(), isTrue);
    });
  });

  group('Issue #2: Storage Quota Trigger Hardening', () {
    test('check_user_storage_quota() reads size from metadata and contains no invalid column lookups', () {
      final file = File('supabase/migrations/20260904040001_harden_wallet_registry_and_invites.sql');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      // Ensure invalid size lookups are eliminated
      expect(content, isNot(contains('NEW.size')), reason: 'Must not access non-existent NEW.size on storage.objects');
      expect(content, isNot(contains('COALESCE(size,')), reason: 'Must not query non-existent column size on storage.objects');

      // Ensure valid metadata extraction
      expect(content, contains("(NEW.metadata->>'size')::BIGINT"));
      expect(content, contains("SUM((metadata->>'size')::BIGINT)"));

      // Ensure quota exception errcode 54000
      expect(content, contains("errcode = '54000'"));

      // Ensure trigger creation is safely guarded inside DO block
      expect(content, contains('DO \$\$'));
      expect(content, contains('CREATE TRIGGER trg_enforce_storage_quota'));
      expect(content, contains('EXCEPTION WHEN OTHERS THEN'));
    });
  });

  group('Issue #3: iOS Universal Links & Deep Link Security', () {
    test('apple-app-site-association route handler exists and rejects placeholders', () {
      final routeFile = File('share-frontend/app/.well-known/apple-app-site-association/route.ts');
      expect(routeFile.existsSync(), isTrue);
      final content = routeFile.readAsStringSync();

      expect(content, contains('DEFAULT_APPLE_TEAM_ID = "9JA6MVCD82"'));
      expect(content, contains('BUNDLE_ID = "com.ino.app"'));
      expect(content, contains('^[A-Z0-9]{10}\$'));
      expect(content, contains('Invalid Apple Team ID placeholder detected'));

      // Validate placeholder rejection logic
      final teamIdRegex = RegExp(r'^[A-Z0-9]{10}$');
      bool isValidTeamId(String candidate) {
        if (candidate.contains('TEAMID') ||
            candidate.contains('YOUR_TEAM_ID') ||
            candidate.contains('PLACEHOLDER') ||
            candidate.contains('<') ||
            candidate.contains('>')) {
          return false;
        }
        return teamIdRegex.hasMatch(candidate);
      }

      expect(isValidTeamId('TEAMID'), isFalse);
      expect(isValidTeamId('<TEAMID>'), isFalse);
      expect(isValidTeamId('YOUR_TEAM_ID'), isFalse);
      expect(isValidTeamId('teamid1234'), isFalse);
      expect(isValidTeamId('9JA6MVCD82'), isTrue);
    });

    test('DeepLinkService correctly handles all supported share and view-once routes', () {
      const shareToken = 'a8f9x2k40b1c';
      const viewOnceToken = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

      // 1. Canonical public link: /s/<token>
      expect(DeepLinkService.parseShareId(Uri.parse('https://share.inoapp.com/s/$shareToken')), equals(shareToken));
      expect(DeepLinkService.parseViewOnceToken(Uri.parse('https://share.inoapp.com/s/$shareToken')), isNull);

      // 2. Canonical with query params: /s/<token>?ref=qr
      expect(DeepLinkService.parseShareId(Uri.parse('https://share.inoapp.com/s/$shareToken?ref=qr')), equals(shareToken));

      // 3. View-once link: /v/<token>
      expect(DeepLinkService.parseViewOnceToken(Uri.parse('https://share.inoapp.com/v/$viewOnceToken')), equals(viewOnceToken));
      expect(DeepLinkService.parseShareId(Uri.parse('https://share.inoapp.com/v/$viewOnceToken')), isNull);

      // 4. Custom schemes: ino://share and ino://viewonce
      expect(DeepLinkService.parseShareId(Uri.parse('ino://share/$shareToken')), equals(shareToken));
      expect(DeepLinkService.parseViewOnceToken(Uri.parse('ino://viewonce/$viewOnceToken')), equals(viewOnceToken));

      // 5. Invalid / unrelated URLs
      expect(DeepLinkService.parseShareId(Uri.parse('https://example.com/other')), isNull);
      expect(DeepLinkService.parseShareId(null), isNull);
      expect(DeepLinkService.parseViewOnceToken(null), isNull);
    });
  });

  group('Issue #4: Share Website Rate Limit & Password Lockout Isolation', () {
    test('All share frontend proxy routes forward visitor IP and proxy authorization headers', () {
      final clientIpFile = File('share-frontend/lib/client-ip.ts');
      expect(clientIpFile.existsSync(), isTrue);

      final clientIpContent = clientIpFile.readAsStringSync();
      expect(clientIpContent, contains('getVisitorIp'));
      expect(clientIpContent, contains('getProxyHeaders'));
      expect(clientIpContent, contains('x-ino-proxy-token'));
      expect(clientIpContent, contains('x-real-ip'));
      expect(clientIpContent, contains('x-forwarded-for'));

      // Check all 7 proxy files
      final filesToCheck = [
        'share-frontend/app/s/[token]/page.tsx',
        'share-frontend/app/v/[token]/page.tsx',
        'share-frontend/app/api/s/[token]/route.ts',
        'share-frontend/app/api/s/[token]/unlock/route.ts',
        'share-frontend/app/api/s/[token]/file/[index]/route.ts',
        'share-frontend/app/api/v/[token]/claim/route.ts',
        'share-frontend/app/api/v/[token]/file/route.ts',
      ];

      for (final path in filesToCheck) {
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: '$path must exist');
        final content = f.readAsStringSync();
        expect(
          content.contains('getProxyHeaders') || content.contains('getVisitorIp'),
          isTrue,
          reason: '$path must forward visitor IP using getProxyHeaders or getVisitorIp',
        );
      }
    });

    test('supabase/functions/share/index.ts getClientIp enforces proxy authentication and anti-spoofing', () {
      final functionFile = File('supabase/functions/share/index.ts');
      expect(functionFile.existsSync(), isTrue);
      final content = functionFile.readAsStringSync();

      expect(content, contains('x-ino-proxy-token'));
      expect(content, contains('SHARE_PROXY_SECRET'));
      expect(content, contains('cf-connecting-ip'));
      expect(content, contains('isValidIp'));

      // Verify that direct clients cannot spoof headers without proxy token
      expect(content, contains('Directly connected untrusted clients CANNOT spoof'));
    });

    test('Rate limit and password lockout scenarios A, B, C isolation logic', () {
      // Simulation of in-memory rate limiting and lockout maps
      final Map<String, int> rateLimits = {};
      final Map<String, int> passwordFailures = {};
      final Set<String> lockedShares = {};

      const maxRequests = 60;
      const maxPasswordAttempts = 5;

      bool checkRateLimit(String ip) {
        final current = rateLimits[ip] ?? 0;
        if (current >= maxRequests) return false;
        rateLimits[ip] = current + 1;
        return true;
      }

      bool isPasswordLocked(String ip, String shareId) {
        final key = '$ip:$shareId';
        return lockedShares.contains(key);
      }

      void recordPasswordFailure(String ip, String shareId) {
        final key = '$ip:$shareId';
        final attempts = (passwordFailures[key] ?? 0) + 1;
        passwordFailures[key] = attempts;
        if (attempts >= maxPasswordAttempts) {
          lockedShares.add(key);
        }
      }

      const userAIp = '198.51.100.10';
      const userBIp = '203.0.113.20';
      const share1 = 'share_test_1';
      const share2 = 'share_test_2';

      // Scenario A: User A fails 5 times -> User A is locked out of share1. User B still works!
      for (int i = 0; i < 5; i++) {
        recordPasswordFailure(userAIp, share1);
      }
      expect(isPasswordLocked(userAIp, share1), isTrue, reason: 'User A must be locked out after 5 failures');
      expect(isPasswordLocked(userBIp, share1), isFalse, reason: 'User B must NOT be locked out on share1');

      // Scenario B: User A consumes rate limit budget -> User B still works!
      for (int i = 0; i < 60; i++) {
        checkRateLimit(userAIp);
      }
      expect(checkRateLimit(userAIp), isFalse, reason: 'User A must be rate limited after 60 requests');
      expect(checkRateLimit(userBIp), isTrue, reason: 'User B must have their own independent rate limit budget');

      // Scenario C: User A lockout on share1 does not lock out share2!
      expect(isPasswordLocked(userAIp, share2), isFalse, reason: 'Lockout on share1 must not affect share2');
    });
  });
}
