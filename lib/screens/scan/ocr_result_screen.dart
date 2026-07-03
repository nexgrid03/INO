import 'package:flutter/material.dart';

import '../../models/scan_models.dart';
import '../../services/category_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/documents/create_category_sheet.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/scan/detection_badge.dart';
import '../../widgets/scan/ocr_field_tile.dart';

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

/// Label used for the "create a new category" entry in the category picker.
const String _kCreateCategory = 'Create new category';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Screen 4 — review & confirm the extracted information.
///
/// Auto-detection badge on top, then clean editable cards for every field. The
/// user corrects anything OCR got wrong, then Continues to save (or retakes).
class OcrResultScreen extends StatefulWidget {
  const OcrResultScreen({
    super.key,
    required this.result,
    required this.onRetake,
    required this.onContinue,
    required this.onClose,
  });

  final OcrResult result;
  final VoidCallback onRetake;
  final ValueChanged<OcrResult> onContinue;
  final VoidCallback onClose;

  @override
  State<OcrResultScreen> createState() => _OcrResultScreenState();
}

class _OcrResultScreenState extends State<OcrResultScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _number;
  late final TextEditingController _tags;
  late final TextEditingController _notes;

  // Structured identity fields extracted from ID documents.
  late final TextEditingController _fullName;
  late final TextEditingController _dob;
  late final TextEditingController _gender;
  late final TextEditingController _fatherName;

  late String _wallet;
  late String _category;
  DateTime? _issueDate;
  DateTime? _expiryDate;

  /// Show the identity card for ID documents (has extracted fields, or is filed
  /// under the Identity wallet).
  bool get _showIdentity =>
      widget.result.category == 'Identity' ||
      widget.result.fullName != null ||
      widget.result.dob != null ||
      widget.result.gender != null ||
      widget.result.fatherName != null;

  @override
  void initState() {
    super.initState();
    final r = widget.result;
    _name = TextEditingController(text: r.documentName);
    _number = TextEditingController(text: r.documentNumber ?? '');
    _tags = TextEditingController(text: r.tags.join(', '));
    _notes = TextEditingController(text: r.notes);
    _fullName = TextEditingController(text: r.fullName ?? '');
    _dob = TextEditingController(text: r.dob ?? '');
    _gender = TextEditingController(text: r.gender ?? '');
    _fatherName = TextEditingController(text: r.fatherName ?? '');
    _wallet = r.suggestedWallet;
    _category = r.category;
    _issueDate = r.issueDate;
    _expiryDate = r.expiryDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _tags.dispose();
    _notes.dispose();
    _fullName.dispose();
    _dob.dispose();
    _gender.dispose();
    _fatherName.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool issue}) async {
    final base = DateTime(2026, 7, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: (issue ? _issueDate : _expiryDate) ?? base,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => issue ? _issueDate = picked : _expiryDate = picked);
    }
  }

  Future<void> _pickWallet() async {
    final picked = await _showOptions(
      title: 'Select Wallet',
      options: _wallets,
      selected: _wallet,
    );
    if (picked != null) setState(() => _wallet = picked);
  }

  Future<void> _pickCategory() async {
    final store = CategoryStore.instance;
    final picked = await _showOptions(
      title: 'Select Category',
      options: [
        for (final c in store.all) (c.name, c.icon),
        (_kCreateCategory, Icons.add_rounded),
      ],
      selected: _category,
    );
    if (picked == null || !mounted) return;
    if (picked == _kCreateCategory) {
      final created = await showCreateCategorySheet(context);
      if (created != null && mounted) setState(() => _category = created.name);
      return;
    }
    setState(() => _category = picked);
  }

  /// Combines the (edited) identity fields with any free-text notes, so the
  /// structured data persists to the saved document.
  String _composeNotes() {
    final parts = <String>[];
    void add(String label, String value) {
      if (value.trim().isNotEmpty) parts.add('$label: ${value.trim()}');
    }

    if (_showIdentity) {
      add('Name', _fullName.text);
      add('DOB', _dob.text);
      add('Gender', _gender.text);
      add("Father's Name", _fatherName.text);
    }
    final identity = parts.join('\n');
    final userNotes = _notes.text.trim();
    if (identity.isEmpty) return userNotes;
    if (userNotes.isEmpty) return identity;
    return '$identity\n\n$userNotes';
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final updated = widget.result.copyWith(
      documentName: _name.text.trim(),
      documentNumber: _number.text.trim(),
      issueDate: _issueDate,
      expiryDate: _expiryDate,
      category: _category,
      suggestedWallet: _wallet,
      tags: _tags.text.trim().isEmpty
          ? const []
          : _tags.text.trim().split(',').map((t) => t.trim()).toList(),
      notes: _composeNotes(),
      fullName: _fullName.text.trim(),
      dob: _dob.text.trim(),
      gender: _gender.text.trim(),
      fatherName: _fatherName.text.trim(),
    );
    widget.onContinue(updated);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final r = widget.result;
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: widget.onClose),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                      AppSpacing.screen, AppSpacing.lg),
                  children: [
                    DetectionBadge(
                      detectedType: r.detectedType,
                      suggestedWallet: _wallet,
                      confidence: r.confidence,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Identity fields (ID documents) — extracted, editable.
                    if (_showIdentity) ...[
                      _CardSection(
                        title: 'Extracted Details',
                        children: [
                          OcrField(
                            label: 'Full Name',
                            optional: true,
                            child: OcrTextField(
                              controller: _fullName,
                              hint: 'e.g. Rahul Kumar',
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          OcrField(
                            label: 'Date of Birth',
                            optional: true,
                            child: OcrTextField(
                              controller: _dob,
                              hint: 'e.g. 01-01-1998',
                            ),
                          ),
                          OcrField(
                            label: 'Gender',
                            optional: true,
                            child: OcrTextField(
                              controller: _gender,
                              hint: 'e.g. Male',
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          if (r.detectedType.toLowerCase().contains('pan') ||
                              _fatherName.text.isNotEmpty)
                            OcrField(
                              label: "Father's Name",
                              optional: true,
                              child: OcrTextField(
                                controller: _fatherName,
                                hint: "e.g. Suresh Kumar",
                                textCapitalization: TextCapitalization.words,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    // Document details card.
                    _CardSection(
                      title: 'Document',
                      children: [
                        OcrField(
                          label: 'Document Name',
                          child: OcrTextField(
                            controller: _name,
                            hint: 'e.g. PAN Card',
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter a document name'
                                : null,
                          ),
                        ),
                        OcrField(
                          label: 'Document Number',
                          optional: true,
                          child: OcrTextField(
                            controller: _number,
                            hint: 'e.g. ABCDE1234F',
                            textCapitalization: TextCapitalization.characters,
                          ),
                        ),
                        OcrField(
                          label: 'Issue Date',
                          optional: true,
                          child: OcrSelector(
                            value:
                                _issueDate == null ? null : _fmtDate(_issueDate!),
                            placeholder: 'Not detected',
                            leading: Icons.event_available_rounded,
                            trailing: Icons.calendar_today_rounded,
                            onTap: () => _pickDate(issue: true),
                          ),
                        ),
                        OcrField(
                          label: 'Expiry Date',
                          optional: true,
                          child: OcrSelector(
                            value: _expiryDate == null
                                ? null
                                : _fmtDate(_expiryDate!),
                            placeholder: 'No expiry',
                            leading: Icons.event_busy_rounded,
                            trailing: Icons.calendar_today_rounded,
                            onTap: () => _pickDate(issue: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Filing card.
                    _CardSection(
                      title: 'Filing',
                      children: [
                        OcrField(
                          label: 'Category',
                          child: OcrSelector(
                            value: _category,
                            placeholder: 'Choose a category',
                            leading: Icons.label_rounded,
                            onTap: _pickCategory,
                          ),
                        ),
                        OcrField(
                          label: 'Wallet',
                          child: OcrSelector(
                            value: _wallet,
                            placeholder: 'Choose a wallet',
                            leading: Icons.account_balance_wallet_rounded,
                            onTap: _pickWallet,
                          ),
                        ),
                        OcrField(
                          label: 'Tags',
                          optional: true,
                          child: OcrTextField(
                            controller: _tags,
                            hint: 'e.g. govt, tax',
                            textCapitalization: TextCapitalization.none,
                          ),
                        ),
                        OcrField(
                          label: 'Notes',
                          optional: true,
                          child: OcrTextField(
                            controller: _notes,
                            hint: 'Add a note (optional)',
                            maxLines: 3,
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _ActionBar(onContinue: _continue, onRetake: widget.onRetake),
          ],
        ),
      ),
    );
  }

  Future<String?> _showOptions({
    required String title,
    required List<(String, IconData)> options,
    required String? selected,
  }) {
    final palette = AppPalette.of(context);
    return showModalBottomSheet<String>(
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
            Text(title,
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs,
                    AppSpacing.md, AppSpacing.md),
                children: [
                  for (final o in options)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        onTap: () => Navigator.of(context).pop(o.$1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
                          child: Row(
                            children: [
                              Container(
                                width: AppSizes.iconContainerSm,
                                height: AppSizes.iconContainerSm,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen
                                      .withValues(alpha: 0.10),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.chip),
                                ),
                                child: Icon(o.$2,
                                    color: AppColors.primaryGreen, size: 21),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(o.$1,
                                    style: AppText.subtitle.copyWith(
                                        color: palette.textPrimary,
                                        fontWeight: o.$1 == selected
                                            ? FontWeight.w700
                                            : FontWeight.w600)),
                              ),
                              if (o.$1 == selected)
                                const Icon(Icons.check_circle_rounded,
                                    color: AppColors.primaryGreen, size: 22),
                            ],
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
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
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
                Text('Confirm Details',
                    style: AppText.headline
                        .copyWith(color: palette.textPrimary, fontSize: 21)),
                const SizedBox(height: 2),
                Text('Review what INO extracted, then continue',
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

class _CardSection extends StatelessWidget {
  const _CardSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.internal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: AppText.label.copyWith(
                  color: palette.textFaint, letterSpacing: 1.0)),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onContinue, required this.onRetake});

  final VoidCallback onContinue;
  final VoidCallback onRetake;

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
                    onTap: onRetake,
                    child: SizedBox(
                      height: AppSizes.button,
                      width: 104,
                      child: Center(
                        child: Text('Retake',
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
                        onTap: onContinue,
                        borderRadius: BorderRadius.circular(AppRadius.button),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Continue',
                                  style: AppText.subtitle.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded,
                                  color: Colors.white, size: 20),
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
