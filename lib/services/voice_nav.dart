import 'package:flutter/material.dart';

import '../data/wallet_repository.dart';
import '../main.dart' show InoApp;
import '../screens/scan/scan_flow_screen.dart';
import '../screens/shell/shell_controller.dart';
import '../screens/wallet/wallet_detail_screen.dart';

/// Global navigation entry points for the voice assistant.
///
/// Every voice destination in [kVoiceCommands] routes through these helpers, so
/// navigation stays in ONE place and works from anywhere — the assistant uses
/// the app-root navigator ([InoApp.navigatorKey]) and the tab controller
/// ([ShellController]) rather than a screen-local `context`. This is what lets a
/// spoken command open any screen regardless of where the user is.
class VoiceNav {
  const VoiceNav._();

  static NavigatorState? get _nav => InoApp.navigatorKey.currentState;

  /// Switches the bottom-nav shell to [index] (0 Home · 1 Wallet · 3 Reminders ·
  /// 4 Profile), first popping any pushed routes so the tab is actually visible.
  static void goToTab(int index) {
    _nav?.popUntil((r) => r.isFirst);
    ShellController.tab.value = index;
  }

  /// Pushes a screen built by [builder] onto the root navigator.
  static void push(WidgetBuilder builder) {
    _nav?.push(MaterialPageRoute(builder: builder));
  }

  /// Opens a specific wallet's detail page by its canonical name (e.g.
  /// "Identity Wallet"). No-op if the name is unknown.
  static void openWallet(String walletName) {
    final category = SupabaseWalletRepository.categoryFor(walletName);
    if (category == null) return;
    _nav?.push(
      MaterialPageRoute(builder: (_) => WalletDetailScreen(category: category)),
    );
  }

  /// Launches the dedicated Scan & OCR flow.
  static void scan() {
    final context = InoApp.navigatorKey.currentContext;
    if (context != null) launchScanFlow(context);
  }
}
