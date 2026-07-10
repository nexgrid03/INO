import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure-preference store for *which documents require biometric unlock*.
///
/// Stores only a set of document IDs (one boolean protection flag per document)
/// — never document content and never biometric data. Backed by
/// `shared_preferences` and exposed as a [ChangeNotifier] so lock badges rebuild
/// the moment protection changes.
class DocumentProtectionStore extends ChangeNotifier {
  DocumentProtectionStore._();
  static final DocumentProtectionStore instance = DocumentProtectionStore._();

  static const String _key = 'protected_document_ids';

  final Set<String> _ids = {};
  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Loads the persisted set. Safe to call once at startup.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _ids
        ..clear()
        ..addAll(prefs.getStringList(_key) ?? const []);
    } catch (_) {
      // No plugin (e.g. tests) → treat as empty, never throw.
    }
    _loaded = true;
    notifyListeners();
  }

  bool isProtected(String documentId) => _ids.contains(documentId);

  int get protectedCount => _ids.length;

  Future<void> setProtected(String documentId, bool value) async {
    final changed = value ? _ids.add(documentId) : _ids.remove(documentId);
    if (!changed) return;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _ids.toList());
    } catch (_) {
      // Best-effort; the in-memory set stays correct for this session.
    }
  }

  /// Clears the per-document protection flags (in-memory + persisted) so the next
  /// account doesn't inherit the previous user's set. Called from [SessionReset].
  Future<void> clear() async {
    _ids.clear();
    _loaded = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Best-effort.
    }
  }
}
