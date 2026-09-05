import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../services/connectivity_service.dart';
import '../../services/document_protection_store.dart';
import '../../services/offline_document_store.dart';
import '../../services/vault_guard.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_origin.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet/wallet_grid.dart' show localizedWalletName;
import '../../widgets/wallet_modules/module_kit.dart';
import '../shell/shell_controller.dart';
import '../splash/splash_screen.dart';

/// The offline library: documents the user saved to view without internet.
///
/// Everything on this screen works with ZERO network - the list hydrates from
/// `shared_preferences` and every file opens from the app's own storage.
/// Images get a full-screen in-app viewer; PDFs and other files open in the
/// device's default app straight from the local copy.
class OfflineDocumentsScreen extends StatefulWidget {
  const OfflineDocumentsScreen({super.key, this.isRootOffline = false});

  /// True when the app cold-started offline and routed directly here as the root screen.
  final bool isRootOffline;

  @override
  State<OfflineDocumentsScreen> createState() => _OfflineDocumentsScreenState();
}

class _OfflineDocumentsScreenState extends State<OfflineDocumentsScreen>
    with WidgetsBindingObserver {
  final _store = OfflineDocumentStore.instance;
  bool _checkingConnection = false;

  /// Connectivity returned while this screen was the app's root. The user is
  /// not yanked out of whatever they were reading - the banner just offers the
  /// way through, so "I turned my wifi back on" doesn't mean hunting for the
  /// retry button or force-quitting.
  bool _backOnline = false;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded(force: true);
    _store.addListener(_onChanged);
    if (widget.isRootOffline) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (widget.isRootOffline) WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_onChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from Settings (where wifi/data was just turned on) is the
    // one moment worth re-probing; polling on a timer would burn battery for a
    // screen that is, by definition, doing nothing over the network.
    if (state == AppLifecycleState.resumed && !_backOnline) {
      _pollConnection();
    }
  }

  /// A silent probe - no toast either way, it just unlocks the banner's
  /// "continue" affordance when the connection is genuinely back.
  Future<void> _pollConnection() async {
    if (_checkingConnection) return;
    final online = await ConnectivityService.instance.checkOnline(
      timeout: const Duration(milliseconds: 1500),
    );
    if (!mounted || !online) return;
    setState(() => _backOnline = true);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Opens an offline copy, gating protected documents behind the biometric
  /// prompt first - exactly as the online path does in `WalletDetailScreen`.
  ///
  /// Without this the offline library was a way around the lock: a document
  /// marked protected still required Face ID / fingerprint when opened from its
  /// wallet, but its offline copy opened straight from disk with no check at
  /// all. The protection flag belongs to the document, not to the route used to
  /// reach it, so it is enforced here too.
  ///
  /// [OfflineDoc.id] is the original document row's id, which is the same key
  /// [DocumentProtectionStore] stores the flag under - so a document protected
  /// online is automatically protected here, with no extra bookkeeping and no
  /// way for the two to drift apart.
  Future<void> _open(OfflineDoc doc) async {
    final file = File(doc.localPath);
    if (!await file.exists()) {
      // Storage was cleared underneath us - drop the dead entry honestly.
      await _store.remove(doc.id);
      if (!mounted) return;
      showModuleToast(
        context,
        AppLocalizations.of(context).t('fileNoLongerOnDevice'),
        error: true,
      );
      return;
    }
    if (!mounted) return;

    // Gate BEFORE anything is rendered or handed to another app: a cancelled
    // prompt must leave the file completely unrevealed.
    if (DocumentProtectionStore.instance.isProtected(doc.id)) {
      final unlocked = await VaultGuard.instance.ensureUnlocked(
        context,
        reason: AppLocalizations.of(context).t('authProtectedDocReason'),
        title: AppLocalizations.of(context).t('verifyIdentity'),
      );
      if (!unlocked || !mounted) return;
    }

    final decryptedFile = await _store.getDecryptedFile(doc);
    final exists = decryptedFile != null && await decryptedFile.exists();
    if (!mounted) return;
    if (!exists) {
      showModuleToast(
        context,
        'Could not open offline document: Decryption failed or keystore inaccessible',
        error: true,
      );
      return;
    }

    if (doc.isImage) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _OfflineImageViewer(file: decryptedFile, title: doc.name),
        ),
      );
      return;
    }
    // Hand the decrypted copy to whatever the device uses for this type. The MIME
    // type is passed explicitly: open_filex otherwise infers it from the file
    // extension, and a document stored without one (or with an extension it
    // does not know) resolves to no handler at all - which is what made
    // perfectly good saved files look like they simply would not open.
    final result = await OpenFilex.open(decryptedFile.path, type: _mimeFor(doc));
    if (!mounted) return;
    if (result.type == ResultType.done) return;

    // No viewer installed for this type. Rather than dead-ending, offer the
    // file to the system share sheet - "Open with" lives there too, so the
    // user can still reach an app that handles it (or save it elsewhere).
    final l10n = AppLocalizations.of(context);
    final origin = shareOrigin(context);
    try {
      await Share.shareXFiles(
        [XFile(file.path, name: doc.name)],
        subject: doc.name,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (!mounted) return;
      showModuleToast(
        context,
        l10n.t('noAppForExtension').replaceAll('{ext}', doc.extension),
        error: true,
      );
    }
  }

  /// The MIME type for [doc], derived from its extension.
  ///
  /// Only the types the app actually produces or accepts are listed; anything
  /// else returns null so open_filex falls back to its own (larger) table.
  /// `application/octet-stream` is deliberately NOT a default here - it matches
  /// no viewer, so guessing it would guarantee the failure this is avoiding.
  String? _mimeFor(OfflineDoc doc) => switch (doc.extension) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'gif' => 'image/gif',
        'bmp' => 'image/bmp',
        'txt' => 'text/plain',
        'csv' => 'text/csv',
        'doc' => 'application/msword',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        _ => null,
      };

  Future<void> _remove(OfflineDoc doc) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.t('removeOfflineCopyTitle'),
      message: l10n
          .t('removeOfflineCopyBody')
          .replaceAll('{name}', doc.name)
          .replaceAll('{wallet}', localizedWalletName(l10n, doc.wallet)),
      confirmLabel: l10n.t('remove'),
    );
    if (!ok || !mounted) return;
    await _store.remove(doc.id);
    if (!mounted) return;
    showModuleToast(
        context, AppLocalizations.of(context).t('removedFromOffline'));
  }

  String _dateLabel(DateTime d) => '${d.day}/${d.month}/${d.year}';

  IconData _iconFor(OfflineDoc doc) {
    if (doc.isImage) return Icons.image_rounded;
    if (doc.extension == 'pdf') return Icons.picture_as_pdf_rounded;
    return Icons.description_rounded;
  }

  Future<void> _retryConnection() async {
    if (_checkingConnection) return;
    setState(() => _checkingConnection = true);
    final l10n = AppLocalizations.of(context);
    showModuleToast(context, l10n.t('checkingConnection'));
    final isOnline = await ConnectivityService.instance.checkOnline(
      timeout: const Duration(seconds: 3),
    );
    if (!mounted) return;
    setState(() => _checkingConnection = false);
    if (isOnline) {
      _enterOnlineMode();
    } else {
      showModuleToast(context, l10n.t('stillOffline'), error: true);
    }
  }

  /// Hands the app back to the normal startup path now that there is internet.
  ///
  /// Going through the splash rather than straight to the shell is deliberate:
  /// nothing has been warmed or authenticated in this launch, and the splash is
  /// the one place that resolves the session and preloads the working set.
  void _enterOnlineMode() {
    showModuleToast(context, AppLocalizations.of(context).t('connectedOnline'));
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  /// The offline-mode notice, which becomes the way back in once the
  /// connection returns.
  Widget _statusBanner(AppPalette palette, AppLocalizations l10n) {
    final accent = _backOnline ? AppColors.primaryGreen : Colors.amber;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _backOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t(_backOnline ? 'backOnline' : 'offlineMode'),
                  style: AppText.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  l10n.t(_backOnline
                      ? 'backOnlineSubtitle'
                      : 'offlineModeSubtitle'),
                  style: AppText.caption.copyWith(
                    fontSize: 11,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _backOnline
                ? _enterOnlineMode
                : (_checkingConnection ? null : _retryConnection),
            icon: _checkingConnection
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _backOnline
                        ? Icons.arrow_forward_rounded
                        : Icons.refresh_rounded,
                    size: 16,
                  ),
            label: Text(
              l10n.t(_backOnline ? 'continue' : 'retryConnection'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final docs = _store.docs;

    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        sky: divineGlassEnabled(context),
        child: SafeArea(
          top: !divineGlassEnabled(context),
          bottom: false,
          child: Column(
            children: [
              ModuleHeader(
                title: l10n.t('offlineDocuments'),
                subtitle: docs.isEmpty
                    ? l10n.t('offlineDocsEmptySubtitle')
                    : l10n
                        .t('offlineDocsCount')
                        .replaceAll('{n}', '${docs.length}'),
                // Root-offline is the only route in the stack, so there is
                // nowhere to go back to and [InoBackButton] hides itself; from
                // Home this pops back to Home. Either way the default is right.
                onBack: null,
                actions: [
                  if (widget.isRootOffline)
                    IconButton(
                      tooltip: l10n.t('retryConnection'),
                      icon: _checkingConnection
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      onPressed: _checkingConnection ? null : _retryConnection,
                    ),
                ],
              ),
              if (widget.isRootOffline) _statusBanner(palette, l10n),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    if (!_store.isLoaded)
                      SliverToBoxAdapter(
                        child:
                            ModuleLoading(message: l10n.t('loadingOfflineDocs')),
                      )
                    else if (docs.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: ModuleEmptyState(
                          icon: Icons.offline_pin_rounded,
                          title: widget.isRootOffline
                              ? l10n.t('offlineMode')
                              : l10n.t('nothingSavedYet'),
                          message: widget.isRootOffline
                              ? l10n.t('noOfflineDocsYet')
                              : l10n.t('offlineDocsEmptyMessage'),
                          actionLabel: widget.isRootOffline
                              ? l10n.t('retryConnection')
                              : l10n.t('browseWallets'),
                          onAction: () {
                            if (widget.isRootOffline) {
                              _retryConnection();
                            } else {
                              ShellController.tab.value = 1;
                              Navigator.of(context).popUntil((r) => r.isFirst);
                            }
                          },
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screen,
                          AppSpacing.sm,
                          AppSpacing.screen,
                          0,
                        ),
                        sliver: SliverList.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.sm),
                          // No FadeSlideIn: recycled rows replay the entrance
                          // every time they scroll back into view.
                          itemBuilder: (context, i) {
                            final doc = docs[i];
                            return _OfflineDocTile(
                              key: ValueKey(doc.id),
                              doc: doc,
                              icon: _iconFor(doc),
                              subtitle:
                                  '${localizedWalletName(l10n, doc.wallet)} · '
                                  '${doc.sizeLabel} · '
                                  '${l10n.t('savedOn').replaceAll('{date}', _dateLabel(doc.savedAt))}',
                              protected: DocumentProtectionStore.instance
                                  .isProtected(doc.id),
                              onTap: () => _open(doc),
                              onRemove: () => _remove(doc),
                            );
                          },
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineDocTile extends StatelessWidget {
  const _OfflineDocTile({
    super.key,
    required this.doc,
    required this.icon,
    required this.subtitle,
    required this.protected,
    required this.onTap,
    required this.onRemove,
  });

  final OfflineDoc doc;
  final IconData icon;
  final String subtitle;

  /// Whether opening this copy will require biometric authentication, so the
  /// prompt is never a surprise.
  final bool protected;

  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.99,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: AppColors.primaryGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: palette.textSecondary,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (protected) ...[
                Icon(
                  Icons.lock_rounded,
                  size: 16,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                Icons.offline_pin_rounded,
                size: 20,
                color: AppColors.primaryGreen,
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: AppLocalizations.of(context).t('removeOfflineCopy'),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen offline image viewer - renders straight from the local file,
/// with pinch-to-zoom. No network anywhere.
class _OfflineImageViewer extends StatelessWidget {
  const _OfflineImageViewer({required this.file, required this.title});

  final File file;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Center(child: InoBackButton(size: 42)),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (context, _, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                AppLocalizations.of(context).t('imageCouldNotBeDisplayed'),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
