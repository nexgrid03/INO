import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import '../config/share_config.dart';
import '../config/supabase_config.dart';

/// Error kinds returned when validating share links or tokens.
enum ShareValidationError {
  none,
  invalidToken,
  invalidHost,
  expiredShare,
  unsupportedLink,
}

/// Result of share link validation.
class ShareValidationResult {
  const ShareValidationResult.success({
    required this.token,
    required this.uri,
    this.isViewOnce = false,
  })  : isValid = true,
        error = ShareValidationError.none,
        errorMessage = null;

  const ShareValidationResult.failure(this.error, this.errorMessage)
      : isValid = false,
        token = null,
        uri = null,
        isViewOnce = false;

  final bool isValid;
  final String? token;
  final Uri? uri;
  final ShareValidationError error;
  final String? errorMessage;
  final bool isViewOnce;
}

/// Centralized validator for deep links, QR codes, share URLs, and share tokens.
class ShareLinkValidator {
  ShareLinkValidator._();

  /// Regex pattern for validating token format.
  /// Accepts 16 to 128 characters of alphanumeric, hyphens, underscores, or legacy `share_` prefix.
  static final RegExp _tokenRegex = RegExp(r'^(?:share_)?[A-Za-z0-9_-]{3,128}$');

  /// Set of approved domain hosts for INO share URLs.
  static const Set<String> _staticApprovedHosts = {
    'ino.app',
    'share.ino.app',
    'staging.ino.app',
    'app.ino.bank',
    'ino-share-web.vercel.app',
    'ino', // Custom scheme host e.g. ino://share/...
  };

  /// Set of loopback hosts allowed only during debug/testing.
  static const Set<String> _debugHosts = {
    'localhost',
    '127.0.0.1',
  };

  /// Returns true if [host] is an approved domain for share links.
  static bool isApprovedHost(String? host) {
    if (host == null || host.trim().isEmpty) return false;
    final cleanHost = host.trim().toLowerCase();

    // Check static approved hosts
    if (_staticApprovedHosts.contains(cleanHost)) return true;

    // In debug mode, allow loopback
    if (kDebugMode && _debugHosts.contains(cleanHost)) return true;

    // Dynamically check configured public base host
    try {
      final publicHost = Uri.parse(ShareConfig.publicBase).host.toLowerCase();
      if (publicHost.isNotEmpty && cleanHost == publicHost) return true;
    } catch (_) {}

    // Dynamically check Supabase function host
    try {
      final apiHost = Uri.parse(ShareConfig.apiBase).host.toLowerCase();
      if (apiHost.isNotEmpty && cleanHost == apiHost) return true;
    } catch (_) {}

    // Dynamically check Supabase URL host & Edge Functions domain
    if (cleanHost == 'functions.supabase.co' || cleanHost.endsWith('.functions.supabase.co')) {
      return true;
    }

    try {
      final supaHost = Uri.parse(SupabaseConfig.url).host.toLowerCase();
      if (supaHost.isNotEmpty && cleanHost == supaHost) return true;
    } catch (_) {}

    return false;
  }

  /// Returns true if [token] matches the required secure token format.
  static bool isValidToken(String? token) {
    if (token == null || token.isEmpty) return false;
    return _tokenRegex.hasMatch(token);
  }

  /// Parses and validates a raw URL string [rawUrl].
  static ShareValidationResult validateUrl(String rawUrl) {
    final value = rawUrl.trim();
    if (value.isEmpty) {
      return const ShareValidationResult.failure(
        ShareValidationError.unsupportedLink,
        'Empty link provided',
      );
    }

    final Uri? uri = Uri.tryParse(value);
    if (uri == null) {
      return const ShareValidationResult.failure(
        ShareValidationError.unsupportedLink,
        'Invalid URL format',
      );
    }

    return validateUri(uri);
  }

  /// Validates a parsed [Uri] against host allow-lists and token rules.
  static ShareValidationResult validateUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();

    // Check supported scheme
    if (scheme != 'http' && scheme != 'https' && scheme != 'ino') {
      return ShareValidationResult.failure(
        ShareValidationError.unsupportedLink,
        'Unsupported link scheme: $scheme',
      );
    }

    // Custom scheme `ino://` handling
    if (scheme == 'ino') {
      final host = uri.host.toLowerCase(); // `share` or `viewonce`
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty) {
        return const ShareValidationResult.failure(
          ShareValidationError.invalidToken,
          'Missing share token in custom scheme link',
        );
      }
      final token = segs.first;
      final isViewOnce = host == 'viewonce';

      if (!isValidToken(token)) {
        return const ShareValidationResult.failure(
          ShareValidationError.invalidToken,
          'Invalid share token format',
        );
      }

      return ShareValidationResult.success(
        token: token,
        uri: uri,
        isViewOnce: isViewOnce,
      );
    }

    // HTTP / HTTPS host validation
    if (!isApprovedHost(uri.host)) {
      developer.log('Rejected untrusted host: ${uri.host}', name: 'security');
      return const ShareValidationResult.failure(
        ShareValidationError.invalidHost,
        'Untrusted or unauthorized share host',
      );
    }

    // Extract path segments
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) {
      return const ShareValidationResult.failure(
        ShareValidationError.invalidToken,
        'No path segments found in share URL',
      );
    }

    // Check for view-once links (/v/<token> or /share/v/<token>)
    String? token;
    bool isViewOnce = false;

    for (var i = segs.length - 2; i >= 0; i--) {
      if (segs[i] == 'v' && segs[i + 1].isNotEmpty) {
        token = segs[i + 1];
        isViewOnce = true;
        break;
      }
    }

    // Regular share links (/s/<token> or /share/<token>)
    if (token == null) {
      final sIdx = segs.indexOf('s');
      if (sIdx >= 0 && sIdx + 1 < segs.length) {
        token = segs[sIdx + 1];
      } else {
        for (final seg in segs) {
          if (seg.startsWith('share_')) {
            token = seg;
            break;
          }
        }
      }
    }

    if (token == null || !isValidToken(token)) {
      return const ShareValidationResult.failure(
        ShareValidationError.invalidToken,
        'Invalid or missing share token format',
      );
    }

    return ShareValidationResult.success(
      token: token,
      uri: uri,
      isViewOnce: isViewOnce,
    );
  }
}
