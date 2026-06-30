import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/wallet_detail_repository.dart';
import '../../models/wallet_detail_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';

/// The source a user picks to add a document.
enum _DocSource { scan, pdf, image }

extension _DocSourceX on _DocSource {
  String get title {
    switch (this) {
      case _DocSource.scan:
        return 'Scan Document';
      case _DocSource.pdf:
        return 'Upload PDF';
      case _DocSource.image:
        return 'Upload Image';
    }
  }

  String get description {
    switch (this) {
      case _DocSource.scan:
        return 'Scan using camera';
      case _DocSource.pdf:
        return 'Choose PDF file';
      case _DocSource.image:
        return 'Select image';
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

  String get mockFileName {
    switch (this) {
      case _DocSource.scan:
        return 'Scan_20260701.pdf';
      case _DocSource.pdf:
        return 'Document.pdf';
      case _DocSource.image:
        return 'IMG_0042.jpg';
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

const _categories = <String>[
  'Identity',
  'Financial',
  'Legal',
  'Medical',
  'Property',
  'Personal',
  'Other',
];

/// Add Document — the fastest path to get a document into the vault.
///
/// Pick a source (scan / PDF / image), then fill a short set of details and
/// save. Deliberately minimal: no analytics, dashboards or extra sections.
class AddDocumentScreen extends StatefulWidget {
  const AddDocumentScreen({super.key, this.initialWallet});

  /// Pre-selects a wallet when opened from a specific wallet's detail screen.
  final String? initialWallet;

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

  // Scanner/File Picker states
  bool _showScanner = false;
  bool _showFilePicker = false;
  _DocSource? _pickerType;
  bool _isProcessing = false;
  String _processingMessage = '';
  double _processingProgress = 0.0;
  String? _tempFileName;

  @override
  void initState() {
    super.initState();
    _wallet = widget.initialWallet;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _hasFile => _source != null;

  void _pickSource(_DocSource source) {
    HapticFeedback.selectionClick();
    if (source == _DocSource.scan) {
      setState(() {
        _showScanner = true;
      });
    } else {
      setState(() {
        _showFilePicker = true;
        _pickerType = source;
      });
    }
  }

  void _removeFile() {
    setState(() {
      _source = null;
      _tempFileName = null;
    });
  }

  Future<void> _pickExpiry() async {
    final now = DateTime(2026, 7, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: now,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_wallet == null) {
      _toast('Please choose a wallet', error: true);
      return;
    }

    final record = DocumentRecord(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      category: _category ?? 'Other',
      icon: _source == _DocSource.image ? Icons.image_rounded : Icons.description_rounded,
      uploadedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      status: DocumentStatus.active,
      expiresAt: _expiry,
      tags: _tagsController.text.trim().isEmpty
          ? const []
          : _tagsController.text.trim().split(',').map((t) => t.trim()).toList(),
      isFavorite: false,
    );

    WalletDetailRepository.instance.addRecord(_wallet!, record);

    FocusScope.of(context).unfocus();
    _toast('“${_nameController.text.trim()}” saved to $_wallet');
    Navigator.of(context).maybePop();
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

  void _startScanningSimulation() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isProcessing = true;
      _processingProgress = 0.1;
      _processingMessage = 'Detecting document edges...';
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _processingProgress = 0.4;
        _processingMessage = 'Enhancing contrast and text...';
      });
    });

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _processingProgress = 0.8;
        _processingMessage = 'Saving as secure PDF...';
      });
    });

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _showScanner = false;
        _source = _DocSource.scan;
        _tempFileName = 'Scan_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}.pdf';
        _nameController.text = 'Aadhaar Card Scan';
        _category = 'Identity';
        _wallet = 'Identity Wallet';
      });
      _toast('Scan completed successfully!');
    });
  }

  void _startUploadingSimulation(String fileName) {
    HapticFeedback.selectionClick();
    setState(() {
      _isProcessing = true;
      _processingProgress = 0.1;
      _processingMessage = 'Connecting to secure server...';
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _processingProgress = 0.5;
        _processingMessage = 'Uploading files (50%)...';
      });
    });

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        _processingProgress = 0.8;
        _processingMessage = 'Encrypting document in vault...';
      });
    });

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _showFilePicker = false;
        _source = _pickerType;
        _tempFileName = fileName;

        // Clean display name
        String displayName = fileName
            .replaceAll('.pdf', '')
            .replaceAll('.png', '')
            .replaceAll('.jpg', '')
            .replaceAll('_', ' ');
        displayName = displayName.split(' ').map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1);
        }).join(' ');

        _nameController.text = displayName;

        // Smart pre-select category and wallet
        if (fileName.contains('insurance')) {
          _category = 'Financial';
          _wallet = 'Insurance Wallet';
        } else if (fileName.contains('rent') || fileName.contains('property')) {
          _category = 'Property';
          _wallet = 'Property Wallet';
        } else if (fileName.contains('pan') ||
            fileName.contains('passport') ||
            fileName.contains('dl') ||
            fileName.contains('voter')) {
          _category = 'Identity';
          _wallet = 'Identity Wallet';
        } else if (fileName.contains('health') ||
            fileName.contains('prescription')) {
          _category = 'Medical';
          _wallet = 'Health Wallet';
        } else {
          _category = 'Other';
          _wallet = 'Document Wallet';
        }
      });
      _toast('File uploaded successfully!');
    });
  }

  Widget _buildProcessingOverlay() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _processingMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _processingProgress,
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primaryGreen),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulatedScanner() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isProcessing
            ? _buildProcessingOverlay()
            : Column(
                children: [
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 28),
                          onPressed: () => setState(() => _showScanner = false),
                        ),
                        const Spacer(),
                        const Text(
                          'DOCUMENT SCANNER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 48), // balance
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Framing viewport
                  Container(
                    width: 290,
                    height: 420,
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: AppColors.primaryGreen, width: 2.5),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryGreen.withValues(alpha: 0.15),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Viewfinder content guide
                        Text(
                          'Place Document Inside Frame',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Bottom controls
                  Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Column(
                      children: [
                        const Text(
                          'Hold steady. Edge detection active.',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 24),
                        GestureDetector(
                          key: const Key('shutter_button'),
                          onTap: _startScanningSimulation,
                          child: Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            padding: const EdgeInsets.all(5),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSimulatedFilePicker() {
    final isPdf = _pickerType == _DocSource.pdf;
    final palette = AppPalette.of(context);

    // Sample files
    final pdfFiles = [
      ('salary_slip_june.pdf', '142 KB', 'Jun 28, 2026'),
      ('rent_agreement_final.pdf', '890 KB', 'May 12, 2026'),
      ('health_insurance_policy.pdf', '2.4 MB', 'Apr 15, 2026'),
      ('pan_card_copy.pdf', '98 KB', 'Jan 10, 2025'),
    ];

    final imageFiles = [
      ('IMG_passport_front.jpg', '1.8 MB', 'Today, 10:14 AM'),
      ('IMG_dl_copy.png', '920 KB', 'Yesterday'),
      ('prescription_rx_2026.jpg', '450 KB', 'Jun 14, 2026'),
      ('voter_id_scan.png', '720 KB', 'Mar 08, 2025'),
    ];

    final files = isPdf ? pdfFiles : imageFiles;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: _isProcessing
            ? _buildProcessingOverlay()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_rounded,
                              color: palette.textPrimary),
                          onPressed: () =>
                              setState(() => _showFilePicker = false),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isPdf ? 'Select PDF Document' : 'Select Image',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'RECENT FILES',
                      style: TextStyle(
                        color: palette.textFaint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: files.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: palette.border, height: 1),
                      itemBuilder: (context, idx) {
                        final file = files[idx];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 8),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: (isPdf
                                      ? AppColors.lightBlue
                                      : AppColors.secondaryGreen)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isPdf
                                  ? Icons.picture_as_pdf_rounded
                                  : Icons.image_rounded,
                              color: isPdf
                                  ? AppColors.lightBlue
                                  : AppColors.secondaryGreen,
                            ),
                          ),
                          title: Text(
                            file.$1,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${file.$2} · ${file.$3}',
                            style: TextStyle(
                              color: palette.textFaint,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => _startUploadingSimulation(file.$1),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    if (_showScanner) {
      return _buildSimulatedScanner();
    }

    if (_showFilePicker) {
      return _buildSimulatedFilePicker();
    }

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
                    _UploadOptions(selected: _source, onPick: _pickSource),
                    const SizedBox(height: AppSpacing.lg),
                    if (!_hasFile)
                      const _EmptyState()
                    else
                      _DetailsForm(
                        formKey: _formKey,
                        source: _source!,
                        fileName: _tempFileName ?? _source!.mockFileName,
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
            )
          : null,
    );
  }

  Future<void> _chooseWallet() async {
    final picked = await _showPicker(
      title: 'Select Wallet',
      options: _wallets.map((w) => (w.$1, w.$2)).toList(),
      selected: _wallet,
    );
    if (picked != null) setState(() => _wallet = picked);
  }

  Future<void> _chooseCategory() async {
    final picked = await _showPicker(
      title: 'Select Category',
      options: _categories.map((c) => (c, Icons.label_rounded)).toList(),
      selected: _category,
    );
    if (picked != null) setState(() => _category = picked);
  }

  Future<String?> _showPicker({
    required String title,
    required List<(String, IconData)> options,
    required String? selected,
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
                      label: o.$1,
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
                Text('Add Document',
                    style: AppText.headline.copyWith(
                        color: palette.textPrimary, fontSize: 21)),
                const SizedBox(height: 2),
                Text('Store your documents securely',
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
  const _UploadOptions({required this.selected, required this.onPick});

  final _DocSource? selected;
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
              onTap: () => onPick(_DocSource.values[i]),
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
  final VoidCallback onTap;

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
            source.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.subtitle.copyWith(
                color: palette.textPrimary, fontSize: 12.5),
          ),
          const SizedBox(height: 1),
          Text(
            source.description,
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
  const _EmptyState();

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
            child: const Icon(Icons.cloud_upload_rounded,
                color: Colors.white, size: 50),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('No document selected',
              style:
                  AppText.title.copyWith(color: palette.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              'Choose a document source above to get started.',
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
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SelectedFile(source: source, fileName: fileName, onRemove: onRemoveFile),
          const SizedBox(height: AppSpacing.lg),
          _Field(
            label: 'Document Name',
            child: TextFormField(
              controller: nameController,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a document name' : null,
              decoration: _decoration(context, 'e.g. Aadhaar Card'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: 'Wallet',
            child: _Selector(
              value: wallet,
              placeholder: 'Choose a wallet',
              leading: Icons.account_balance_wallet_rounded,
              onTap: onPickWallet,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: 'Category',
            child: _Selector(
              value: category,
              placeholder: 'Choose a category',
              leading: Icons.label_rounded,
              onTap: onPickCategory,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: 'Tags',
            optional: true,
            child: TextFormField(
              controller: tagsController,
              textInputAction: TextInputAction.next,
              decoration: _decoration(context, 'e.g. tax, 2026'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: 'Expiry Date',
            optional: true,
            child: _Selector(
              value: expiry == null ? null : _fmt(expiry!),
              placeholder: 'No expiry',
              leading: Icons.event_rounded,
              trailing: Icons.calendar_today_rounded,
              onTap: onPickExpiry,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: 'Notes',
            optional: true,
            child: TextFormField(
              controller: notesController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration(context, 'Add a note (optional)'),
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
              Text('Optional',
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
                Text('Ready to save',
                    style: AppText.caption
                        .copyWith(color: AppColors.primaryGreen)),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, color: palette.textFaint, size: 20),
            tooltip: 'Remove',
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
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
                  color: AppColors.primaryGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(icon, color: AppColors.primaryGreen, size: 21),
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
// Save bar
// ---------------------------------------------------------------------------

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.onSave, required this.onCancel});

  final VoidCallback onSave;
  final VoidCallback onCancel;

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
                onTap: onCancel,
                child: SizedBox(
                  height: AppSizes.button,
                  width: 104,
                  child: Center(
                    child: Text('Cancel',
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
                    onTap: onSave,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text('Save Document',
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
