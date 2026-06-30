import 'package:flutter/material.dart';

/// Tiny shared controller for the app shell's active tab.
///
/// [MainShell] listens to [tab] and reflects it; pushed routes (e.g. the Wallet
/// Detail screen) can set it and pop back to root to switch tabs, so the bottom
/// navigation stays consistent everywhere without threading callbacks through.
class ShellController {
  ShellController._();

  static final ValueNotifier<int> tab = ValueNotifier<int>(0);
}
