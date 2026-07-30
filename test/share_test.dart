import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/file_picker_service.dart';
import 'package:inoapp/services/share_codec_service.dart';

void main() {
  group('FilePickerService.mergeUnique (BUG 1: multi-select)', () {
    PlatformFile file(String name, int size) =>
        PlatformFile(name: name, size: size);

    test('appends new files without dropping the existing selection', () {
      final existing = [file('a.pdf', 1), file('b.png', 2)];
      final added = [file('c.jpg', 3)];
      final merged = FilePickerService.mergeUnique(existing, added);
      expect(merged.map((f) => f.name), ['a.pdf', 'b.png', 'c.jpg']);
    });

    test('de-duplicates by name + size (no overwrite, no dupes)', () {
      final existing = [file('a.pdf', 1)];
      final added = [file('a.pdf', 1), file('a.pdf', 999)];
      final merged = FilePickerService.mergeUnique(existing, added);
      // Same name+size is skipped; same name but different size is kept.
      expect(merged.length, 2);
      expect(merged.where((f) => f.name == 'a.pdf').length, 2);
    });
  });

  group('ShareCodecService tokens', () {
    test('build → parse round-trips the token', () {
      final token = ShareCodecService.generateToken();
      final uri = ShareCodecService.buildShareUri(token);
      expect(uri, startsWith('ino://share/'));
      expect(ShareCodecService.parseToken(uri), token);
    });

    test('parse accepts a bare token and rejects unrelated codes', () {
      final token = ShareCodecService.generateToken();
      expect(ShareCodecService.parseToken(token), token);
      expect(ShareCodecService.parseToken('https://example.com'), isNull);
      expect(ShareCodecService.parseToken('hello world'), isNull);
    });

    test('tokens are unique', () {
      final a = ShareCodecService.generateToken();
      final b = ShareCodecService.generateToken();
      expect(a, isNot(b));
    });
  });

  group('ShareCodecService.generateQrPng (BUG 2/4/5: off-isolate)', () {
    const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

    test('produces a valid PNG off the main isolate', () async {
      final bytes = await ShareCodecService.generateQrPng(
        ShareCodecService.buildShareUri(ShareCodecService.generateToken()),
      );
      expect(bytes.length, greaterThan(100));
      expect(bytes.sublist(0, 8), pngSignature);
    });

    test('different data yields different QR images', () async {
      final a = await ShareCodecService.generateQrPng('ino://share/aaa');
      final b = await ShareCodecService.generateQrPng('ino://share/bbb');
      expect(a, isNot(equals(b)));
    });

    test('completes quickly (well under the 1s budget)', () async {
      final sw = Stopwatch()..start();
      await ShareCodecService.generateQrPng('ino://share/perf-check-token');
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });
}
