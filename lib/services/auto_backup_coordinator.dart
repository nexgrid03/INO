import 'dart:async';
import 'dart:developer' as developer;

import '../repositories/document_repository.dart';
import '../repositories/user_repository.dart';
import 'app_settings.dart';
import 'auth_service.dart';
import 'backup_service.dart';

/// Runs a cloud backup automatically after documents change, but only when the
/// user has Auto Backup enabled.
///
/// Listens to [DocumentRepository.revision] (bumped on every create / delete)
/// and debounces so a burst of edits produces a single backup a little later.
/// Fetches the profile itself, so callers don't have to thread it in.
///
/// Three guards keep an upload storm from cascading into a backup storm (each
/// backup is itself a listAll + Storage upload, so unthrottled it multiplies
/// every write):
///   • a debounce window, so a burst of edits coalesces into one run;
///   • single-flight, so a change arriving mid-backup queues exactly one
///     follow-up instead of overlapping uploads;
///   • a minimum interval between runs, so sustained editing produces at most
///     one backup every few minutes. Nothing is lost - the trailing run always
///     captures the final state.
class AutoBackupCoordinator {
  AutoBackupCoordinator._();
  static final AutoBackupCoordinator instance = AutoBackupCoordinator._();

  static const _debounceWindow = Duration(seconds: 30);
  static const _minInterval = Duration(minutes: 5);

  Timer? _debounce;
  bool _started = false;
  bool _running = false;
  bool _dirty = false;
  DateTime? _lastRun;

  /// Begins watching for document changes. Safe to call once at startup.
  void start() {
    if (_started) return;
    _started = true;
    DocumentRepository.revision.addListener(_onDocumentsChanged);
  }

  void _onDocumentsChanged() {
    if (!AppSettings.instance.autoBackup.value) return;
    if (!AuthService.instance.isSignedIn) return;
    if (_running) {
      // A backup is in progress; remember that the data moved on and run once
      // more when it finishes, rather than piling up parallel uploads.
      _dirty = true;
      return;
    }
    _schedule(_debounceWindow);
  }

  void _schedule(Duration after) {
    // Respect the minimum spacing between runs: if the last backup was recent,
    // push this one out to the boundary instead of dropping it.
    final last = _lastRun;
    if (last != null) {
      final sinceLast = DateTime.now().difference(last);
      final remaining = _minInterval - sinceLast;
      if (remaining > after) after = remaining;
    }
    _debounce?.cancel();
    _debounce = Timer(after, _runBackup);
  }

  Future<void> _runBackup() async {
    if (_running) return;
    _running = true;
    try {
      final uid = AuthService.instance.currentUser?.id;
      if (uid == null) return;
      final profile = await UserRepository.instance.getProfileByAuthId(uid);
      if (profile == null) return;
      developer.log('auto-backup: documents changed → backing up',
          name: 'backup');
      await BackupService.instance.backupNow(profile: profile);
      _lastRun = DateTime.now();
    } catch (e) {
      developer.log('auto-backup failed: $e', name: 'backup');
    } finally {
      _running = false;
      if (_dirty) {
        // Documents changed while we were uploading - one trailing run picks
        // up the final state (spaced by the same debounce + min interval).
        _dirty = false;
        _schedule(_debounceWindow);
      }
    }
  }
}
