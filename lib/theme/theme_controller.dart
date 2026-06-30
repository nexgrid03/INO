import 'package:flutter/material.dart';

/// App-wide theme-mode state, exposed as a single [ValueNotifier].
///
/// Kept deliberately tiny (no state-management package): [InoApp] listens to it
/// to pick light/dark, and any screen can flip it via [toggle]. Defaults to
/// [ThemeMode.system] so first launch honours the OS setting; an explicit
/// toggle then pins light or dark for the session.
class ThemeController {
  ThemeController._();

  // Light is the primary theme; users can switch to dark via the header toggle.
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  /// Flip between light and dark. When currently following the system, resolve
  /// the *effective* brightness first so the toggle always visibly switches.
  static void toggle(BuildContext context) {
    final current = mode.value;
    final effectiveDark = current == ThemeMode.system
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : current == ThemeMode.dark;
    mode.value = effectiveDark ? ThemeMode.light : ThemeMode.dark;
  }
}
