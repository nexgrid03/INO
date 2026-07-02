import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/user_profile.dart';
import '../../services/app_settings.dart';
import '../../services/backup_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatting.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';

/// Cloud Backup — shows the last backup time, runs a manual backup (with a
/// determinate progress bar), and lists / restores previous backups.
class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  List<CloudBackup>? _backups;
  bool _backingUp = false;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    try {
      final list = await BackupService.instance.listBackups();
      if (!mounted) return;
      setState(() {
        _backups = list;
        _error = null;
      });
    } catch (e) {
      developer.log('listBackups error: $e', name: 'backup', error: e);
      if (!mounted) return;
      setState(() {
        _backups = const [];
        _error = 'Could not load your backups. Pull to retry.';
      });
    }
  }

  Future<void> _backupNow() async {
    setState(() {
      _backingUp = true;
      _progress = 0;
      _error = null;
    });
    try {
      await BackupService.instance.backupNow(
        profile: widget.profile,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      BiometricUx.successSnack(context, 'Backup completed.');
      await _loadBackups();
    } catch (e) {
      developer.log('backupNow error: $e', name: 'backup', error: e);
      if (!mounted) return;
      setState(() => _error = 'Backup failed. Check your connection and retry.');
      BiometricUx.errorSnack(context, 'Backup failed. Please try again.');
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _restore(CloudBackup backup) async {
    try {
      BiometricUx.successSnack(context, 'Preparing your backup…');
      final file = await BackupService.instance.download(backup);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)],
          subject: 'INO backup ${backup.name}');
    } catch (e) {
      developer.log('restore error: $e', name: 'backup', error: e);
      if (mounted) {
        BiometricUx.errorSnack(context, 'Could not restore this backup.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final backups = _backups;
    return SettingsScaffold(
      title: 'Cloud Backup',
      child: RefreshIndicator(
        onRefresh: _loadBackups,
        color: AppColors.primaryGreen,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md,
              AppSpacing.screen, AppSpacing.xl),
          children: [
            _StatusCard(backingUp: _backingUp, progress: _progress),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!,
                  style: AppText.caption.copyWith(color: AppColors.critical)),
            ],
            const SizedBox(height: AppSpacing.lg),
            SettingsPrimaryButton(
              label: _backingUp ? 'Backing up…' : 'Back Up Now',
              icon: Icons.cloud_upload_rounded,
              busy: _backingUp,
              onPressed: _backingUp ? null : _backupNow,
            ),
            const SizedBox(height: AppSpacing.section),
            Text('PREVIOUS BACKUPS',
                style: AppText.label.copyWith(color: palette.textFaint)),
            const SizedBox(height: AppSpacing.sm),
            if (backups == null)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4)),
              )
            else if (backups.isEmpty)
              _EmptyBackups()
            else
              for (final b in backups) ...[
                _BackupTile(backup: b, onRestore: () => _restore(b)),
                const SizedBox(height: AppSpacing.sm),
              ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.backingUp, required this.progress});

  final bool backingUp;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.cloud_done_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ValueListenableBuilder<DateTime?>(
                  valueListenable: AppSettings.instance.lastBackupAt,
                  builder: (context, last, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last backup',
                          style: AppText.caption
                              .copyWith(color: palette.textSecondary)),
                      const SizedBox(height: 2),
                      Text(
                        last == null
                            ? 'No backups yet'
                            : formatRelativeDate(last),
                        style: AppText.title
                            .copyWith(color: palette.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (backingUp) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: progress == 0 ? null : progress,
                minHeight: 6,
                backgroundColor: palette.surfaceVariant,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primaryGreen),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({required this.backup, required this.onRestore});

  final CloudBackup backup;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.surfaceVariant,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.archive_rounded,
                color: palette.textSecondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  backup.updatedAt != null
                      ? formatRelativeDate(backup.updatedAt!)
                      : backup.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(color: palette.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(formatBytes(backup.sizeBytes),
                    style:
                        AppText.caption.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
          TextButton(
            onPressed: onRestore,
            child: const Text('Restore',
                style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _EmptyBackups extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Icon(Icons.inbox_rounded, color: palette.textFaint, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You haven’t backed up yet. Tap “Back Up Now” to create your first cloud backup.',
              style: AppText.body
                  .copyWith(color: palette.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
