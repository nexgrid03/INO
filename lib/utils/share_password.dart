import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// SHA-256 hex of a share password, matching `encode(digest(p_password, 'sha256'), 'hex')`.
Future<String> sharePasswordHash(String password) async {
  final hash = await Sha256().hash(utf8.encode(password));
  return hash.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
