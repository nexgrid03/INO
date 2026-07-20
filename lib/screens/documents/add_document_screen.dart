import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../data/reminder_store.dart';
import '../../data/wallet_detail_repository.dart';
import '../../models/reminder_models.dart';
import '../../models/scan_models.dart';
import '../../models/wallet_detail_models.dart';
import '../../repositories/document_repository.dart';
import '../../services/camera_permission_service.dart';
import '../../services/category_store.dart';
import '../../services/document_protection_store.dart';
import '../../services/document_scanner_service.dart';
import '../../services/gallery_import_service.dart';
import '../../services/pdf_import_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/documents/create_category_sheet.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet/wallet_grid.dart' show localizedWalletName;

/// The source a user picks to add a document.
enum _DocSource { scan, pdf, image }

extension _DocSourceX on _DocSource {
  /// The localized card title.
  String localizedTitle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (this) {
      case _DocSource.scan:
        return l10n.t('scanDocument');
      case _DocSource.pdf:
        return l10n.t('uploadPdf');
      case _DocSource.image:
        return l10n.t('uploadImage');
    }
  }

  /// The localized card description.
  String localizedDescription(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (this) {
      case _DocSource.scan:
        return l10n.t('scanUsingCamera');
      case _DocSource.pdf:
        return l10n.t('choosePdfFile');
      case _DocSource.image:
        return l10n.t('selectImage');
    }
  }

  IconData get icon {
    switch (this) {
      case _DocSource.scan:
        return Icons.photo_camera_rounded;
      case _DocSource.pdf:
        return Icons.picture_as_pdf_rounded;
      case _DocSource.image:
        return Icons.image_rounded;
    }
  }

  Color get color {
    switch (this) {
      case _DocSource.scan:
        return AppColors.primaryGreen;
      case _DocSource.pdf:
        return AppColors.lightBlue;
      case _DocSource.image:
        return AppColors.secondaryGreen;
    }
  }

  IconData get fileIcon {
    switch (this) {
      case _DocSource.scan:
      case _DocSource.pdf:
        return Icons.picture_as_pdf_rounded;
      case _DocSource.image:
        return Icons.image_rounded;
    }
  }
}

const _wallets = <(String, IconData)>[
  ('Identity Wallet', Icons.badge_rounded),
  ('Document Wallet', Icons.folder_shared_rounded),
  ('Property Wallet', Icons.home_work_rounded),
  ('Insurance Wallet', Icons.shield_rounded),
  ('Health Wallet', Icons.favorite_rounded),
  ('Investment Wallet', Icons.trending_up_rounded),
  ('Banking Wallet', Icons.account_balance_rounded),
  ('Password Vault', Icons.lock_rounded),
];

/// Sentinel returned by the category picker when the user taps "Create new
/// category" instead of an existing one.
const String _kCreateCategory = '__create_category__';

/// Add Document — the fastest path to get a document into the vault.
///
/// Pick a source (scan / image), then fill a short set of details and save.
/// Deliberately minimal: no analytics, dashboards or extra sections.
class AddDocumentScreen extends StatefulWidget {
  const AddDocumentScreen({
    super.key,
    this.initialWallet,
    this.prefill,
    this.initialFilePath,
  });

  /// Pre-selects a wallet when opened from a specific wallet's detail screen.
  final String? initialWallet;

  /// When arriving from the Scan & OCR flow, pre-populates the form with the
  /// confirmed extraction so the user lands straight on Save.
  final OcrResult? prefill;

  /// Local path of the captured/imported image, uploaded to Storage on save.
  final String? initialFilePath;

  @override
  State<AddDocumentScreen> createState() => _AddDocumentScreenState();
}

