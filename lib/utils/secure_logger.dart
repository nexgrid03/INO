import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Centralized secure logging system for INO.
/// Ensures logs are ONLY emitted when running in debug mode ([kDebugMode]).
/// Automatically strips or sanitizes sensitive data (emails, tokens, transcripts).
class SecureLogger {
  SecureLogger._();

  /// Logs a standard message, guarded strictly by [kDebugMode].
  static void log(String message, {String name = 'ino', Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      developer.log(message, name: name, error: error, stackTrace: stackTrace);
    }
  }

  /// Logs an informational message.
  static void info(String message, {String name = 'ino'}) {
    if (kDebugMode) {
      developer.log('INFO: $message', name: name);
    }
  }

  /// Logs an error message safely.
  static void error(String message, {String name = 'ino', Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      developer.log('ERROR: $message', name: name, error: error, stackTrace: stackTrace);
    }
  }

  /// Logs a labeled sensitive piece of data, masking value for security.
  static void sensitive(String label, String? value, {String name = 'ino'}) {
    if (kDebugMode && value != null && value.isNotEmpty) {
      developer.log('$label: ${maskSensitive(value)}', name: name);
    }
  }

  /// Masks sensitive strings (emails, JWT tokens, account IDs, speech text).
  static String maskSensitive(String input) {
    if (input.trim().isEmpty) return '[EMPTY]';

    // Email mask
    if (input.contains('@')) {
      final parts = input.split('@');
      final name = parts.first;
      final domain = parts.last;
      if (name.length <= 2) {
        return '***@$domain';
      }
      return '${name.substring(0, 2)}***@$domain';
    }

    // Token / UUID mask
    if (input.length > 8) {
      return '${input.substring(0, 4)}***${input.substring(input.length - 4)}';
    }

    return '***';
  }
}
