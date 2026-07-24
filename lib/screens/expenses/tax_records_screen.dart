import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/expense_models.dart';
import '../../services/camera_permission_service.dart';
import '../../services/expense_store.dart';
import '../../services/gallery_import_service.dart';
import '../../services/pdf_import_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_origin.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';

/// The Tax Document Vault — Form 16, 26AS, AIS, TDS, salary slips, proofs, rent
/// receipts, medical & insurance bills, home-loan certificates — filed under the
/// selected financial year.
class TaxRecordsScreen extends StatefulWidget {
  const TaxRecordsScreen({super.key});

  @override
  State<TaxRecordsScreen> createState() => _TaxRecordsScreenState();
}

class _TaxRecordsScreenState extends State<TaxRecordsScreen> {
  final _store = ExpenseStore.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Hydrate the vault from Supabase (no-op when already loaded / signed out).
    _store.ensureLoaded();
  }

  Future<void> _upload(TaxDocType type) async {
    final palette = AppPalette.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill))),
            const SizedBox(height: AppSpacing.sm),
            Text('Upload ${type.label}',
                style: AppText.subtitle.copyWith(color: palette.textPrimary)),
            ListTile(
              leading:
                  const Icon(Icons.image_rounded, color: AppColors.primaryGreen),
              title: const Text('Photo / Image'),
              onTap: () => Navigator.of(context).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded,
                  color: AppColors.lightBlue),
              title: const Text('PDF'),
              onTap: () => Navigator.of(context).pop('pdf'),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (choice == 'image') {
        final access = await CameraPermissionService.instance.requestPhotos();
        if (access != CameraAccess.granted) {
          _toast('Photo access is needed to upload', error: true);
          return;
        }
        final path = await GalleryImportService.instance.pickImage();
        if (path != null) {
          _store.addTaxDocument(
            type: type,
            fileName: path.split(RegExp(r'[\\/]')).last,
            filePath: path,
            isPdf: false,
          );
        }
      } else {
        final picked = await PdfImportService.instance.pickPdf();
        if (picked != null) {
          _store.addTaxDocument(
            type: type,
            fileName: picked.name,
            filePath: picked.path,
            isPdf: true,
          );
        }
      }
    } on PdfImportException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } catch (_) {
      if (mounted) _toast('Could not upload the document', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shares every tax document filed under the selected financial year in one
  /// go — the "Share Tax Folder" action (e.g. to send to a CA).
  Future<void> _shareFolder() async {
    final fy = _store.selectedYear;
    final docs = _store.taxDocumentsForYear(fy);
    if (docs.isEmpty) {
      _toast('No tax documents to share for FY ${fy.label}', error: true);
      return;
    }
    final origin = shareOrigin(context);
    try {
      await Share.shareXFiles(
        [for (final d in docs) XFile(d.filePath)],
        subject: 'INO Tax Folder — FY ${fy.label}',
        text: '${docs.length} tax document(s) for FY ${fy.label}',
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (mounted) _toast('Could not share the tax folder', error: true);
    }
  }

  void _toast(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Stack(
          children: [
            ListenableBuilder(
              listenable: _store,
              builder: (context, _) {
                final fy = _store.selectedYear;
                final total = _store.taxDocumentsForYear(fy).length;
                return Column(
                  children: [
                    _Header(
                        yearLabel: fy.label,
                        count: total,
                        onBack: () => Navigator.of(context).maybePop(),
                        onShare: _shareFolder),
                    Expanded(
                      child: ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                            AppSpacing.screen, AppSpacing.xl),
                        children: [
                          for (final type in TaxDocType.values)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: _TypeSection(
                                type: type,
                                docs: _store.taxDocumentsOfType(type, fy),
                                onUpload: () => _upload(type),
                                onRemove: _store.removeTaxDocument,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_busy)
              Container(
                color: Colors.black.withValues(alpha: 0.15),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _TypeSection extends StatelessWidget {
  const _TypeSection({
    required this.type,
    required this.docs,
    required this.onUpload,
    required this.onRemove,
  });

  final TaxDocType type;
  final List<TaxDocument> docs;
  final VoidCallback onUpload;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(type.icon, color: AppColors.primaryGreen, size: 21),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary, fontSize: 14)),
                    Text(docs.isEmpty ? 'No files yet' : '${docs.length} file(s)',
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                  ],
                ),
              ),
              PressableScale(
                pressedScale: 0.9,
                child: GestureDetector(
                  onTap: onUpload,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded,
                            size: 16, color: AppColors.darkGreen),
                        SizedBox(width: 3),
                        Text('Upload',
                            style: TextStyle(
                                color: AppColors.darkGreen,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (docs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final d in docs)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                        d.isPdf
                            ? Icons.picture_as_pdf_rounded
                            : Icons.image_rounded,
                        size: 18,
                        color: d.isPdf
                            ? AppColors.lightBlue
                            : palette.textSecondary),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => OpenFilex.open(d.filePath),
                        child: Text(d.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption
                                .copyWith(color: palette.textPrimary)),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => onRemove(d.id),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: palette.textFaint),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.yearLabel,
      required this.count,
      required this.onBack,
      required this.onShare});

  final String yearLabel;
  final int count;
  final VoidCallback onBack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
          AppSpacing.screen, AppSpacing.md),
      child: Row(
        children: [
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onBack,
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 21, color: palette.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tax Records',
                    style: AppText.headline
                        .copyWith(color: palette.textPrimary, fontSize: 21)),
                Text('FY $yearLabel · $count document(s)',
                    style: AppText.caption.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: AppColors.primaryGreen.withValues(alpha: 0.12),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onShare,
                child: const SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.ios_share_rounded,
                      size: 20, color: AppColors.darkGreen),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
