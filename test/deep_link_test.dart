import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/deep_link_service.dart';

void main() {
  group('DeepLinkService.parseShareId', () {
    String? parse(String url) => DeepLinkService.parseShareId(Uri.parse(url));

    test('extracts the token from the public /s/<token> link', () {
      expect(parse('https://share.inoapp.in/s/a8f9x2k40b1c'), 'a8f9x2k40b1c');
    });

    test('handles /s/<token> with a query string', () {
      expect(parse('https://share.inoapp.in/s/a8f9x2k4?ref=qr'), 'a8f9x2k4');
    });

    test('extracts the id from the legacy Supabase functions App Link', () {
      expect(
        parse('https://ilfzppryyojoponkomrw.functions.supabase.co/share/share_9f83a1c4e0'),
        'share_9f83a1c4e0',
      );
    });

    test('handles the /functions/v1/share/... invoke path', () {
      expect(
        parse('https://ilfzppryyojoponkomrw.supabase.co/functions/v1/share/share_abc123'),
        'share_abc123',
      );
    });

    test('handles a custom domain', () {
      expect(parse('https://ino.app/share/share_xyz'), 'share_xyz');
    });

    test('handles the ino:// custom scheme', () {
      expect(parse('ino://share/share_qwerty'), 'share_qwerty');
    });

    test('ignores query strings and trailing segments', () {
      expect(
        parse('https://ino.app/share/share_abc?ref=qr'),
        'share_abc',
      );
    });

    test('returns null for a non-share link', () {
      expect(parse('https://ino.app/documents/123'), isNull);
      expect(parse('https://google.com'), isNull);
    });

    test('returns null when there is no id after /share/', () {
      expect(parse('https://ino.app/share/'), isNull);
      expect(parse('https://ino.app/share'), isNull);
    });

    test('returns null for a null uri', () {
      expect(DeepLinkService.parseShareId(null), isNull);
    });
  });
}
