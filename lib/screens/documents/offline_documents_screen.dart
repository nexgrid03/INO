import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../l10n/app_localizations.dart';
import '../../services/document_protection_store.dart';
import '../../services/offline_document_store.dart';
import '../../services/vault_guard.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet/wallet_grid.dart' show localizedWalletName;
import '../../widgets/wallet_modules/module_kit.dart';
import '../shell/shell_controller.dart';

/// The offline library: documents the user saved to view without internet.
///
/// Everything on this screen works with ZERO network - the list hydrates from
/// `shared_preferences` and every file opens from the app's own storage.
/// Images get a full-screen in-app viewer; PDFs and other files open in the
/// device's default app straight from the local copy.
class OfflineDocumentsScreen extends StatefulWidget {
  const OfflineDocumentsScreen({super.key});

  @override
  State<OfflineDocumentsScreen> createState() => _OfflineDocumentsScreenState();
}

class _OfflineDocumentsScreenState extends State<OfflineDocumentsScreen> {
  final _store = OfflineDocumentStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
    _store.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
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

    if (doc.isImage) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _OfflineImageViewer(file: file, title: doc.name),
        ),
      );
      return;
    }
    final result = await OpenFilex.open(file.path);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      showModuleToast(
        context,
        AppLocalizations.of(context)
            .t('noAppForExtension')
            .replaceAll('{ext}', doc.extension),
        error: true,
      );
    }
  }

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
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    if (!_store.isLoaded)
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.screen,
                          AppSpacing.md,
                          AppSpacing.screen,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: ModuleSkeleton(height: 72, count: 4),
                        ),
                      )
                    else if (docs.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: ModuleEmptyState(
                          icon: Icons.offline_pin_rounded,
                          title: l10n.t('nothingSavedYet'),
                          message: l10n.t('offlineDocsEmptyMessage'),
                          actionLabel: l10n.t('browseWallets'),
                          onAction: () {
                            ShellController.tab.value = 1;
                            Navigator.of(context).popUntil((r) => r.isFirst);
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
