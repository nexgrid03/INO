import 'package:flutter/material.dart';

import '../screens/assets/assets_screen.dart';
import '../screens/documents/add_document_screen.dart';
import '../screens/expenses/expense_dashboard_screen.dart';
import '../screens/expenses/tax_records_screen.dart';
import '../screens/networth/net_worth_analytics_screen.dart';
import '../screens/notes/notes_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/about_screen.dart';
import '../screens/profile/help_center_screen.dart';
import '../screens/profile/trusted_devices_screen.dart';
import '../screens/profile/two_factor_screen.dart';
import '../screens/property/area_converter_screen.dart';
import '../screens/property_finance/emi_calculator_screen.dart';
import '../screens/property_finance/gold_calculator_screen.dart';
import '../screens/property_finance/property_finance_tools_screen.dart';
import '../screens/property_finance/property_valuation_screen.dart';
import '../screens/property_finance/sip_calculator_screen.dart';
import '../screens/search/global_search_screen.dart';
import '../screens/share/manage_shares_screen.dart';
import '../services/voice_nav.dart';

/// A voice-navigable destination: the phrases that select it (across English,
/// Hinglish, Telugu, Hindi and Tamil), a display [route] for the confirmation
/// UI, the label spoken back, and the [navigate] action that opens it.
///
/// Matching is deliberately loose (substring + fuzzy) — accents and phrasing
/// vary and the recognizer routinely mis-hears a character or two. Phrase lists
/// are all lowercase and include the English word, common romanized forms, and
/// native-script words.
///
/// ── To add a NEW voice destination: append ONE entry to [kVoiceCommands]. ──
/// Nothing else needs editing: the mic, matcher and navigation all read from
/// this single registry.
class VoiceCommand {
  VoiceCommand({
    required this.id,
    required this.spokenLabel,
    required this.route,
    required this.icon,
    required this.phrases,
    required this.navigate,
  });

  /// Stable identifier (kebab-case), used only for logging/analytics.
  final String id;

  /// The English label spoken back and shown on match, e.g. "Documents" →
  /// "Opening Documents".
  final String spokenLabel;

  /// A display-only route string shown in the confirmation UI (e.g. "/emi").
  /// The app navigates via [navigate] (Navigator / tab switch), not a URL router.
  final String route;

  final IconData icon;

  /// Lowercase keyword forms that select this destination.
  final List<String> phrases;

  /// Opens the destination. Runs on the app-root navigator via [VoiceNav], so it
  /// works from anywhere in the app.
  final VoidCallback navigate;
}

