import 'package:flutter/material.dart';

/// The eight destinations reachable by voice from the Home screen.
enum VoiceCommandId {
  documents,
  notes,
  cards,
  expenses,
  scanner,
  taxRecords,
  profile,
  settings,
}

/// A voice-navigable destination: the phrases that select it (across English,
/// Telugu and Hinglish), a human display [route] for the debug/confirmation UI,
/// and the label spoken back in confirmation.
///
/// Matching is deliberately loose (substring + fuzzy) — accents and phrasing
/// vary and the recognizer routinely mis-hears a character or two. The phrase
/// lists include the English word, common Hinglish/romanized forms, and the
/// Telugu word (Telugu script + romanized), all lowercase.
class VoiceCommand {
  const VoiceCommand({
    required this.id,
    required this.spokenLabel,
    required this.route,
    required this.icon,
    required this.phrases,
  });

  final VoiceCommandId id;

  /// The English label spoken back and shown on match, e.g. "Documents" →
  /// "Opening Documents".
  final String spokenLabel;

  /// A display-only route string shown in the debug/confirmation UI
  /// (e.g. "/notes"). The app navigates via Navigator, not a URL router.
  final String route;

  final IconData icon;

  /// Lowercase keyword forms in English / Hinglish / Telugu that select this
  /// destination.
  final List<String> phrases;
}

/// The command table, in match-priority order (first match wins). More specific
/// multi-word destinations (e.g. "tax records") come before shorter ones so a
/// broad word can't shadow them.
const List<VoiceCommand> kVoiceCommands = [
  VoiceCommand(
    id: VoiceCommandId.taxRecords,
    spokenLabel: 'Tax Records',
    route: '/tax-records',
    icon: Icons.receipt_long_rounded,
    phrases: [
      'tax records', 'tax record', 'income tax', 'tax', 'taxes', 'itr',
      'పన్ను', 'పన్నులు', 'pannu', 'pannulu',
    ],
  ),
  VoiceCommand(
    id: VoiceCommandId.documents,
    spokenLabel: 'Documents',
    route: '/documents',
    icon: Icons.folder_shared_rounded,
    phrases: [
      'documents', 'document', 'docs', 'my documents',
      'దస్తావేజులు', 'పత్రాలు', 'patralu', 'dastavej', 'dastavez',
      'documentlu',
    ],
  ),
  VoiceCommand(
    id: VoiceCommandId.notes,
    spokenLabel: 'Notes',
    route: '/notes',
    icon: Icons.edit_note_rounded,
    phrases: [
      'notes', 'note', 'my notes',
      'నోట్స్', 'నోటు', 'notelu', 'notulu',
    ],
  ),
  VoiceCommand(
    id: VoiceCommandId.cards,
    spokenLabel: 'Cards',
    route: '/cards',
    icon: Icons.credit_card_rounded,
    phrases: [
      'cards', 'card', 'my cards', 'banking', 'bank',
      'కార్డులు', 'కార్డు', 'kardulu',
    ],
  ),
  VoiceCommand(
    id: VoiceCommandId.expenses,
    spokenLabel: 'Expenses',
    route: '/expenses',
    icon: Icons.account_balance_wallet_rounded,
    phrases: [
      'expenses', 'expense', 'spending', 'spends',
      'kharch', 'kharcha', 'ఖర్చులు', 'ఖర్చు', 'kharchulu',
    ],
  ),
  VoiceCommand(
    id: VoiceCommandId.scanner,
    spokenLabel: 'Scanner',
    route: '/scanner',
    icon: Icons.document_scanner_rounded,
    phrases: [
      'scanner', 'scan', 'scan document', 'skyan',
      'స్కాన్', 'స్కానర్',
    ],
  ),
  VoiceCommand(
    id: VoiceCommandId.profile,
    spokenLabel: 'Profile',
    route: '/profile',
    icon: Icons.person_rounded,
    phrases: [
      'profile', 'my profile', 'account',
      'ప్రొఫైల్', 'profilu', 'ఖాతా',
    ],
  ),
  VoiceCommand(
    id: VoiceCommandId.settings,
    spokenLabel: 'Settings',
    route: '/settings',
    icon: Icons.settings_rounded,
    phrases: [
      'settings', 'setting',
      'సెట్టింగ్‌లు', 'సెట్టింగులు', 'settingulu',
    ],
  ),
];

/// Matches recognized speech to a [VoiceCommand], or null when nothing fits.
///
/// Two passes: (1) a direct substring match (handles multi-word phrases, Telugu
/// script and romanized forms inside a longer sentence); (2) a fuzzy per-word
/// match (Levenshtein) for Latin keywords, so a mis-heard character or two
/// ("nots" → "notes", "documnt" → "document") still resolves.
VoiceCommand? matchVoiceCommand(String words) {
  final text = words.toLowerCase().trim();
  if (text.isEmpty) return null;

  // Pass 1 — direct substring.
  for (final c in kVoiceCommands) {
    for (final p in c.phrases) {
      if (text.contains(p)) return c;
    }
  }

  // Pass 2 — fuzzy, token by token, Latin keywords only.
  final tokens = text
      .split(RegExp(r'[^a-z0-9ఀ-౿]+'))
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
  'Open Notes',
  'Open Cards',
  'Open Expenses',
  'Open Scanner',
  'Open Tax Records',
  'Open Profile',
  'Open Settings',
];