class _AddDocumentScreenState extends State<AddDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _tagsController = TextEditingController();
  final _notesController = TextEditingController();

  _DocSource? _source;
  String? _wallet;
  String? _category;
  DateTime? _expiry;

  String? _tempFileName;
  String? _localFilePath; // real on-device file to upload to Storage
  String? _recordNumber; // OCR-extracted document number (Aadhaar / PAN / …)
  bool _saving = false;
  bool _capturing = false; // true while the camera/gallery picker is open
  bool _protect = false; // require biometrics to open this document

  @override
  void initState() {
    super.initState();
    _localFilePath = widget.initialFilePath;
    // Pre-select a wallet passed in by the launcher (e.g. from a wallet page).
    if (widget.initialWallet != null &&
        _wallets.any((w) => w.$1 == widget.initialWallet)) {
      _wallet = widget.initialWallet;
    }

    final prefill = widget.prefill;
    if (prefill != null) {
      // Arrived from the Scan → OCR flow: AUTO-FILL the form from the confirmed
      // extraction so the user just reviews and saves.
      _source = _DocSource.scan;
      _tempFileName = _localFilePath != null
          ? _localFilePath!.split(RegExp(r'[\\/]')).last
          : 'Scanned document';
      if (prefill.documentName.isNotEmpty) {
        _nameController.text = prefill.documentName;
      }
      if (_wallets.any((w) => w.$1 == prefill.suggestedWallet)) {
        _wallet = prefill.suggestedWallet;
      }
      if (CategoryStore.instance.exists(prefill.category)) {
        _category = prefill.category;
      }
      if (prefill.tags.isNotEmpty) {
        _tagsController.text = prefill.tags.join(', ');
      }
      if (prefill.notes.isNotEmpty) {
        _notesController.text = prefill.notes;
      }
      _expiry = prefill.expiryDate;
      _recordNumber = prefill.documentNumber;
    } else if (_localFilePath != null) {
      // Captured without OCR data — attach the file, leave fields for the user.
      _source = _DocSource.scan;
      _tempFileName = _localFilePath!.split(RegExp(r'[\\/]')).last;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _hasFile => _source != null;

  /// Opens the real device source for [source] and attaches the chosen file so
  /// it uploads to Storage on save.
  Future<void> _pickSource(_DocSource source) async {
    if (_capturing) return;
    HapticFeedback.selectionClick();

    if (source == _DocSource.pdf) {
      await _pickPdf();
      return;
    }

    setState(() => _capturing = true);
    try {
      String? path;
      if (source == _DocSource.scan &&
          DocumentScannerService.instance.isSupported) {
        // Ask for camera access first (shows the "Allow" prompt), then scan.
        final access = await CameraPermissionService.instance.requestCamera();
        if (access != CameraAccess.granted) {
          _handleDenied(access, 'camera');
          return;
        }
        path = await DocumentScannerService.instance.scan();
      } else {
        // Ask for photo access first (shows the "Allow" prompt), then open the
        // gallery.
        final access = await CameraPermissionService.instance.requestPhotos();
        if (access != CameraAccess.granted) {
          _handleDenied(access, 'photos');
          return;
        }
        path = await GalleryImportService.instance.pickImage();
      }

      if (path == null || !mounted) return; // user cancelled
      final captured = path;
      // Attach the file only — leave all detail fields blank for the user.
      setState(() {
        _source = source;
        _localFilePath = captured;
        _tempFileName = captured.split(RegExp(r'[\\/]')).last;
      });
    } catch (e) {
      if (!mounted) return;
      _toast(
          AppLocalizations.of(context)
              .t('couldNotOpenSource')
              .replaceAll('{source}', source.localizedTitle(context).toLowerCase())
              .replaceAll('{e}', '$e'),
          error: true);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Picks a PDF from device storage, validates it, and attaches it for upload.
  /// The name field is pre-filled from the PDF's file name (sans extension) so
  /// the user lands closer to Save.
  Future<void> _pickPdf() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final picked = await PdfImportService.instance.pickPdf();
      if (picked == null || !mounted) return; // cancelled
      setState(() {
        _source = _DocSource.pdf;
        _localFilePath = picked.path;
        _tempFileName = picked.name;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = _stripExtension(picked.name);
        }
      });
    } on PdfImportException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } catch (e) {
      if (mounted) {
        _toast(
            AppLocalizations.of(context)
                .t('couldNotImportPdf')
                .replaceAll('{e}', '$e'),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  String _stripExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  /// Shows the right message when the user declines a permission (and opens
  /// Settings if they've permanently blocked it).
  void _handleDenied(CameraAccess access, String what) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // [what] is a canonical key ('camera' / 'photos'); localize it for display.
    final whatLabel = l10n.t(what);
    if (access == CameraAccess.permanentlyDenied) {
      _toast(l10n.t('accessBlocked').replaceAll('{what}', whatLabel),
          error: true);
      CameraPermissionService.instance.openSettings();
    } else {
      _toast(l10n.t('pleaseAllowAccess').replaceAll('{what}', whatLabel),
          error: true);
    }
  }

  void _removeFile() {
    setState(() {
      _source = null;
      _tempFileName = null;
      _localFilePath = null;
    });
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: now,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_wallet == null) {
      _toast(AppLocalizations.of(context).t('pleaseChooseWallet'), error: true);
      return;
    }

    final name = _nameController.text.trim();
    final tags = _tagsController.text.trim().isEmpty
        ? <String>[]
        : _tagsController.text.trim().split(',').map((t) => t.trim()).toList();
    final notes = _notesController.text.trim();

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      // 1) Upload the actual file to Storage (if we have one), getting back its
      //    location to store on the row.
      String? filePath;
      if (_localFilePath != null) {
        filePath = await DocumentRepository.instance.uploadFile(_localFilePath!);
      }

      // 2) Persist to Supabase (the `documents` table). RLS ties the row to the
      //    signed-in user automatically.
      final doc = await DocumentRepository.instance.create(
        wallet: _wallet!,
        name: name,
        category: _category ?? 'Other',
        recordNumber: _recordNumber,
        tags: tags,
        notes: notes.isEmpty ? null : notes,
        expiresAt: _expiry,
        filePath: filePath,
      );

      // 2b) If the user asked to protect it, store the secure biometric flag
      //     for this document (by its real DB id).
      if (_protect) {
        await DocumentProtectionStore.instance.setProtected(doc.id, true);
      }

      if (!mounted) return;

      // 3) Keep the in-memory wallet list in sync so the detail screen shows the
      //    new document immediately (using the real id returned by the DB).
      WalletDetailRepository.instance.addRecord(
        _wallet!,
        DocumentRecord(
          id: doc.id,
          name: doc.name,
          category: doc.category ?? 'Other',
          icon: switch (_source) {
            _DocSource.image => Icons.image_rounded,
            _DocSource.pdf => Icons.picture_as_pdf_rounded,
            _ => Icons.description_rounded,
          },
          uploadedAt: doc.createdAt,
          updatedAt: doc.updatedAt,
          status: DocumentStatus.active,
          expiresAt: doc.expiresAt,
          tags: doc.tags,
          isFavorite: doc.isFavorite,
          filePath: doc.filePath,
        ),
      );

      // If the document has an expiry date, also create a reminder for it so it
      // shows up on the Reminders page (persisted to Supabase).
      if (_expiry != null) {
        ReminderStore.instance.add(
          Reminder(
            id: 'doc-${doc.id}',
            title: name,
            subtitle: '$_wallet · Expiry',
            category: _reminderCategoryForWallet(_wallet!),
            priority: ReminderPriority.important,
            date: _expiry!,
          ),
        );
      }

      _toast(AppLocalizations.of(context)
          .t('savedToWallet')
          .replaceAll('{name}', name)
          .replaceAll('{wallet}',
              localizedWalletName(AppLocalizations.of(context), _wallet!)));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Surface the real reason (bucket missing, RLS denial, not signed in, …)
      // instead of a generic message, so failures are diagnosable on-device.
      _toast(
          AppLocalizations.of(context)
              .t('saveFailedDetail')
              .replaceAll('{e}', '$e'),
          error: true);
      debugPrint('Document save failed: $e');
    }
  }

  /// Maps a wallet to the matching reminder category for auto-created expiry
  /// reminders.
  ReminderCategory _reminderCategoryForWallet(String wallet) {
    switch (wallet) {
      case 'Insurance Wallet':
        return ReminderCategory.insurance;
      case 'Health Wallet':
        return ReminderCategory.health;
      case 'Property Wallet':
        return ReminderCategory.property;
      case 'Investment Wallet':
        return ReminderCategory.investments;
      default:
        return ReminderCategory.documents;
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                    AppSpacing.screen, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _UploadOptions(
                      selected: _source,
                      busy: _capturing,
                      onPick: _pickSource,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (!_hasFile)
                      _EmptyState(busy: _capturing)
                    else ...[
                      _DetailsForm(
                        formKey: _formKey,
                        source: _source!,
                        fileName: _tempFileName ?? 'Document',
                        nameController: _nameController,
                        tagsController: _tagsController,
                        notesController: _notesController,
                        wallet: _wallet,
                        category: _category,
                        expiry: _expiry,
                        onRemoveFile: _removeFile,
                        onPickWallet: _chooseWallet,
                        onPickCategory: _chooseCategory,
                        onPickExpiry: _pickExpiry,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ProtectToggle(
                        value: _protect,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          setState(() => _protect = v);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _hasFile
          ? _SaveBar(
              onSave: _save,
              onCancel: () => Navigator.of(context).maybePop(),
              saving: _saving,
            )
          : null,
    );
  }

  Future<void> _chooseWallet() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _showPicker(
      title: l10n.t('selectWallet'),
      options: _wallets.map((w) => (w.$1, w.$2)).toList(),
      selected: _wallet,
      labelBuilder: (v) => localizedWalletName(l10n, v),
    );
    if (picked != null) setState(() => _wallet = picked);
  }

  Future<void> _chooseCategory() async {
    final store = CategoryStore.instance;
    final palette = AppPalette.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
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
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(AppLocalizations.of(context).t('selectCategory'),
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
                children: [
                  for (final c in store.all)
                    _PickerTile(
                      label: c.name,
                      icon: c.icon,
                      iconColor: c.color,
                      selected: c.name == _category,
                      onTap: () => Navigator.of(context).pop(c.name),
                    ),
                  Divider(color: palette.border, height: AppSpacing.md),
                  _PickerTile(
                    label: AppLocalizations.of(context).t('createNewCategory'),
                    icon: Icons.add_rounded,
                    selected: false,
                    onTap: () => Navigator.of(context).pop(_kCreateCategory),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == _kCreateCategory) {
      final created = await showCreateCategorySheet(context);
      if (created != null && mounted) setState(() => _category = created.name);
      return;
    }
    setState(() => _category = picked);
  }

  Future<String?> _showPicker({
    required String title,
    required List<(String, IconData)> options,
    required String? selected,
    String Function(String)? labelBuilder,
  }) {
    final palette = AppPalette.of(context);
    return showModalBottomSheet<String>(
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
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(title,
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
                children: [
                  for (final o in options)
                    _PickerTile(
                      label: labelBuilder != null ? labelBuilder(o.$1) : o.$1,
                      icon: o.$2,
                      selected: o.$1 == selected,
                      onTap: () => Navigator.of(context).pop(o.$1),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
          AppSpacing.screen, AppSpacing.lg),
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
                Text(AppLocalizations.of(context).t('addDocument'),
                    style: AppText.headline.copyWith(
                        color: palette.textPrimary, fontSize: 21)),
                const SizedBox(height: 2),
                Text(AppLocalizations.of(context).t('storeDocsSecurely'),
                    style:
                        AppText.caption.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upload options
// ---------------------------------------------------------------------------

class _UploadOptions extends StatelessWidget {
  const _UploadOptions({
    required this.selected,
    required this.busy,
    required this.onPick,
  });

  final _DocSource? selected;
  final bool busy;
  final void Function(_DocSource) onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _DocSource.values.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _OptionCard(
              source: _DocSource.values[i],
              selected: _DocSource.values[i] == selected,
              onTap: busy ? null : () => onPick(_DocSource.values[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final _DocSource source;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = source.color;
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md, horizontal: AppSpacing.xs),
      onTap: onTap,
      borderColor: selected ? color : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(source.icon, color: color, size: 24),
              ),
              if (selected)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.surface, width: 2),
                    ),
                    padding: const EdgeInsets.all(1),
                    child: const Icon(Icons.check_rounded,
                        size: 11, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            source.localizedTitle(context),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.subtitle.copyWith(
                color: palette.textPrimary, fontSize: 12.5),
          ),
          const SizedBox(height: 1),
          Text(
            source.localizedDescription(context),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(
                color: palette.textFaint, fontSize: 10.5, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.busy = false});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.large + 8),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.30),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )
                : const Icon(Icons.cloud_upload_rounded,
                    color: Colors.white, size: 50),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
              busy
                  ? AppLocalizations.of(context).t('opening')
                  : AppLocalizations.of(context).t('noDocumentSelected'),
              style:
                  AppText.title.copyWith(color: palette.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              AppLocalizations.of(context).t('chooseSourceHint'),
              textAlign: TextAlign.center,
              style: AppText.body
                  .copyWith(color: palette.textSecondary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Details form
// ---------------------------------------------------------------------------

class _DetailsForm extends StatelessWidget {
  const _DetailsForm({
    required this.formKey,
    required this.source,
    required this.fileName,
    required this.nameController,
    required this.tagsController,
    required this.notesController,
    required this.wallet,
    required this.category,
    required this.expiry,
    required this.onRemoveFile,
    required this.onPickWallet,
    required this.onPickCategory,
    required this.onPickExpiry,
  });

  final GlobalKey<FormState> formKey;
  final _DocSource source;
  final String fileName;
  final TextEditingController nameController;
  final TextEditingController tagsController;
  final TextEditingController notesController;
  final String? wallet;
  final String? category;
  final DateTime? expiry;
  final VoidCallback onRemoveFile;
  final VoidCallback onPickWallet;
  final VoidCallback onPickCategory;
  final VoidCallback onPickExpiry;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmt(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SelectedFile(source: source, fileName: fileName, onRemove: onRemoveFile),
          const SizedBox(height: AppSpacing.lg),
          _Field(
            label: l10n.t('documentName'),
            child: TextFormField(
              controller: nameController,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.t('enterDocumentName')
                  : null,
              decoration: _decoration(context, l10n.t('hintAddDocName')),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: l10n.t('wallet'),
            child: _Selector(
              value: wallet == null ? null : localizedWalletName(l10n, wallet!),
              placeholder: l10n.t('chooseWallet'),
              leading: Icons.account_balance_wallet_rounded,
              onTap: onPickWallet,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: l10n.t('category'),
            child: _Selector(
              value: category,
              placeholder: l10n.t('chooseCategory'),
              leading: Icons.label_rounded,
              onTap: onPickCategory,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: l10n.t('tags'),
            optional: true,
            child: TextFormField(
              controller: tagsController,
              textInputAction: TextInputAction.next,
              decoration: _decoration(context, l10n.t('hintAddTags')),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: l10n.t('expiryDate'),
            optional: true,
            child: _Selector(
              value: expiry == null ? null : _fmt(expiry!),
              placeholder: l10n.t('noExpiry'),
              leading: Icons.event_rounded,
              trailing: Icons.calendar_today_rounded,
              onTap: onPickExpiry,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: l10n.t('notes'),
            optional: true,
            child: TextFormField(
              controller: notesController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration(context, l10n.t('hintNotes')),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(BuildContext context, String hint) {
    final palette = AppPalette.of(context);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body.copyWith(color: palette.textFaint),
      filled: true,
      fillColor: palette.surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 14),
      border: border(palette.border),
      enabledBorder: border(palette.border),
      focusedBorder: border(AppColors.primaryGreen, 1.6),
      errorBorder: border(AppColors.critical),
      focusedErrorBorder: border(AppColors.critical, 1.6),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    this.optional = false,
  });

  final String label;
  final Widget child;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: AppText.subtitle.copyWith(
                    color: palette.textPrimary, fontSize: 13)),
            if (optional) ...[
              const SizedBox(width: 6),
              Text(AppLocalizations.of(context).t('optional'),
                  style: AppText.label.copyWith(
                      color: palette.textFaint, fontSize: 11)),
            ],
          ],
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

class _Selector extends StatelessWidget {
  const _Selector({
    required this.value,
    required this.placeholder,
    required this.leading,
    required this.onTap,
    this.trailing = Icons.keyboard_arrow_down_rounded,
  });

  final String? value;
  final String placeholder;
  final IconData leading;
  final IconData trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasValue = value != null;
    return PressableScale(
      pressedScale: 0.98,
      child: Material(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(leading, size: 19, color: AppColors.primaryGreen),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    hasValue ? value! : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      color: hasValue ? palette.textPrimary : palette.textFaint,
                    ),
                  ),
                ),
                Icon(trailing, size: 20, color: palette.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedFile extends StatelessWidget {
  const _SelectedFile({
    required this.source,
    required this.fileName,
    required this.onRemove,
  });

  final _DocSource source;
  final String fileName;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = source.color;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.iconContainerSm,
            height: AppSizes.iconContainerSm,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(source.fileIcon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(
                        color: palette.textPrimary, fontSize: 13.5)),
                const SizedBox(height: 1),
                Text(AppLocalizations.of(context).t('readyToSave'),
                    style: AppText.caption
                        .copyWith(color: AppColors.primaryGreen)),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, color: palette.textFaint, size: 20),
            tooltip: AppLocalizations.of(context).t('remove'),
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.iconColor,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tint = iconColor ?? AppColors.primaryGreen;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(icon, color: tint, size: 21),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(label,
                    style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600)),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primaryGreen, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Biometric protection toggle
// ---------------------------------------------------------------------------

class _ProtectToggle extends StatelessWidget {
  const _ProtectToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = value ? AppColors.primaryGreen : palette.textSecondary;
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      borderColor: value ? AppColors.primaryGreen : null,
      child: Row(
        children: [
          Container(
            width: AppSizes.iconContainerSm,
            height: AppSizes.iconContainerSm,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(Icons.lock_rounded, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).t('protectWithBiometrics'),
                  style: AppText.subtitle
                      .copyWith(color: palette.textPrimary, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).t('protectBiometricsSubtitle'),
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primaryGreen,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Save bar
// ---------------------------------------------------------------------------

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.onSave,
    required this.onCancel,
    this.saving = false,
  });

  final VoidCallback onSave;
  final VoidCallback onCancel;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
              AppSpacing.screen, AppSpacing.sm),
          child: Row(
        children: [
          PressableScale(
            child: Material(
              color: palette.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
                side: BorderSide(color: palette.border),
              ),
              child: InkWell(
                onTap: saving ? null : onCancel,
                child: SizedBox(
                  height: AppSizes.button,
                  width: 104,
                  child: Center(
                    child: Text(AppLocalizations.of(context).t('cancel'),
                        style: AppText.subtitle
                            .copyWith(color: palette.textSecondary)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: PressableScale(
              child: Container(
                height: AppSizes.button,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.32),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: saving ? null : onSave,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    child: Center(
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(AppLocalizations.of(context).t('saveDocument'),
                                    style: AppText.subtitle.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }
}