/// The command registry, in match-priority order (first match wins). More
/// specific multi-word destinations come first so a broad word can't shadow
/// them — e.g. "gold calculator" must beat the "gold" investments keyword.
final List<VoiceCommand> kVoiceCommands = [
  // ── Finance calculators (specific multi-word phrases first) ───────────────
  VoiceCommand(
    id: 'emi',
    spokenLabel: 'EMI Calculator',
    route: '/emi',
    icon: Icons.account_balance_rounded,
    phrases: [
      'emi calculator', 'emi', 'loan calculator', 'loan emi', 'loan',
    ],
    navigate: () => VoiceNav.push((_) => const EmiCalculatorScreen()),
  ),
  VoiceCommand(
    id: 'sip',
    spokenLabel: 'SIP Calculator',
    route: '/sip',
    icon: Icons.trending_up_rounded,
    phrases: [
      'sip calculator', 'sip', 'mutual fund calculator',
    ],
    navigate: () => VoiceNav.push((_) => const SipCalculatorScreen()),
  ),
  VoiceCommand(
    id: 'gold-calculator',
    spokenLabel: 'Gold Calculator',
    route: '/gold-calculator',
    icon: Icons.diamond_rounded,
    phrases: [
      'gold calculator', 'gold rate calculator', 'gold value',
    ],
    navigate: () => VoiceNav.push((_) => const GoldCalculatorScreen()),
  ),
  VoiceCommand(
    id: 'area-converter',
    spokenLabel: 'Area Converter',
    route: '/area-converter',
    icon: Icons.straighten_rounded,
    phrases: [
      'area converter', 'area calculator', 'area', 'unit converter',
      'land converter', 'convert area',
    ],
    navigate: () => VoiceNav.push((_) => const AreaConverterScreen()),
  ),
  VoiceCommand(
    id: 'property-valuation',
    spokenLabel: 'Property Valuation',
    route: '/property-valuation',
    icon: Icons.home_work_rounded,
    phrases: [
      'property valuation', 'valuation', 'property value', 'property calculator',
    ],
    navigate: () => VoiceNav.push((_) => const PropertyValuationScreen()),
  ),
  VoiceCommand(
    id: 'finance-tools',
    spokenLabel: 'Finance Tools',
    route: '/tools',
    icon: Icons.calculate_rounded,
    phrases: [
      'finance tools', 'calculators', 'property tools', 'property and finance',
      'tools', 'calculator',
    ],
    navigate: () => VoiceNav.push((_) => const PropertyFinanceToolsScreen()),
  ),

  // ── Add / scan / share (specific verbs win over the wallet nouns) ─────────
  VoiceCommand(
    id: 'add-document',
    spokenLabel: 'Add Document',
    route: '/add-document',
    icon: Icons.note_add_rounded,
    phrases: [
      'add document', 'upload document', 'new document', 'add doc',
      'add a document', 'add new document',
    ],
    navigate: () => VoiceNav.push((_) => const AddDocumentScreen()),
  ),
  VoiceCommand(
    id: 'scanner',
    spokenLabel: 'Scanner',
    route: '/scanner',
    icon: Icons.document_scanner_rounded,
    phrases: [
      'scanner', 'scan', 'scan document', 'scan id', 'camera', 'ocr', 'skyan',
      'స్కాన్', 'స్కానర్',
    ],
    navigate: VoiceNav.scan,
  ),
  VoiceCommand(
    id: 'qr',
    spokenLabel: 'QR Sharing',
    route: '/qr',
    icon: Icons.qr_code_2_rounded,
    phrases: [
      'qr', 'my qr', 'qr code', 'qr sharing', 'share qr', 'shared links',
      'manage shares',
    ],
    navigate: () => VoiceNav.push((_) => const ManageSharesScreen()),
  ),

  // ── Wallets / vaults ──────────────────────────────────────────────────────
  VoiceCommand(
    id: 'identity',
    spokenLabel: 'Identity Wallet',
    route: '/identity',
    icon: Icons.badge_rounded,
    phrases: [
      'identity', 'identity wallet', 'aadhaar', 'aadhar', 'adhaar',
      'pan', 'pan card', 'passport', 'driving licence', 'driving license',
      'licence', 'license', 'voter id', 'voter',
    ],
    navigate: () => VoiceNav.openWallet('Identity Wallet'),
  ),
  VoiceCommand(
    id: 'documents',
    spokenLabel: 'Documents',
    route: '/documents',
    icon: Icons.folder_shared_rounded,
    phrases: [
      'documents', 'document', 'docs', 'my documents', 'document wallet',
      'certificate', 'certificates',
      'దస్తావేజులు', 'పత్రాలు', 'patralu', 'dastavej', 'documentlu',
    ],
    navigate: () => VoiceNav.openWallet('Document Wallet'),
  ),
  VoiceCommand(
    id: 'property',
    spokenLabel: 'Property Wallet',
    route: '/property',
    icon: Icons.home_rounded,
    phrases: [
      'property', 'property wallet', 'land', 'land records', 'real estate',
    ],
    navigate: () => VoiceNav.openWallet('Property Wallet'),
  ),
  VoiceCommand(
    id: 'insurance',
    spokenLabel: 'Insurance Wallet',
    route: '/insurance',
    icon: Icons.shield_rounded,
    phrases: [
      'insurance', 'insurance wallet', 'policy', 'policies',
      'health insurance', 'life insurance', 'vehicle insurance',
    ],
    navigate: () => VoiceNav.openWallet('Insurance Wallet'),
  ),
  VoiceCommand(
    id: 'health',
    spokenLabel: 'Health Wallet',
    route: '/health',
    icon: Icons.favorite_rounded,
    phrases: [
      'health', 'health wallet', 'medical', 'medical records', 'health records',
      'reports', 'prescriptions', 'prescription',
    ],
    navigate: () => VoiceNav.openWallet('Health Wallet'),
  ),
  VoiceCommand(
    id: 'investments',
    spokenLabel: 'Investment Wallet',
    route: '/investments',
    icon: Icons.show_chart_rounded,
    phrases: [
      'investments', 'investment', 'investment wallet', 'mutual funds',
      'mutual fund', 'stocks', 'stock', 'shares', 'gold', 'silver',
      'fixed deposit', 'fixed deposits', 'fd', 'holdings',
    ],
    navigate: () => VoiceNav.openWallet('Investment Wallet'),
  ),
  VoiceCommand(
    id: 'banking',
    spokenLabel: 'Banking Wallet',
    route: '/banking',
    icon: Icons.account_balance_wallet_rounded,
    phrases: [
      'banking', 'banking wallet', 'bank', 'bank account', 'bank accounts',
      'cards', 'card', 'credit card', 'debit card',
      'కార్డులు', 'kardulu',
    ],
    navigate: () => VoiceNav.openWallet('Banking Wallet'),
  ),
  VoiceCommand(
    id: 'passwords',
    spokenLabel: 'Password Vault',
    route: '/passwords',
    icon: Icons.lock_rounded,
    phrases: [
      'passwords', 'password', 'password manager', 'password vault',
      'saved passwords', 'my passwords',
    ],
    navigate: () => VoiceNav.openWallet('Password Vault'),
  ),

  // ── Net worth / assets ────────────────────────────────────────────────────
  VoiceCommand(
    id: 'net-worth',
    spokenLabel: 'Net Worth',
    route: '/net-worth',
    icon: Icons.pie_chart_rounded,
    phrases: [
      'net worth', 'networth', 'wealth', 'net worth analytics',
    ],
    navigate: () => VoiceNav.push((_) => const NetWorthAnalyticsScreen()),
  ),
  VoiceCommand(
    id: 'assets',
    spokenLabel: 'Assets',
    route: '/assets',
    icon: Icons.inventory_2_rounded,
    phrases: [
      'assets', 'asset', 'my assets', 'total assets',
    ],
    navigate: () => VoiceNav.push((_) => const AssetsScreen()),
  ),

  // ── Expenses / tax / notes ────────────────────────────────────────────────
  VoiceCommand(
    id: 'tax-records',
    spokenLabel: 'Tax Records',
    route: '/tax-records',
    icon: Icons.receipt_long_rounded,
    phrases: [
      'tax records', 'tax record', 'income tax', 'tax', 'taxes', 'itr',
      'tax calculator', 'పన్ను', 'పన్నులు', 'pannu', 'pannulu',
    ],
    navigate: () => VoiceNav.push((_) => const TaxRecordsScreen()),
  ),
  VoiceCommand(
    id: 'expenses',
    spokenLabel: 'Expenses',
    route: '/expenses',
    icon: Icons.payments_rounded,
    phrases: [
      'expenses', 'expense', 'spending', 'spends',
      'kharch', 'kharcha', 'ఖర్చులు', 'ఖర్చు', 'kharchulu',
    ],
    navigate: () => VoiceNav.push((_) => const ExpenseDashboardScreen()),
  ),
  VoiceCommand(
    id: 'notes',
    spokenLabel: 'Notes',
    route: '/notes',
    icon: Icons.edit_note_rounded,
    phrases: [
      'notes', 'note', 'my notes',
      'నోట్స్', 'నోటు', 'notelu', 'notulu',
    ],
    navigate: () => VoiceNav.push((_) => const NotesScreen()),
  ),

  // ── Search / notifications ────────────────────────────────────────────────
  VoiceCommand(
    id: 'search',
    spokenLabel: 'Search',
    route: '/search',
    icon: Icons.search_rounded,
    phrases: [
      'search', 'find', 'global search', 'search documents',
    ],
    navigate: () => VoiceNav.push((_) => const GlobalSearchScreen()),
  ),
  VoiceCommand(
    id: 'notifications',
    spokenLabel: 'Notifications',
    route: '/notifications',
    icon: Icons.notifications_rounded,
    phrases: [
      'notifications', 'notification', 'alerts', 'alert', 'bell',
    ],
    navigate: () => VoiceNav.push((_) => const NotificationsScreen()),
  ),

  // ── Settings sub-pages ────────────────────────────────────────────────────
  VoiceCommand(
    id: 'two-factor',
    spokenLabel: 'Two-Factor Authentication',
    route: '/two-factor',
    icon: Icons.verified_user_rounded,
    phrases: [
      'two factor', 'two-factor', 'two factor authentication', '2fa',
      'two step verification',
    ],
    navigate: () => VoiceNav.push((_) => const TwoFactorScreen()),
  ),
  VoiceCommand(
    id: 'trusted-devices',
    spokenLabel: 'Trusted Devices',
    route: '/trusted-devices',
    icon: Icons.devices_rounded,
    phrases: [
      'trusted devices', 'devices', 'my devices', 'trusted device',
    ],
    navigate: () => VoiceNav.push((_) => const TrustedDevicesScreen()),
  ),
  VoiceCommand(
    id: 'help',
    spokenLabel: 'Help Center',
    route: '/help',
    icon: Icons.help_outline_rounded,
    phrases: [
      'help', 'help center', 'support', 'faq', 'contact support',
    ],
    navigate: () => VoiceNav.push((_) => const HelpCenterScreen()),
  ),
  VoiceCommand(
    id: 'about',
    spokenLabel: 'About INO',
    route: '/about',
    icon: Icons.info_outline_rounded,
    phrases: [
      'about', 'about ino', 'about app', 'version', 'app info',
    ],
    navigate: () => VoiceNav.push((_) => const AboutScreen()),
  ),

  // ── Primary tabs (broad words last, so specifics win) ─────────────────────
  VoiceCommand(
    id: 'home',
    spokenLabel: 'Home',
    route: '/home',
    icon: Icons.home_rounded,
    phrases: [
      'home', 'dashboard', 'overview', 'go home', 'main screen',
    ],
    navigate: () => VoiceNav.goToTab(0),
  ),
  VoiceCommand(
    id: 'wallet',
    spokenLabel: 'Wallet',
    route: '/wallet',
    icon: Icons.account_balance_wallet_rounded,
    phrases: [
      'wallet', 'wallets', 'my wallets', 'vault', 'my vault',
    ],
    navigate: () => VoiceNav.goToTab(1),
  ),
  VoiceCommand(
    id: 'reminders',
    spokenLabel: 'Reminders',
    route: '/reminders',
    icon: Icons.alarm_rounded,
    phrases: [
      'reminders', 'reminder', 'bills', 'birthdays', 'renewals', 'due dates',
    ],
    navigate: () => VoiceNav.goToTab(3),
  ),
  VoiceCommand(
    id: 'profile',
    spokenLabel: 'Profile',
    route: '/profile',
    icon: Icons.person_rounded,
    phrases: [
      'profile', 'my profile', 'account', 'my account',
      'ప్రొఫైల్', 'profilu', 'ఖాతా',
    ],
    navigate: () => VoiceNav.goToTab(4),
  ),
  VoiceCommand(
    id: 'settings',
    spokenLabel: 'Settings',
    route: '/settings',
    icon: Icons.settings_rounded,
    phrases: [
      'settings', 'setting', 'preferences', 'security settings', 'security',
      'backup', 'language', 'logout', 'log out', 'sign out',
      'సెట్టింగ్‌లు', 'settingulu',
    ],
    navigate: () => VoiceNav.goToTab(4),
  ),
];

