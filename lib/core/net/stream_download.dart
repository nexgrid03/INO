import 'dart:io';

import 'package:http/http.dart' as http;

import 'net_guard.dart';

/// Streams the body of [url] straight into [dest], chunk by chunk, so a large
/// file never exists as one contiguous in-memory buffer.
///
/// Storage SDKs hand back a whole `Uint8List`, which is fine for a thumbnail
/// and ruinous for a 50 MB PDF: several open at once is what turns a stress run
/// into an OOM. Every path whose end state is a file on disk (the document
/// cache, cloud backups, family-vault opens) should come through here instead.
///
/// A failed transfer deletes the partial file rather than leaving behind
/// something a caller could mistake for a complete download.
///
/// [onError] builds the exception thrown on a non-200 response, so each caller
/// can surface its own domain error type.
Future<void> streamUrlToFile(
  String url,
  File dest, {
  required Object Function(int statusCode) onError,
}) async {
  final client = http.Client();
  IOSink? sink;
  try {
    final res = await client
        .send(http.Request('GET', Uri.parse(url)))
        .timeout(NetGuard.query);
    if (res.statusCode != 200) throw onError(res.statusCode);
    sink = dest.openWrite();
    // The stream timeout fires on a stalled connection (no chunk arriving),
    // not on total duration - a big file on a slow link still succeeds.
    await sink.addStream(res.stream.timeout(NetGuard.query));
    await sink.flush();
  } catch (e) {
    // Never leave a half-written file behind for callers to mistake for a
    // complete download.
    try {
      await sink?.close();
      sink = null;
      if (await dest.exists()) await dest.delete();
    } catch (_) {}
    rethrow;
  } finally {
    await sink?.close();
    client.close();
  }
}
