import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Secure clipboard service with automatic self-destruction.
///
/// Features:
/// 1. Auto-clears clipboard after [timeout] (default 30 seconds).
/// 2. Clears clipboard immediately when the app enters background, pauses, or becomes inactive.
/// 3. Clears clipboard immediately on sign-out.
/// 4. Displays user notification about auto-clear policy.
class SecureClipboard with WidgetsBindingObserver {
  SecureClipboard._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final SecureClipboard instance = SecureClipboard._();

  Timer? _clearTimer;
  String? _lastCopiedText;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      clearImmediately();
    }
  }

  /// Copies [text] to the system clipboard and schedules automatic clearing after [timeout].
  static Future<void> copy(
    BuildContext context,
    String text, {
    Duration timeout = const Duration(seconds: 30),
    String? label,
    bool showToast = true,
  }) async {
    await instance._copyInternal(
      context,
      text,
      timeout: timeout,
      label: label,
      showToast: showToast,
    );
  }

  Future<void> _copyInternal(
    BuildContext context,
    String text, {
    required Duration timeout,
    String? label,
    required bool showToast,
  }) async {
    _clearTimer?.cancel();
    _lastCopiedText = text;

    await Clipboard.setData(ClipboardData(text: text));
    developer.log(
      'copied sensitive data to clipboard (${text.length} chars)',
      name: 'clipboard',
    );

    if (showToast && context.mounted) {
      final message = label != null
          ? '$label copied to clipboard. Auto-clears in ${timeout.inSeconds}s.'
          : 'Clipboard will be cleared automatically (${timeout.inSeconds}s)';

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primaryGreen,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    _clearTimer = Timer(timeout, () {
      clearImmediately();
    });
  }

  /// Clears the system clipboard immediately and cancels any active timer.
  Future<void> clearImmediately() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    if (_lastCopiedText != null) {
      try {
        await Clipboard.setData(const ClipboardData(text: ''));
        developer.log('secure clipboard cleared', name: 'clipboard');
      } catch (e) {
        developer.log('failed to clear clipboard: $e', name: 'clipboard');
      }
      _lastCopiedText = null;
    }
  }
}
