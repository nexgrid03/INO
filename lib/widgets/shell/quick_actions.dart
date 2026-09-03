import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../screens/expenses/expense_dashboard_screen.dart';
import '../../screens/expenses/tax_records_screen.dart';
import '../../screens/notes/notes_screen.dart';
import '../../screens/property/area_converter_screen.dart';
import '../../screens/property_finance/emi_calculator_screen.dart';
import '../../screens/property_finance/gold_calculator_screen.dart';
import '../../screens/property_finance/property_valuation_screen.dart';
import '../../screens/property_finance/sip_calculator_screen.dart';
import '../../screens/scan/scan_flow_screen.dart';
import '../../screens/shell/shell_controller.dart';
import '../../services/app_settings.dart';

/// Every feature the bottom nav's "+" menu can surface. The user picks up to
/// five of these (see `showQuickMenuEditor`); the picked ids persist in
/// [AppSettings.quickMenu] by [QuickMenuAction.name].
enum QuickMenuAction {
  expenses,
  scan,
  notes,
  reminders,
  emi,
  sip,
  areaConverter,
  valuation,
  gold,
  taxRecords,
}

extension QuickMenuActionX on QuickMenuAction {
  /// Crisp, product-grade glyphs - the same visual language as Wallets /
  /// Reminders (payments, scan, notes) rather than generic pencil/alarm clip-art.
  IconData get icon => switch (this) {
        QuickMenuAction.expenses => Icons.payments_rounded,
        QuickMenuAction.scan => Icons.document_scanner_rounded,
        QuickMenuAction.notes => Icons.sticky_note_2_rounded,
        QuickMenuAction.reminders => Icons.notifications_active_rounded,
        QuickMenuAction.emi => Icons.calculate_rounded,
        QuickMenuAction.sip => Icons.show_chart_rounded,
        QuickMenuAction.areaConverter => Icons.square_foot_rounded,
        QuickMenuAction.valuation => Icons.real_estate_agent_rounded,
        QuickMenuAction.gold => Icons.monetization_on_rounded,
        QuickMenuAction.taxRecords => Icons.receipt_long_rounded,
      };

  /// Short label for menu items and wheel slots, in the active language.
  String label(AppLocalizations l10n) => switch (this) {
        QuickMenuAction.expenses => l10n.t('expenses'),
        QuickMenuAction.scan => l10n.t('scan'),
        QuickMenuAction.notes => l10n.t('notes'),
        QuickMenuAction.reminders => l10n.t('reminders'),
        QuickMenuAction.emi => l10n.t('emi'),
        QuickMenuAction.sip => l10n.t('sip'),
        QuickMenuAction.areaConverter => l10n.t('area'),
        QuickMenuAction.valuation => l10n.t('valuation'),
        QuickMenuAction.gold => l10n.t('goldShort'),
        QuickMenuAction.taxRecords => l10n.t('tax'),
      };

  /// Longer name for the editor sheet, in the active language.
  String title(AppLocalizations l10n) => switch (this) {
        QuickMenuAction.expenses => l10n.t('addExpense'),
        QuickMenuAction.scan => l10n.t('scanDocument'),
        QuickMenuAction.notes => l10n.t('notes'),
        QuickMenuAction.reminders => l10n.t('reminders'),
        QuickMenuAction.emi => l10n.t('emiCalculator'),
        QuickMenuAction.sip => l10n.t('sipCalculator'),
        QuickMenuAction.areaConverter => l10n.t('areaConverter'),
        QuickMenuAction.valuation => l10n.t('propertyValuation'),
        QuickMenuAction.gold => l10n.t('goldCalculator'),
        QuickMenuAction.taxRecords => l10n.t('taxRecords'),
      };
}

/// The user's current quick-menu picks, resolved from the persisted ids.
/// Unknown ids (from an older build) are dropped; an empty result falls back
/// to the default trio so the "+" menu is never blank.
List<QuickMenuAction> selectedQuickMenuActions() {
  final byName = {for (final a in QuickMenuAction.values) a.name: a};
  final picked = [
    for (final id in AppSettings.instance.quickMenu.value)
      if (byName[id] != null) byName[id]!,
  ];
  return picked.isEmpty
      ? const [QuickMenuAction.expenses, QuickMenuAction.scan, QuickMenuAction.notes]
      : picked;
}

/// Opens [action]'s destination. Shared by the shell and pushed routes so a
/// quick action behaves identically everywhere.
///
/// [initialWallet] threads a wallet name into the scan flow when the menu is
/// used from inside a wallet (scans stay scoped to that wallet).
void openQuickMenuAction(
  BuildContext context,
  QuickMenuAction action, {
  String? initialWallet,
}) {
  void push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => screen));

  switch (action) {
    case QuickMenuAction.expenses:
      // The Transaction Vault sits underneath the form on purpose - see
      // [ExpenseDashboardScreen.openAddOnStart]. Saving then returns the user
      // to the list holding their new expense, instead of dropping them back
      // on Home with no sign it was recorded.
      push(const ExpenseDashboardScreen(openAddOnStart: true));
    case QuickMenuAction.scan:
      launchScanFlow(context, initialWallet: initialWallet);
    case QuickMenuAction.notes:
      push(const NotesScreen());
    case QuickMenuAction.reminders:
      // Reminders is a shell tab - switch to it and unwind any pushed routes
      // so the tab is actually visible.
      ShellController.tab.value = 3;
      Navigator.of(context).popUntil((r) => r.isFirst);
    case QuickMenuAction.emi:
      push(const EmiCalculatorScreen());
    case QuickMenuAction.sip:
      push(const SipCalculatorScreen());
    case QuickMenuAction.areaConverter:
      push(const AreaConverterScreen());
    case QuickMenuAction.valuation:
      push(const PropertyValuationScreen());
    case QuickMenuAction.gold:
      push(const GoldCalculatorScreen());
    case QuickMenuAction.taxRecords:
      push(const TaxRecordsScreen());
  }
}