/// Matches recognized speech to a [VoiceCommand], or null when nothing fits.
///
/// Two passes: (1) a direct substring match (handles multi-word phrases, native
/// script and romanized forms inside a longer sentence); (2) a fuzzy per-word
/// match (Levenshtein) for Latin keywords, so a mis-heard character or two
/// ("nots" → "notes", "documnt" → "document") still resolves.
VoiceCommand? matchVoiceCommand(String words) {
  final text = words.toLowerCase().trim();
  if (text.isEmpty) return null;

  // Pass 1 — direct substring (registry order = priority).
  for (final c in kVoiceCommands) {
    for (final p in c.phrases) {
      if (text.contains(p)) return c;
    }
  }

  // Pass 2 — fuzzy, token by token, Latin keywords only.
  final tokens = text
      .split(RegExp(r'[^a-z0-9ఀ-౿ऀ-ॿ஀-௿]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return null;

  VoiceCommand? best;
  var bestDist = 1 << 30;
  for (final c in kVoiceCommands) {
    for (final p in c.phrases) {
      if (p.contains(' ') || p.length < 4 || !_isLatin(p)) continue;
      final threshold = p.length <= 5 ? 1 : 2;
      for (final t in tokens) {
        if (t.length < 3) continue;
        final d = _levenshtein(t, p);
        if (d <= threshold && d < bestDist) {
          bestDist = d;
          best = c;
        }
      }
    }
  }
  return best;
}

bool _isLatin(String s) {
  for (final code in s.codeUnits) {
    if (code > 0x7f) return false;
  }
  return true;
}

/// Classic iterative Levenshtein edit distance (small strings, so O(n·m) is fine).
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      final del = prev[j + 1] + 1;
      final ins = curr[j] + 1;
      final sub = prev[j] + cost;
      curr[j + 1] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// A short list of example phrases shown in the UI so users know what to say.
const List<String> kVoiceCommandExamples = [
  'Open Documents',
  'Open Scanner',
  'Open Investments',
  'Open EMI Calculator',
  'Open Reminders',
  'Open Profile',
  'Open Settings',
  'Go Home',
];
