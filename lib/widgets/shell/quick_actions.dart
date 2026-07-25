import 'package:flutter/material.dart';

import '../../screens/expenses/add_expense_screen.dart';
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
  IconData get icon => switch (this) {
        QuickMenuAction.expenses => Icons.account_balance_wallet_rounded,
        QuickMenuAction.scan => Icons.document_scanner_rounded,
        QuickMenuAction.notes => Icons.edit_rounded,
        QuickMenuAction.reminders => Icons.alarm_rounded,
        QuickMenuAction.emi => Icons.account_balance_rounded,
        QuickMenuAction.sip => Icons.trending_up_rounded,
        QuickMenuAction.areaConverter => Icons.straighten_rounded,
        QuickMenuAction.valuation => Icons.home_work_rounded,
        QuickMenuAction.gold => Icons.diamond_rounded,
        QuickMenuAction.taxRecords => Icons.receipt_long_rounded,
      };

  /// Short label for menu items and wheel slots.
  String get label => switch (this) {
        QuickMenuAction.expenses => 'Expenses',
        QuickMenuAction.scan => 'Scan',
        QuickMenuAction.notes => 'Notes',
        QuickMenuAction.reminders => 'Reminders',
        QuickMenuAction.emi => 'EMI',
        QuickMenuAction.sip => 'SIP',
        QuickMenuAction.areaConverter => 'Area',
        QuickMenuAction.valuation => 'Valuation',
        QuickMenuAction.gold => 'Gold',
        QuickMenuAction.taxRecords => 'Tax',
      };

  /// Longer name for the editor sheet.
  String get title => switch (this) {
        QuickMenuAction.expenses => 'Add Expense',
        QuickMenuAction.scan => 'Scan Document',
        QuickMenuAction.notes => 'Notes',
        QuickMenuAction.reminders => 'Reminders',
        QuickMenuAction.emi => 'EMI Calculator',
        QuickMenuAction.sip => 'SIP Calculator',
        QuickMenuAction.areaConverter => 'Area Converter',
        QuickMenuAction.valuation => 'Property Valuation',
        QuickMenuAction.gold => 'Gold Calculator',
        QuickMenuAction.taxRecords => 'Tax Records',
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
      push(const AddExpenseScreen());
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
