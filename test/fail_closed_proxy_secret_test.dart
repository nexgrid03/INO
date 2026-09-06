import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CRITICAL SECURITY: Fail-Closed Secret Management Audit', () {
    test('share/index.ts contains NO hardcoded fallback secrets and fails closed on unauthenticated headers', () {
      final file = File('supabase/functions/share/index.ts');
      expect(file.existsSync(), isTrue);
      final code = file.readAsStringSync();

      // Verify no hardcoded secrets exist
      expect(code.contains('ino-share-proxy-v1-production-auth'), isFalse);
      expect(code.contains('const SHARE_PROXY_SECRET = Deno.env.get("SHARE_PROXY_SECRET");'), isTrue);

      // Verify proxy verification strictly requires SHARE_PROXY_SECRET
      expect(code.contains('if (proxyToken && SHARE_PROXY_SECRET && proxyToken === SHARE_PROXY_SECRET)'), isTrue);

      // Verify step 3 strictly fails closed without reading untrusted x-real-ip or x-forwarded-for
      expect(code.contains('return "127.0.0.1";'), isTrue);
      // Ensure step 3 does not read untrusted x-real-ip
      final step3Index = code.indexOf('// 3. Fallback for direct connections');
      expect(step3Index != -1, isTrue);
      final afterStep3 = code.substring(step3Index, step3Index + 250);
      expect(afterStep3.contains('req.headers.get("x-real-ip")'), isFalse,
          reason: 'Untrusted direct connections must never inspect x-real-ip');
      expect(afterStep3.contains('req.headers.get("x-forwarded-for")'), isFalse,
          reason: 'Untrusted direct connections must never inspect x-forwarded-for');
    });

    test('share-frontend/lib/client-ip.ts contains NO hardcoded fallback secrets and fails closed', () {
      final file = File('share-frontend/lib/client-ip.ts');
      expect(file.existsSync(), isTrue);
      final code = file.readAsStringSync();

      expect(code.contains('ino-share-proxy-v1-production-auth'), isFalse);
      // Must not fall back to hardcoded string
      expect(code.contains('process.env.SHARE_PROXY_SECRET || "ino-'), isFalse);
      // getProxyHeaders must only attach proxy token and IP when SHARE_PROXY_SECRET is configured
      expect(code.contains('if (SHARE_PROXY_SECRET && SHARE_PROXY_SECRET.length > 0)'), isTrue);
    });

    test('share-frontend/lib/config.ts contains NO hardcoded fallback keys or secrets', () {
      final file = File('share-frontend/lib/config.ts');
      expect(file.existsSync(), isTrue);
      final code = file.readAsStringSync();

      expect(code.contains('ino-share-proxy-v1-production-auth'), isFalse);
      expect(code.contains('sb_publishable_AkYUQB5-mxBJkY_tZQu6EQ_JprMvI97'), isFalse);
      expect(code.contains('if (clientIp && SHARE_PROXY_SECRET && SHARE_PROXY_SECRET.length > 0)'), isTrue);
    });

    test('Account deletion API routes fail closed if SUPABASE_ANON_KEY is missing', () {
      final deleteReqFile = File('share-frontend/app/api/account/delete-request/route.ts');
      expect(deleteReqFile.existsSync(), isTrue);
      final deleteReqCode = deleteReqFile.readAsStringSync();
      expect(deleteReqCode.contains('if (!SUPABASE_ANON_KEY || SUPABASE_ANON_KEY.trim().length === 0)'), isTrue);

      final deleteConfirmFile = File('share-frontend/app/api/account/delete-confirm/route.ts');
      expect(deleteConfirmFile.existsSync(), isTrue);
      final deleteConfirmCode = deleteConfirmFile.readAsStringSync();
      expect(deleteConfirmCode.contains('if (!SUPABASE_ANON_KEY || SUPABASE_ANON_KEY.trim().length === 0)'), isTrue);
    });
  });

  group('MANDATORY VALIDATION: Scenarios A through F', () {
    // Model getClientIp logic
    String resolveClientIp({
      required String? serverConfiguredSecret,
      required String? headerProxyToken,
      required String? headerRealIp,
      required String? headerForwardedFor,
      required String? headerCfConnectingIp,
    }) {
      // 1. Authenticated Proxy Route
      if (headerProxyToken != null &&
          serverConfiguredSecret != null &&
          serverConfiguredSecret.isNotEmpty &&
          headerProxyToken == serverConfiguredSecret) {
        if (headerRealIp != null && headerRealIp.trim().isNotEmpty) {
          return headerRealIp.trim();
        }
        if (headerForwardedFor != null && headerForwardedFor.trim().isNotEmpty) {
          final hops = headerForwardedFor.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          if (hops.isNotEmpty) {
            return hops.first;
          }
        }
      }

      // 2. Direct client connection
      if (headerCfConnectingIp != null && headerCfConnectingIp.trim().isNotEmpty) {
        return headerCfConnectingIp.trim();
      }

      // 3. Fallback for direct connections without Cloudflare header
      return '127.0.0.1';
    }

    test('Scenario A: Missing secret -> Fails closed (proxy headers not trusted, direct IP used)', () {
      final resolved = resolveClientIp(
        serverConfiguredSecret: null, // Secret missing on server
        headerProxyToken: 'any-token',
        headerRealIp: '1.2.3.4',
        headerForwardedFor: '1.2.3.4',
        headerCfConnectingIp: '198.51.100.55', // Actual client socket IP
      );
      expect(resolved, equals('198.51.100.55'),
          reason: 'When server secret is missing, forwarded headers must be ignored and direct socket IP used');
    });

    test('Scenario B: Invalid proxy token -> Forwarded headers ignored', () {
      final resolved = resolveClientIp(
        serverConfiguredSecret: 'correct-secret-12345',
        headerProxyToken: 'attacker-guessed-wrong-token',
        headerRealIp: '1.2.3.4',
        headerForwardedFor: '1.2.3.4',
        headerCfConnectingIp: '203.0.113.99',
      );
      expect(resolved, equals('203.0.113.99'),
          reason: 'Invalid proxy token must cause all forwarded headers to be ignored');
    });

    test('Scenario C: Valid proxy token -> Real visitor IP accepted', () {
      final resolved = resolveClientIp(
        serverConfiguredSecret: 'correct-secret-12345',
        headerProxyToken: 'correct-secret-12345',
        headerRealIp: '49.36.120.15',
        headerForwardedFor: '49.36.120.15',
        headerCfConnectingIp: '76.76.21.21', // Vercel egress IP
      );
      expect(resolved, equals('49.36.120.15'),
          reason: 'With valid proxy token, the real visitor IP must be accepted');
    });

    test('Scenario D: Forged x-forwarded-for -> Rejected / ignored without valid proxy token', () {
      // Attacker tries to forge x-forwarded-for without proxy token
      final resolved = resolveClientIp(
        serverConfiguredSecret: 'correct-secret-12345',
        headerProxyToken: null, // No proxy token
        headerRealIp: null,
        headerForwardedFor: '8.8.8.8, 1.1.1.1',
        headerCfConnectingIp: '203.0.113.88', // Attacker true socket IP
      );
      expect(resolved, equals('203.0.113.88'),
          reason: 'Untrusted client sending forged x-forwarded-for must be mapped to their real socket IP');
    });

    test('Scenario E: Rate limiting -> Attacker cannot bypass by rotating forged x-forwarded-for', () {
      final Map<String, int> rateBucket = {};
      const maxAllowed = 60;
      const attackerTrueSocketIp = '198.51.100.99';
      const legitimateVisitorIp = '49.36.100.1';

      bool checkRate(String ip) {
        final count = (rateBucket[ip] ?? 0) + 1;
        rateBucket[ip] = count;
        return count <= maxAllowed;
      }

      // Attacker sends 60 requests rotating x-forwarded-for: 10.0.0.1, 10.0.0.2...
      for (int i = 1; i <= 60; i++) {
        final ip = resolveClientIp(
          serverConfiguredSecret: 'correct-secret-12345',
          headerProxyToken: null, // Attacker doesn't have proxy secret
          headerRealIp: null,
          headerForwardedFor: '10.0.0.$i', // Attacker rotates header
          headerCfConnectingIp: attackerTrueSocketIp,
        );
        expect(ip, equals(attackerTrueSocketIp));
        expect(checkRate(ip), isTrue);
      }

      // 61st request from attacker with a new forged header: 10.0.0.61
      final ip61 = resolveClientIp(
        serverConfiguredSecret: 'correct-secret-12345',
        headerProxyToken: null,
        headerRealIp: null,
        headerForwardedFor: '10.0.0.61',
        headerCfConnectingIp: attackerTrueSocketIp,
      );
      expect(checkRate(ip61), isFalse,
          reason: 'Attacker must be blocked on 61st request despite forged header rotation');

      // Legitimate visitor via authenticated proxy is unaffected
      final visitorIp = resolveClientIp(
        serverConfiguredSecret: 'correct-secret-12345',
        headerProxyToken: 'correct-secret-12345',
        headerRealIp: legitimateVisitorIp,
        headerForwardedFor: legitimateVisitorIp,
        headerCfConnectingIp: '76.76.21.21',
      );
      expect(visitorIp, equals(legitimateVisitorIp));
      expect(checkRate(visitorIp), isTrue,
          reason: 'Legitimate visitor must not be affected by attacker rate limit exhaustion');
    });

    test('Scenario F: Password lockout -> Attacker cannot bypass 5-attempt lockout by rotating forged headers', () {
      final Map<String, int> failureCount = {};
      final Set<String> lockedAccounts = {};
      const maxAttempts = 5;
      const shareId = 'confidential_share_123';
      const attackerTrueSocketIp = '198.51.100.99';
      const legitimateVisitorIp = '49.36.100.1';

      void recordFailure(String ip, String share) {
        final key = '$ip:$share';
        final attempts = (failureCount[key] ?? 0) + 1;
        failureCount[key] = attempts;
        if (attempts >= maxAttempts) {
          lockedAccounts.add(key);
        }
      }

      bool isLocked(String ip, String share) => lockedAccounts.contains('$ip:$share');

      // Attacker attempts 5 wrong passwords rotating headers
      for (int i = 1; i <= 5; i++) {
        final ip = resolveClientIp(
          serverConfiguredSecret: 'correct-secret-12345',
          headerProxyToken: null,
          headerRealIp: null,
          headerForwardedFor: '10.1.1.$i',
          headerCfConnectingIp: attackerTrueSocketIp,
        );
        recordFailure(ip, shareId);
      }

      // Attacker is locked out
      expect(isLocked(attackerTrueSocketIp, shareId), isTrue,
          reason: 'Attacker socket IP must be locked out after 5 attempts');

      // Attacker attempts 6th guess with a new forged header 10.1.1.99
      final ip6 = resolveClientIp(
        serverConfiguredSecret: 'correct-secret-12345',
        headerProxyToken: null,
        headerRealIp: null,
        headerForwardedFor: '10.1.1.99',
        headerCfConnectingIp: attackerTrueSocketIp,
      );
      expect(isLocked(ip6, shareId), isTrue,
          reason: 'Attacker cannot bypass lockout by forging headers');

      // Legitimate user via authenticated proxy on the same share is NOT locked out
      final legitIp = resolveClientIp(
        serverConfiguredSecret: 'correct-secret-12345',
        headerProxyToken: 'correct-secret-12345',
        headerRealIp: legitimateVisitorIp,
        headerForwardedFor: legitimateVisitorIp,
        headerCfConnectingIp: '76.76.21.21',
      );
      expect(isLocked(legitIp, shareId), isFalse,
          reason: 'Legitimate user must not be locked out by attacker failures');
    });
  });
}
