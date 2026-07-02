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
/// and debounces so a burst of edits produces a single backup a few seconds
/// later. Fetches the profile itself, so callers don't have to thread it in.
class AutoBackupCoordinator {
  AutoBackupCoordinator._();
  static final AutoBackupCoordinator instance = AutoBackupCoordinator._();

  static const _debounceWindow = Duration(seconds: 4);

  Timer? _debounce;
  bool _started = false;

  /// Begins watching for document changes. Safe to call once at startup.
  void start() {
    if (_started) return;
    _started = true;
    DocumentRepository.revision.addListener(_onDocumentsChanged);
  }

  void _onDocumentsChanged() {
    if (!AppSettings.instance.autoBackup.value) return;
    if (!AuthService.instance.isSignedIn) return;
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, _runBackup);
  }

  Future<void> _runBackup() async {
    try {
      final uid = AuthService.instance.currentUser?.id;
      if (uid == null) return;
      final profile = await UserRepository.instance.getProfileByAuthId(uid);
      if (profile == null) return;
      developer.log('auto-backup: documents changed → backing up',
          name: 'backup');
      await BackupService.instance.backupNow(profile: profile);
    } catch (e) {
      developer.log('auto-backup failed: $e', name: 'backup');
    }
  }
}
