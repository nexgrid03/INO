import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/config/share_config.dart';
import 'package:inoapp/models/view_once_share.dart';
import 'package:inoapp/services/deep_link_service.dart';

/// Guards the invariants of **View Once** sharing.
///
/// The feature's entire value rests on a few rules that are easy to break by
/// accident, and whose breakage is silent - a one-time link that quietly opens
/// twice still *looks* like it works. So each rule is pinned here:
///
///  1. A one-time link is routed by its `/v/` path and must NEVER be mistaken
///     for a regular `/s/` share (which would open it without the gate).
///  2. A spent link stays spent - `viewed` is terminal regardless of expiry.
///  3. Every non-`ready` status looks the same to the recipient, so probing a
///     token can't reveal whether it ever existed.
void main() {
  group('deep-link routing keeps the two kinds of link apart', () {
    test('a /v/ link parses as view-once and NOT as a regular share', () {
      final uri = Uri.parse('https://share.inoapp.in/v/a1b2c3d4e5f60718293a4b5c6d7e8f90');

      expect(DeepLinkService.parseViewOnceToken(uri),
          'a1b2c3d4e5f60718293a4b5c6d7e8f90');
      // The critical half: the regular parser must not claim it. If it did,
      // the link would open in SharedDocumentsScreen, which fetches without
      // ever warning the recipient.
      expect(DeepLinkService.parseShareId(uri), isNull);
    });

    test('a /s/ link parses as a regular share and NOT as view-once', () {
      final uri = Uri.parse('https://share.inoapp.in/s/a8f9x2k40b1c');

      expect(DeepLinkService.parseShareId(uri), 'a8f9x2k40b1c');
      expect(DeepLinkService.parseViewOnceToken(uri), isNull);
    });

    test('the Edge Function form /share/v/<token> also resolves', () {
      final uri = Uri.parse(
          'https://ref.functions.supabase.co/share/v/ff00ff00ff00ff00ff00ff00ff00ff00');

      expect(DeepLinkService.parseViewOnceToken(uri),
          'ff00ff00ff00ff00ff00ff00ff00ff00');
    });

    test('the custom scheme ino://viewonce/<token> resolves', () {
      expect(DeepLinkService.parseViewOnceToken(Uri.parse('ino://viewonce/abc123def456')),
          'abc123def456');
      // …and the pre-existing ino://share scheme keeps working untouched.
      expect(DeepLinkService.parseShareId(Uri.parse('ino://share/tok123456789')),
          'tok123456789');
    });

    test('unrelated links resolve to neither', () {
      for (final raw in const [
        'https://inoapp.in/about',
        'https://share.inoapp.in/',
        'ino://home',
      ]) {
        final uri = Uri.parse(raw);
        expect(DeepLinkService.parseViewOnceToken(uri), isNull, reason: raw);
        expect(DeepLinkService.parseShareId(uri), isNull, reason: raw);
      }
    });
  });

  group('link URLs', () {
    test('a view-once link lives under /v/ on the same host as /s/', () {
      const token = 'deadbeefdeadbeefdeadbeefdeadbeef';
      final url = ShareConfig.viewOncePublicUrl(token);

      expect(url, endsWith('/v/$token'));
      expect(url, isNot(contains('/s/')));
      // Same origin as regular shares - one domain to deploy and verify.
      expect(Uri.parse(url).host, Uri.parse(ShareConfig.publicUrl(token)).host);
    });

    test('the app talks to the Edge Function, not the public web host', () {
      const token = 'deadbeefdeadbeefdeadbeefdeadbeef';
      final api = ShareConfig.viewOnceApiUrl(token);

      expect(api, contains('functions.supabase.co'));
      expect(api, endsWith('/share/v/$token'));
    });

    test('a round trip - the QR URL parses back to the same token', () {
      const token = '0123456789abcdef0123456789abcdef';
      final parsed =
          DeepLinkService.parseViewOnceToken(Uri.parse(ShareConfig.viewOncePublicUrl(token)));

      expect(parsed, token);
    });
  });

  group('a spent link stays spent', () {
    ViewOnceShare share({
      bool viewed = false,
      bool revoked = false,
      Duration expiresIn = const Duration(hours: 24),
    }) {
      return ViewOnceShare(
        id: 'row-1',
        token: '0123456789abcdef0123456789abcdef',
        documentId: 'doc-1',
        ownerId: 'owner-1',
        expiryTime: DateTime.now().add(expiresIn),
        viewed: viewed,
        revoked: revoked,
        createdAt: DateTime.now(),
        viewedAt: viewed ? DateTime.now() : null,
      );
    }

    test('an untouched, unexpired link is the only live state', () {
      expect(share().isLive, isTrue);
      expect(share().status, ViewOnceStatus.ready);
    });

    test('viewed beats a still-valid expiry - it can never go back to ready', () {
      final s = share(viewed: true, expiresIn: const Duration(days: 7));

      expect(s.isLive, isFalse);
      expect(s.status, ViewOnceStatus.viewed);
    });

    test('viewed still reads as viewed after the expiry passes', () {
      final s = share(viewed: true, expiresIn: const Duration(seconds: -1));

      expect(s.status, ViewOnceStatus.viewed,
          reason: 'a burned link is burned, not merely expired');
    });

    test('an unopened link lapses once its expiry passes', () {
      final s = share(expiresIn: const Duration(seconds: -1));

      expect(s.isLive, isFalse);
      expect(s.status, ViewOnceStatus.expired);
    });

    test('revoking outranks everything else', () {
      expect(share(revoked: true).status, ViewOnceStatus.revoked);
      expect(share(revoked: true, viewed: true).status, ViewOnceStatus.revoked);
      expect(share(revoked: true).isLive, isFalse);
    });
  });

  group('status parsing', () {
    test('ready and claimed both mean "a view is available"', () {
      expect(viewOnceStatusFrom('ready'), ViewOnceStatus.ready);
      expect(viewOnceStatusFrom('claimed'), ViewOnceStatus.ready);
    });

    test('every terminal status is recognised', () {
      expect(viewOnceStatusFrom('viewed'), ViewOnceStatus.viewed);
      expect(viewOnceStatusFrom('expired'), ViewOnceStatus.expired);
      expect(viewOnceStatusFrom('revoked'), ViewOnceStatus.revoked);
      expect(viewOnceStatusFrom('not_found'), ViewOnceStatus.notFound);
    });

    test('anything unknown degrades to error, never to ready', () {
      for (final raw in [null, '', 'weird', 'READY', 'ok']) {
        expect(viewOnceStatusFrom(raw), ViewOnceStatus.error, reason: '$raw');
        expect(viewOnceStatusFrom(raw).isReady, isFalse, reason: '$raw');
      }
    });

    test('error is retryable, so it must not count as spent', () {
      // The viewer sends the user back to the gate on `error` (the claim may
      // never have landed) but shows a terminal page on anything spent.
      expect(ViewOnceStatus.error.isSpent, isFalse);
      expect(ViewOnceStatus.viewed.isSpent, isTrue);
      expect(ViewOnceStatus.expired.isSpent, isTrue);
      expect(ViewOnceStatus.revoked.isSpent, isTrue);
      expect(ViewOnceStatus.notFound.isSpent, isTrue);
      expect(ViewOnceStatus.ready.isSpent, isFalse);
    });
  });

  group('peek and claim payloads', () {
    test('a ready peek carries only display metadata - no storage internals', () {
      final peek = ViewOncePeek.fromJson({
        'status': 'ready',
        'name': 'Passport.pdf',
        'type': 'Identity',
        'expiresAt': '2026-08-01T10:00:00.000Z',
      });

      expect(peek.status, ViewOnceStatus.ready);
      expect(peek.name, 'Passport.pdf');
      expect(peek.type, 'Identity');
      expect(peek.expiresAt, DateTime.parse('2026-08-01T10:00:00.000Z'));
    });

    test('a peek with blank fields still renders something sane', () {
      final peek = ViewOncePeek.fromJson({'status': 'ready', 'name': '  '});

      expect(peek.name, 'Document');
      expect(peek.type, 'Document');
    });

    test('a claim carries the access key and the render kind', () {
      final claim = ViewOnceClaim.fromJson({
        'status': 'claimed',
        'accessKey': 'aaaabbbbccccdddd',
        'accessExpiresAt': '2026-07-29T10:05:00.000Z',
        'name': 'Aadhaar.jpg',
        'type': 'Identity',
        'kind': 'image',
        'mime': 'image/jpeg',
      });

      expect(claim.accessKey, 'aaaabbbbccccdddd');
      expect(claim.kind, ViewOnceKind.image);
      expect(claim.mime, 'image/jpeg');
      expect(claim.accessExpiresAt, isNotNull);
    });

    test('an unknown kind falls back to "other" rather than guessing', () {
      expect(viewOnceKindFrom('image'), ViewOnceKind.image);
      expect(viewOnceKindFrom('pdf'), ViewOnceKind.pdf);
      expect(viewOnceKindFrom('docx'), ViewOnceKind.other);
      expect(viewOnceKindFrom(null), ViewOnceKind.other);
    });

    test('a denied claim reports why, and never hands back a claim', () {
      const result = ViewOnceResult.denied(ViewOnceStatus.viewed,
          message: 'This document has already been viewed or has expired.');

      expect(result.isClaimed, isFalse);
      expect(result.claim, isNull);
      expect(result.status, ViewOnceStatus.viewed);
    });
  });

  group('row mapping', () {
    test('a database row maps onto the model, dashes and all', () {
      final s = ViewOnceShare.fromMap({
        'id': '11111111-2222-3333-4444-555555555555',
        'token': 'abcdefabcdefabcdefabcdefabcdefab',
        'document_id': 'doc-9',
        'owner_id': 'owner-9',
        'expiry_time': '2026-08-05T12:00:00.000Z',
        'viewed': true,
        'revoked': false,
        'created_at': '2026-07-29T09:00:00.000Z',
        'viewed_at': '2026-07-29T09:30:00.000Z',
      });

      expect(s.token, 'abcdefabcdefabcdefabcdefabcdefab');
      expect(s.documentId, 'doc-9');
      expect(s.viewed, isTrue);
      expect(s.viewedAt, DateTime.parse('2026-07-29T09:30:00.000Z'));
      expect(s.status, ViewOnceStatus.viewed);
    });

    test('a fresh row defaults to not-viewed, not-revoked', () {
      final s = ViewOnceShare.fromMap({
        'id': 'row',
        'token': 'ffffffffffffffffffffffffffffffff',
        'document_id': 'doc',
        'owner_id': 'owner',
        'expiry_time':
            DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });

      expect(s.viewed, isFalse);
      expect(s.revoked, isFalse);
      expect(s.viewedAt, isNull);
      expect(s.isLive, isTrue);
    });
  });
}
