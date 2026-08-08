import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'theme_style.dart';

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
  static const _kThemeStyle = 'pref_theme_style';

  // Light is the primary theme; users can switch to dark via the header toggle.
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  /// The visual style (classic / bold / soft / aqua …) picked in Profile →
  /// App theme. Defaults to Aqua so first-run splash/onboarding match brand.
  static final ValueNotifier<ThemeStyle> style =
      ValueNotifier<ThemeStyle>(ThemeStyle.aqua);

  /// Reads the persisted theme choices into [mode] and [style]. Call once at
  /// startup, before the first frame, so there's no flash of the wrong theme.
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final stored = p.getString(_kThemeMode);
      mode.value = _decode(stored);
      final nextStyle = _decodeStyle(p.getString(_kThemeStyle));
      // Apply brand getters before notifying listeners so Aqua icons match
      // ThemeData on the first frame.
      AppColors.applyStyle(nextStyle);
      style.value = nextStyle;
      developer.log(
        'loaded theme=${mode.value} style=${style.value}',
        name: 'theme',
      );
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

  /// Sets and persists the visual style.
  static void setStyle(ThemeStyle next) {
    AppColors.applyStyle(next);
    style.value = next;
    _persistStyle(next);
  }

  static Future<void> _persistStyle(ThemeStyle next) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kThemeStyle, next.name);
      developer.log('saved style=$next', name: 'theme');
    } catch (e) {
      developer.log('persist style failed: $e', name: 'theme');
    }
  }

  static ThemeStyle _decodeStyle(String? name) {
    switch (name) {
      case 'bold':
        return ThemeStyle.bold;
      case 'soft':
        return ThemeStyle.soft;
      case 'launcher':
        return ThemeStyle.launcher;
      case 'classic':
        return ThemeStyle.classic;
      case 'aqua':
        return ThemeStyle.aqua;
      case 'aquaLight':
        return ThemeStyle.aquaLight;
      case 'aquaMist':
        return ThemeStyle.aquaMist;
      case 'clay':
        return ThemeStyle.clay;
      default:
        // First launch (no pref yet) → Aqua.
        return ThemeStyle.aqua;
    }
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
