import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';
import '../models/payment_qr.dart';

/// The user's saved "My QR", as stored in `public.user_qr_codes`.
class UserQr {
  const UserQr({
    required this.bytes,
    this.label,
    this.payload,
    this.payeeVpa,
    this.payeeName,
    this.width,
    this.height,
    this.updatedAt,
  });

  /// Decoded PNG bytes of the cropped QR - what the Home card renders.
  final Uint8List bytes;

  final String? label;

  /// The decoded contents, e.g. `upi://pay?pa=…`. Null when the uploaded image
  /// held no readable code.
  final String? payload;

  final String? payeeVpa;
  final String? payeeName;
  final int? width;
  final int? height;
  final DateTime? updatedAt;

  /// What to show under the QR: the payee's name, else their VPA, else nothing.
  String? get subtitle {
    final n = payeeName?.trim();
    if (n != null && n.isNotEmpty) return n;
    final v = payeeVpa?.trim();
    if (v != null && v.isNotEmpty) return v;
    return null;
  }

  static UserQr? fromRow(Map<String, dynamic> row) {
    final b64 = row['image_base64'] as String?;
    if (b64 == null || b64.isEmpty) return null;
    final Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      // A corrupt row should render as "no QR", not crash Home.
      return null;
    }
    return UserQr(
      bytes: bytes,
      label: row['label'] as String?,
      payload: row['payload'] as String?,
      payeeVpa: row['payee_vpa'] as String?,
      payeeName: row['payee_name'] as String?,
      width: (row['width'] as num?)?.toInt(),
      height: (row['height'] as num?)?.toInt(),
      updatedAt: DateTime.tryParse((row['updated_at'] ?? '') as String),
    );
  }
}

/// Reads and writes the single saved QR belonging to the signed-in user.
///
/// One row per user (`auth_user_id` is the primary key), so saving is an
/// upsert: replacing the QR overwrites in place and can never leave a second
/// code behind. Every call is scoped by RLS server-side; the client never
/// filters by user id to decide what it may see.
class QrCodeRepository {
  QrCodeRepository._();
  static final QrCodeRepository instance = QrCodeRepository._();

  static const String _table = 'user_qr_codes';

  // ---- Session cache --------------------------------------------------------
  // Home builds this panel inside a sliver list that DISPOSES off-screen
  // children, so scrolling to the top and back re-creates the widget and would
  // re-fetch - showing a spinner where a QR already was. The result is memoised
  // for the session so the second build is instant.
  //
  // Keyed by user id: a cache that outlived a sign-out would show one account's
  // QR to the next. `_cachedForUid` is the guard, not an optimisation.

  UserQr? _cached;
  String? _cachedForUid;
  bool _loaded = false;

  /// True when the QR for the CURRENT user has already been fetched this
  /// session - so a rebuild can render immediately instead of showing a loader.
  bool get isLoaded => _loaded && _cachedForUid == _uid;

  /// The memoised QR, or null when nothing is cached for the current user.
  /// Null is also a legitimate cached value ("this user has no QR"), so check
  /// [isLoaded] to tell the two apart.
  UserQr? get cached => isLoaded ? _cached : null;

  void _remember(UserQr? qr) {
    _cached = qr;
    _cachedForUid = _uid;
    _loaded = true;
  }

  /// Drops the memo, e.g. on sign-out or account switch.
  void invalidate() {
    _cached = null;
    _cachedForUid = null;
    _loaded = false;
  }

  /// The client, or null when Supabase isn't up yet.
  ///
  /// `Supabase.instance` throws an **AssertionError** (an Error, not an
  /// Exception) before `initialize` has run. Home builds this panel eagerly, so
  /// reading it unguarded would take the whole feed down on early boot - and it
  /// does exactly that under widget tests, which never initialise Supabase.
  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String? get _uid {
    try {
      return _client?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// The saved QR, or null when the user has none (or is signed out).
  ///
  /// Never throws: Home renders the empty state on any failure rather than
  /// showing an error where a QR should be.
  Future<UserQr?> fetch({bool force = false}) async {
    if (!force && isLoaded) return _cached;

    final client = _client;
    final uid = _uid;
    if (client == null || uid == null) return null;
    try {
      final row = await client
          .from(_table)
          .select()
          .eq('auth_user_id', uid)
          .maybeSingle()
          .timeout(NetGuard.query);
      final qr = row == null ? null : UserQr.fromRow(row);
      // Memoise the "no QR" answer too - otherwise a user without one re-queries
      // on every scroll back into view.
      _remember(qr);
      return qr;
    } catch (e) {
      // Deliberately NOT memoised: a failed fetch should be retried next time,
      // not remembered as "this user has no QR".
      developer.log('fetch failed: $e', name: 'my-qr');
      return null;
    }
  }

  /// Saves (or replaces) the user's QR. Returns the stored record, or null if
  /// the write failed.
  Future<UserQr?> save({
    required Uint8List bytes,
    String? payload,
    int? width,
    int? height,
    String? label,
  }) async {
    final client = _client;
    final uid = _uid;
    if (client == null || uid == null) return null;

    // Parse the payee once, at write time, so every read can show it without
    // re-decoding the image.
    final payment = payload == null ? null : PaymentQrParser.parse(payload);

    final values = {
      'auth_user_id': uid,
      'image_base64': base64Encode(bytes),
      'payload': payload,
      'payee_vpa': payment?.payeeAddress,
      'payee_name': payment?.payeeName,
      'width': width,
      'height': height,
      'label': label,
    };

    try {
      final row = await client
          .from(_table)
          .upsert(values, onConflict: 'auth_user_id')
          .select()
          .single()
          .timeout(NetGuard.mutation);
      developer.log('saved (${bytes.length} bytes, payload=${payload != null})',
          name: 'my-qr');
      final qr = UserQr.fromRow(row);
      _remember(qr);
      return qr;
    } catch (e) {
      developer.log('save failed: $e', name: 'my-qr');
      return null;
    }
  }

  /// Removes the saved QR. Returns true when the row is gone afterwards.
  Future<bool> remove() async {
    final client = _client;
    final uid = _uid;
    if (client == null || uid == null) return false;
    try {
      await client
          .from(_table)
          .delete()
          .eq('auth_user_id', uid)
          .timeout(NetGuard.mutation);
      _remember(null);
      return true;
    } catch (e) {
      developer.log('delete failed: $e', name: 'my-qr');
      return false;
    }
  }
}
