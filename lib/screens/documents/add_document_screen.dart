import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  ('Bank Wallet', Icons.account_balance_rounded),
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
    setState(() {
      _source = source;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = source == _DocSource.image
            ? 'New Image'
            : 'New Document';
      }
    });
  }

  void _removeFile() {
    setState(() => _source = null);
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
                    _UploadOptions(selected: _source, onPick: _pickSource),
                    const SizedBox(height: AppSpacing.lg),
                    if (!_hasFile)
                      const _EmptyState()
                    else
                      _DetailsForm(
                        formKey: _formKey,
                        source: _source!,
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
          _SelectedFile(source: source, onRemove: onRemoveFile),
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
  const _SelectedFile({required this.source, required this.onRemove});

  final _DocSource source;
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
                Text(source.mockFileName,
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
