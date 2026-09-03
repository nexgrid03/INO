import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_service.dart';

/// Raises the account-security notifications the SERVER cannot observe on its
/// own — a sign-in, an in-app password change, a two-factor toggle.
///
/// **Why the client reports these at all.** Supabase Auth owns the events, but
/// its tables live in the `auth` schema, which a project migration can only
/// attach triggers to with elevated privilege. Rather than depend on that, the
/// app reports what it directly witnesses. A database trigger covers the paths
/// the app never sees (a reset-by-email, an admin change) — the two together
/// give full coverage, and neither is load-bearing alone.
///
/// **The client never writes the wording.** Every call goes through the
/// `enqueue_security_event` RPC, which composes the title and body server-side.
/// A client that could choose the text of a "your password was changed" alert
/// would be a phishing primitive, and these are precisely the notifications a
/// user is most likely to act on.
///
/// **Nothing here can throw.** A failed alert must never break a sign-in or a
/// password change; every call is best-effort and logs under `security-alert`.
class SecurityAlertService {
  SecurityAlertService._();
  static final SecurityAlertService instance = SecurityAlertService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// A short human label for this device, used as "Signed in on {detail}".
  /// Deliberately coarse — the platform, not a fingerprint.
  String get _deviceLabel {
    if (kIsWeb) return 'the web app';
    if (Platform.isAndroid) return 'an Android device';
    if (Platform.isIOS) return 'an iPhone';
    if (Platform.isMacOS) return 'a Mac';
    if (Platform.isWindows) return 'a Windows PC';
    return 'a new device';
  }

  /// Tells the user's OTHER devices that their account was just signed in on
  /// this one.
  ///
  /// The current device is excluded by token: whoever is holding the phone that
  /// just signed in does not need to be told it happened. If it is the only
  /// registered device the RPC sends nothing at all.
  Future<void> signedIn() =>
      _raise('security.new_signin', detail: _deviceLabel);

  /// The user changed their password from inside the app.
  Future<void> passwordChanged() => _raise('security.password_changed');

  /// Two-factor was turned on or off.
  Future<void> twoFactorChanged({required bool enabled}) => _raise(
        'security.two_factor_changed',
        detail: enabled
            ? 'Two-factor authentication was turned on.'
            : 'Two-factor authentication was turned off.',
      );

  Future<void> _raise(String kind, {String? detail}) async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.rpc('enqueue_security_event', params: {
        'p_kind': kind,
        'p_detail': detail,
        // Excluding this device is what makes the alert meaningful rather than
        // noise. Null (token not ready yet) simply means "tell everything".
        'p_exclude_token': PushService.instance.token,
      });
      developer.log('queued $kind', name: 'security-alert');
    } catch (e) {
      // A missing RPC means the migration has not been applied yet. That is a
      // deployment state, not a bug worth surfacing to the user mid-sign-in.
      developer.log('could not queue $kind: $e', name: 'security-alert');
    }
  }
}
