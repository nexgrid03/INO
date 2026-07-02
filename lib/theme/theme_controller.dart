import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide theme-mode state, exposed as a single [ValueNotifier], and
/// **persisted** so the choice survives an app restart.
///
/// Kept deliberately tiny (no state-management package): [InoApp] listens to it
/// to pick light/dark, and any screen can flip it via [toggle] / [setMode].
/// Defaults to [ThemeMode.system] semantics on first launch (light), then an
/// explicit choice is remembered via `shared_preferences`.
class ThemeController {
  ThemeController._();

  static const _kThemeMode = 'pref_theme_mode';

  // Light is the primary theme; users can switch to dark via the header toggle.
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  /// Reads the persisted theme choice into [mode]. Call once at startup, before
  /// the first frame, so there's no light→dark flash.
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final stored = p.getString(_kThemeMode);
      mode.value = _decode(stored);
      developer.log('loaded theme=${mode.value}', name: 'theme');
    } catch (e) {
      developer.log('load failed: $e', name: 'theme');
    }
  }

  /// Flip between light and dark. When currently following the system, resolve
  /// the *effective* brightness first so the toggle always visibly switches.
  static void toggle(BuildContext context) {
    final current = mode.value;
    final effectiveDark = current == ThemeMode.system
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : current == ThemeMode.dark;
    setMode(effectiveDark ? ThemeMode.light : ThemeMode.dark);
  }

  /// Sets and persists the theme mode.
  static void setMode(ThemeMode next) {
    mode.value = next;
    _persist(next);
  }

  static Future<void> _persist(ThemeMode next) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kThemeMode, next.name);
      developer.log('saved theme=$next', name: 'theme');
    } catch (e) {
      developer.log('persist failed: $e', name: 'theme');
    }
  }

  static ThemeMode _decode(String? name) {
    switch (name) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }
}
