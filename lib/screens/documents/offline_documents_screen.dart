import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../services/offline_document_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet_modules/module_kit.dart';

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

  Future<void> _open(OfflineDoc doc) async {
    final file = File(doc.localPath);
    if (!await file.exists()) {
      // Storage was cleared underneath us - drop the dead entry honestly.
      await _store.remove(doc.id);
      if (!mounted) return;
      showModuleToast(context, 'This file is no longer on the device',
          error: true);
      return;
    }
    if (!mounted) return;
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
        'No app on this device can open .${doc.extension} files',
        error: true,
      );
    }
  }

  Future<void> _remove(OfflineDoc doc) async {
    final ok = await confirmDestructive(
      context,
      title: 'Remove offline copy?',
      message: '"${doc.name}" will no longer be viewable without internet. '
          'The original in your ${doc.wallet} is not touched.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    await _store.remove(doc.id);
    if (!mounted) return;
    showModuleToast(context, 'Removed from offline');
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
    final docs = _store.docs;

    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: ModuleHeader(
                    title: 'Offline documents',
                    subtitle: docs.isEmpty
                        ? 'Saved to this device, viewable anytime'
                        : '${docs.length} saved · no internet needed',
                  ),
                ),
              ),
              if (!_store.isLoaded)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: ModuleSkeleton(height: 72, count: 4),
                  ),
                )
              else if (docs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ModuleEmptyState(
                    icon: Icons.offline_pin_rounded,
                    title: 'Nothing saved yet',
                    message:
                        'Open any document in your wallets and tap the '
                        'save-offline button. A copy is kept on this device '
                        'so you can view it anytime - even with no internet.',
                    actionLabel: 'Browse wallets',
                    onAction: () => Navigator.of(context).maybePop(),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      return FadeSlideIn(
                        delay: Duration(milliseconds: (i * 35).clamp(0, 300)),
                        offset: 10,
                        child: _OfflineDocTile(
                          doc: doc,
                          icon: _iconFor(doc),
                          subtitle:
                              '${doc.wallet} · ${doc.sizeLabel} · saved ${_dateLabel(doc.savedAt)}',
                          onTap: () => _open(doc),
                          onRemove: () => _remove(doc),
                        ),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineDocTile extends StatelessWidget {
  const _OfflineDocTile({
    required this.doc,
    required this.icon,
    required this.subtitle,
    required this.onTap,
    required this.onRemove,
  });

  final OfflineDoc doc;
  final IconData icon;
  final String subtitle;
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
          padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
          decoration: BoxDecoration(
            gradient: palette.cardGradient,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
            boxShadow: palette.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: AppColors.primaryGreen),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption
                          .copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              // The offline badge - the whole point of this list.
              const Icon(Icons.offline_pin_rounded,
                  size: 18, color: AppColors.primaryGreen),
              IconButton(
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove offline copy',
                icon: Icon(Icons.delete_outline_rounded,
                    size: 19, color: palette.textSecondary),
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
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This image could not be displayed.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
