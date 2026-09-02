import 'dart:async';

import 'package:flutter/material.dart';

import '../../main.dart' show InoApp;
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import 'ino_loader.dart';

/// The app-wide blocking wait: a dimmed scrim with the spinning INO shield in
/// the middle, for work the user must not interrupt — uploading a document,
/// encrypting a vault entry, exporting a PDF, hydrating files before a share.
///
/// Mounted into the **root [Overlay]**, not pushed as a route, which is what
/// makes it safe to use around code that navigates:
///
///  * [hide] is idempotent. A `finally { hide(); }` that runs twice, or after
///    the screen that opened it was disposed, is a no-op — where the old
///    `showDialog` + `Navigator.pop` pairing could pop the caller's own route
///    if the dialog had already gone.
///  * It sits above every route, so a push or pop underneath it doesn't take
///    the spinner with it.
///  * Nested calls reference-count: an inner `run` finishing leaves the outer
///    one's overlay up until it, too, is done.
///
/// Prefer [run], which brackets a future and always tears down, over calling
/// [show] / [hide] by hand.
///
/// ```dart
/// final url = await InoBusyOverlay.run(
///   context,
///   () => DocumentRepository.instance.upload(file),
///   message: l10n.t('uploading'),
/// );
/// ```
class InoBusyOverlay {
  InoBusyOverlay._();

  static OverlayEntry? _entry;

  /// How many [show] calls are outstanding. The overlay only comes down when
  /// this returns to zero, so a nested operation can't dismiss its parent's.
  static int _depth = 0;

  /// Drives the caption without rebuilding (or re-inserting) the entry, so a
  /// multi-stage job can narrate itself: "Uploading…" → "Encrypting…".
  static final ValueNotifier<String?> _message = ValueNotifier<String?>(null);

  /// Whether a blocking wait is currently on screen.
  static bool get isVisible => _entry != null;

  /// Shows the overlay (or bumps the nesting count if it is already up).
  ///
  /// [context] is only used to find an [Overlay]; the app-root navigator is
  /// the fallback, so this still works from a service with no widget context.
  static void show(BuildContext? context, {String? message}) {
    _depth++;
    _message.value = message;
    if (_entry != null) return;

    final overlay = (context != null ? Overlay.maybeOf(context, rootOverlay: true) : null) ??
        InoApp.navigatorKey.currentState?.overlay;
    if (overlay == null) {
      // No overlay to attach to (very early startup). Don't leave the depth
      // counter armed, or the next hide() would silently do nothing.
      _depth = 0;
      return;
    }

    final entry = OverlayEntry(builder: (_) => const _BusyScrim());
    _entry = entry;
    overlay.insert(entry);
  }

  /// Updates the caption of a wait that is already on screen.
  static void setMessage(String? message) {
    if (_entry != null) _message.value = message;
  }

  /// Takes the overlay down once every outstanding [show] has been matched.
  /// Safe to call when nothing is showing.
  static void hide() {
    if (_depth > 0) _depth--;
    if (_depth > 0 || _entry == null) return;
    _entry!.remove();
    _entry = null;
    _message.value = null;
  }

  /// Forces the overlay down regardless of nesting — for error paths that
  /// unwind past the code owning the counter (e.g. a session reset).
  static void dismissAll() {
    _depth = 0;
    hide();
  }

  /// Runs [action] with the overlay up, tearing it down on every exit path
  /// (success, error, or a `mounted` check failing mid-way).
  static Future<T> run<T>(
    BuildContext? context,
    Future<T> Function() action, {
    String? message,
  }) async {
    show(context, message: message);
    try {
      return await action();
    } finally {
      hide();
    }
  }
}

/// The scrim itself: a soft dim over the page with the brand loader centred on
/// a floating card.
class _BusyScrim extends StatelessWidget {
  const _BusyScrim();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Positioned.fill(
      // Swallows every pointer event for as long as it is up — that is the
      // whole point of a blocking wait. `absorbing` (not `IgnorePointer`) so
      // taps don't fall through to the buttons underneath.
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: palette.isDark ? 0.52 : 0.34),
          child: Center(
            child: ValueListenableBuilder<String?>(
              valueListenable: InoBusyOverlay._message,
              builder: (context, message, _) {
                return Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: message == null ? 28 : 26,
                  ),
                  decoration: BoxDecoration(
                    color: palette.bgElevated,
                    borderRadius: BorderRadius.circular(AppRadius.large),
                    border: Border.all(color: palette.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: InoLoader(size: 72, label: message),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
