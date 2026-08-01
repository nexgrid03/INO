import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/expense_models.dart';
import '../../services/camera_permission_service.dart';
import '../../services/expense_store.dart';
import '../../services/gallery_import_service.dart';
import '../../services/pdf_import_service.dart';
import '../../services/receipt_scan_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/expenses/direction_toggle.dart';
import '../../widgets/pressable_scale.dart';

/// Add / edit an ITR-ready transaction. Attaching a photo receipt runs OCR and
/// pre-fills amount / date / vendor automatically.
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key, this.existing});

  final TransactionRecord? existing;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _store = ExpenseStore.instance;
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _gst = TextEditingController();
  final _vendor = TextEditingController();
  final _note = TextEditingController();

  TransactionType _type = TransactionType.expense;
  TxnCategory _category = TxnCategory.other;
  PaymentMethod? _payment;
  late DateTime _date;
  String? _receiptPath;
  bool _receiptIsPdf = false;
  bool _busy = false;
  bool _scanning = false;

  /// Money direction (Feature 2). Defaults from [_type]; auto-set from a scanned
  /// receipt when detected; always user-overridable via the [DirectionToggle].
  late TransactionDirection _direction;

  /// True right after OCR auto-set the direction, so the toggle pulses once to
  /// flag the change. Cleared as soon as the user touches anything.
  bool _directionAutoSet = false;

  /// The set of fields the last receipt scan filled (labels for the "Auto-filled
  /// from receipt ✓" note) - empty when there's no live extraction.
  final Set<String> _autoFilled = {};

  /// A snapshot of the fields OCR may touch, taken just before auto-fill, so
  /// "Clear" can discard the extraction and restore what the user had.
  Map<String, String>? _preScanSnapshot;
  DateTime? _preScanDate;

  /// True when the last scan couldn't confidently read the amount and the field
  /// is empty - the amount field shows a "enter manually" hint (FIX 4). Filling
  /// nothing beats filling a wrong value.
  bool _amountUnread = false;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e?.dateTime ?? DateTime.now();
    if (e != null) {
      _description.text = e.description;
      _amount.text = _fmt(e.amount);
      _reference.text = e.reference ?? '';
      _gst.text = e.gstAmount == null ? '' : _fmt(e.gstAmount!);
      _vendor.text = e.vendorName ?? '';
      _note.text = e.note ?? '';
      _type = e.type;
      _category = e.category;
      _payment = e.paymentMethod;
      _receiptPath = e.receiptPath;
      _receiptIsPdf = e.receiptIsPdf;
      _direction = e.effectiveDirection; // preserve an edited record's direction
    } else {
      _direction = TransactionDirectionX.defaultFor(_type);
    }
    // Once the user types an amount, the "couldn't read amount" hint clears.
    _amount.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    if (_amountUnread && _amount.text.trim().isNotEmpty) {
      setState(() => _amountUnread = false);
    }
  }

  /// Switching Expense/Income re-defaults the direction from context. A manual
  /// direction tap afterwards still wins (until the type changes again).
  void _onTypeChanged(TransactionType type) {
    setState(() {
      _type = type;
      _direction = TransactionDirectionX.defaultFor(type);
      _directionAutoSet = false;
    });
  }

  void _onDirectionChanged(TransactionDirection d) {
    setState(() {
      _direction = d;
      _directionAutoSet = false; // user override → stop the highlight
    });
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _amount.removeListener(_onAmountChanged);
    _description.dispose();
    _amount.dispose();
    _reference.dispose();
    _gst.dispose();
    _vendor.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_amount.text.trim()) ?? 0;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() =>
          _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
    }
  }

  Future<void> _attach() async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
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
            ListTile(
              leading:
                  const Icon(Icons.photo_camera_rounded, color: AppColors.primaryGreen),
              title: Text(l10n.t('camera')),
              subtitle: Text(l10n.t('snapReceiptSubtitle')),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.image_rounded, color: AppColors.primaryGreen),
              title: Text(l10n.t('gallery')),
              subtitle: Text(l10n.t('pickPhotoSubtitle')),
              onTap: () => Navigator.of(context).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded,
                  color: AppColors.lightBlue),
              title: Text(l10n.t('pdfReceipt')),
              onTap: () => Navigator.of(context).pop('pdf'),
            ),
            if (_receiptPath != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_rounded, color: AppColors.critical),
                title: Text(l10n.t('removeAttachment')),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      setState(() {
        _receiptPath = null;
        _receiptIsPdf = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      if (choice == 'camera') {
        final access = await CameraPermissionService.instance.requestCamera();
        if (access != CameraAccess.granted) {
          _toast(
              l10n.t(access == CameraAccess.permanentlyDenied
                  ? 'cameraAccessBlockedReceipt'
                  : 'cameraAccessNeededReceipt'),
              error: true);
          if (access == CameraAccess.permanentlyDenied) {
            await CameraPermissionService.instance.openSettings();
          }
          return;
        }
        final path = await GalleryImportService.instance.captureFromCamera();
        if (path != null && mounted) {
          setState(() {
            _receiptPath = path;
            _receiptIsPdf = false;
          });
          await _runOcr(path);
        }
      } else if (choice == 'image') {
        final access = await CameraPermissionService.instance.requestPhotos();
        if (access != CameraAccess.granted) {
          _toast(
              l10n.t(access == CameraAccess.permanentlyDenied
                  ? 'photoAccessBlocked'
                  : 'photoAccessNeeded'),
              error: true);
          if (access == CameraAccess.permanentlyDenied) {
            await CameraPermissionService.instance.openSettings();
          }
          return;
        }
        final path = await GalleryImportService.instance.pickImage();
        if (path != null && mounted) {
          setState(() {
            _receiptPath = path;
            _receiptIsPdf = false;
          });
          await _runOcr(path);
        }
      } else if (choice == 'pdf') {
        final picked = await PdfImportService.instance.pickPdf();
        if (picked != null && mounted) {
          setState(() {
            _receiptPath = picked.path;
            _receiptIsPdf = true;
          });
        }
      }
    } on PdfImportException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } catch (_) {
      if (mounted) _toast(l10n.t('couldNotAttachReceipt'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs OCR on the receipt image and auto-fills the matching form fields.
  ///
  /// Fields that are already empty are filled directly; if the scan found values
  /// for fields the user has ALREADY typed into, we ask "Replace existing
  /// values?" first. Every filled field stays editable, and a snapshot is kept
  /// so "Clear" can discard the extraction. OCR failure is non-fatal - the form
  /// stays fully usable.
  Future<void> _runOcr(String path) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _scanning = true);
    try {
      final data = await ReceiptScanService.instance.scan(path);
      if (!mounted || data.isEmpty) {
        if (mounted) {
          _toast(l10n.t('couldntReadReceipt'), error: true);
        }
        return;
      }

      // The Transaction ID field is fed by the parsed reference code first,
      // then a GSTIN as a weak fallback - never by a numeric amount.
      final referenceValue = data.transactionId ?? data.gstNumber;

      // What can the scan offer, and does any of it collide with typed values?
      final hasConflict = (data.amount != null && _amount.text.trim().isNotEmpty) ||
          (data.vendorName != null && _vendor.text.trim().isNotEmpty) ||
          (referenceValue != null && _reference.text.trim().isNotEmpty);

      var replaceExisting = false;
      if (hasConflict) {
        replaceExisting = await _askReplaceExisting() ?? false;
      }

      // Snapshot the touchable fields BEFORE filling, so Clear can restore them.
      _preScanSnapshot = {
        'amount': _amount.text,
        'vendor': _vendor.text,
        'reference': _reference.text,
      };
      _preScanDate = _date;

      final filled = <String>{};
      void fill(String key, TextEditingController c, String value) {
        if (c.text.trim().isEmpty || replaceExisting) {
          c.text = value;
          filled.add(key);
        }
      }

      // Amount is only ever filled from a VALIDATED value (parseAmount); an ID
      // can never reach it. If none was read and the field is still empty, show
      // the "enter manually" hint instead of guessing a wrong number.
      if (data.amount != null) {
        fill('Amount', _amount, _fmt(data.amount!));
      }
      final amountUnread = data.amount == null && _amount.text.trim().isEmpty;

      // Transaction ID lands in its OWN field, verbatim as a string.
      if (referenceValue != null) {
        fill('Transaction ID', _reference, referenceValue);
      }
      if (data.vendorName != null) fill('Vendor', _vendor, data.vendorName!);
      if (data.date != null) {
        _date = DateTime(data.date!.year, data.date!.month, data.date!.day,
            _date.hour, _date.minute);
        filled.add('Date');
      }

      // Direction from the receipt (e.g. a bank/UPI screenshot) - set it and
      // pulse the toggle so the user notices it was auto-chosen.
      if (data.direction != null && data.direction != _direction) {
        _direction = data.direction!;
        _directionAutoSet = true;
        filled.add('Direction');
      }

      setState(() {
        _amountUnread = amountUnread;
        _autoFilled
          ..clear()
          ..addAll(filled);
      });
      if (amountUnread) {
        _toast(l10n.t('couldntReadAmount'), error: true);
      } else if (filled.isEmpty) {
        _toast(l10n.t('nothingNewFromReceipt'));
      }
    } catch (_) {
      // OCR / network failure → keep the form usable.
      if (mounted) {
        _toast(l10n.t('couldntReadReceipt'), error: true);
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<bool?> _askReplaceExisting() {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(l10n.t('replaceExistingTitle')),
        content: Text(
          l10n.t('replaceExistingBody'),
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('keepMine')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('replace'),
                style: const TextStyle(color: AppColors.primaryGreen)),
          ),
        ],
      ),
    );
  }

  /// Discards the last receipt extraction: restores the fields OCR touched to
  /// their pre-scan values and clears the "Auto-filled" note.
  void _clearExtraction() {
    final snap = _preScanSnapshot;
    setState(() {
      if (snap != null) {
        _amount.text = snap['amount'] ?? '';
        _vendor.text = snap['vendor'] ?? '';
        _reference.text = snap['reference'] ?? '';
        if (_preScanDate != null) _date = _preScanDate!;
      }
      _autoFilled.clear();
      _directionAutoSet = false;
      _amountUnread = false;
      _preScanSnapshot = null;
      _preScanDate = null;
    });
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final desc = _description.text.trim();
    if (desc.isEmpty) {
      _toast(l10n.t('enterDescription'), error: true);
      return;
    }
    if (_value <= 0) {
      _toast(l10n.t('enterAmountGreaterThanZero'), error: true);
      return;
    }
    final ref = _reference.text.trim().isEmpty ? null : _reference.text.trim();
    final vendor = _vendor.text.trim().isEmpty ? null : _vendor.text.trim();
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final gst = double.tryParse(_gst.text.trim());
    final e = widget.existing;
    if (e == null) {
      _store.add(
        description: desc,
        amount: _value,
        dateTime: _date,
        type: _type,
        category: _category,
        reference: ref,
        gstAmount: gst,
        vendorName: vendor,
        paymentMethod: _payment,
        note: note,
        receiptPath: _receiptPath,
        receiptIsPdf: _receiptIsPdf,
        direction: _direction,
      );
    } else {
      _store.update(e.replace(
        description: desc,
        amount: _value,
        dateTime: _date,
        type: _type,
        category: _category,
        reference: ref,
        gstAmount: gst,
        vendorName: vendor,
        paymentMethod: _payment,
        note: note,
        receiptPath: _receiptPath,
        receiptIsPdf: _receiptIsPdf,
        direction: _direction,
      ));
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).maybePop();
  }

  void _toast(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
    ));
  }

  String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final editing = widget.existing != null;
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        child: SafeArea(
        child: Column(
          children: [
            _Header(
                title: l10n.t(editing ? 'editTransaction' : 'addTransaction'),
                onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                    AppSpacing.screen, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Segmented(
                      options: [l10n.t('expense'), l10n.t('income')],
                      selectedIndex: _type == TransactionType.income ? 1 : 0,
                      onChanged: (i) => _onTypeChanged(i == 1
                          ? TransactionType.income
                          : TransactionType.expense),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Feature 1 - upload payment proof (top of the form). Reads
                    // amount / date / vendor / direction and auto-fills below.
                    _UploadProof(
                      path: _receiptPath,
                      isPdf: _receiptIsPdf,
                      busy: _busy,
                      scanning: _scanning,
                      onTap: _attach,
                    ),
                    if (_autoFilled.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _AutoFilledNote(
                        fields: _autoFilled,
                        onClear: _clearExtraction,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    _AmountField(controller: _amount),
                    if (_amountUnread) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 14, color: AppColors.critical),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.t('couldntReadAmount'),
                              style: AppText.caption
                                  .copyWith(color: AppColors.critical),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    // Feature 2 - money direction, defaulted from the type above.
                    _Field(
                      label: l10n.t('direction'),
                      child: DirectionToggle(
                        value: _direction,
                        highlight: _directionAutoSet,
                        onChanged: _onDirectionChanged,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Field(
                      label: l10n.t('description'),
                      child: _input(_description, l10n.t('descriptionHint'),
                          cap: TextCapitalization.sentences),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Field(
                      label: l10n.t('category'),
                      child: _CategoryPicker(
                        selected: _category,
                        onChanged: (c) => setState(() => _category = c),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(children: [
                      Expanded(
                        child: _Field(
                          label: l10n.t('date'),
                          child: _Selector(
                              value: _fmtDate(_date),
                              icon: Icons.event_rounded,
                              onTap: _pickDate),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _Field(
                          label: l10n.t('transactionId'),
                          optional: true,
                          child: _input(_reference, l10n.t('transactionIdHint')),
                        ),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.md),
                    Row(children: [
                      Expanded(
                        child: _Field(
                          label: l10n.t('gstAmount'),
                          optional: true,
                          child: _input(_gst, '0', number: true),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _Field(
                          label: l10n.t('vendorName'),
                          optional: true,
                          child: _input(_vendor, l10n.t('vendorNameHint'),
                              cap: TextCapitalization.words),
                        ),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.md),
                    _Field(
                      label: l10n.t('paymentMethod'),
                      optional: true,
                      child: _PaymentPicker(
                        selected: _payment,
                        onChanged: (m) => setState(
                            () => _payment = _payment == m ? null : m),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Field(
                      label: l10n.t('notes'),
                      optional: true,
                      child: _input(_note, l10n.t('notesHint'),
                          cap: TextCapitalization.sentences, maxLines: 3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
      bottomNavigationBar: _SaveBar(
          onSave: _save,
          label: l10n.t(editing ? 'saveChanges' : 'addTransaction')),
    );
  }

  Widget _input(TextEditingController c, String hint,
      {TextCapitalization cap = TextCapitalization.none,
      bool number = false,
      int maxLines = 1}) {
    final palette = AppPalette.of(context);
    OutlineInputBorder border(Color col, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: col, width: w),
        );
    return TextField(
      controller: c,
      textCapitalization: cap,
      maxLines: maxLines,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : (maxLines > 1 ? TextInputType.multiline : null),
      inputFormatters: number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      style: AppText.body.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        prefixText: number ? '₹ ' : null,
        hintStyle: AppText.body.copyWith(color: palette.textFaint),
        filled: true,
        fillColor: palette.surfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: border(palette.border),
        enabledBorder: border(palette.border),
        focusedBorder: border(AppColors.primaryGreen, 1.6),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Text('₹',
              style: AppText.bigNumber
                  .copyWith(color: palette.textPrimary, fontSize: 30)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: AppText.bigNumber
                  .copyWith(color: palette.textPrimary, fontSize: 30),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: AppText.bigNumber
                    .copyWith(color: palette.textFaint, fontSize: 30),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected, required this.onChanged});

  final TxnCategory selected;
  final ValueChanged<TxnCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final c in TxnCategory.values)
          PressableScale(
            pressedScale: 0.95,
            child: GestureDetector(
              onTap: () => onChanged(c),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: c == selected
                      ? c.color.withValues(alpha: 0.16)
                      : palette.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                      color: c == selected ? c.color : palette.border,
                      width: c == selected ? 1.4 : 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(c.icon, size: 15, color: c.color),
                    const SizedBox(width: 5),
                    Text(c.label(AppLocalizations.of(context)),
                        style: AppText.caption.copyWith(
                            color: palette.textPrimary,
                            fontWeight: c == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PaymentPicker extends StatelessWidget {
  const _PaymentPicker({required this.selected, required this.onChanged});

  final PaymentMethod? selected;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final m in PaymentMethod.values)
          PressableScale(
            pressedScale: 0.95,
            child: GestureDetector(
              onTap: () => onChanged(m),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: m == selected
                      ? AppColors.primaryGreen.withValues(alpha: 0.16)
                      : palette.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                      color: m == selected
                          ? AppColors.primaryGreen
                          : palette.border,
                      width: m == selected ? 1.4 : 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(m.icon,
                        size: 15,
                        color: m == selected
                            ? AppColors.primaryGreen
                            : palette.textSecondary),
                    const SizedBox(width: 5),
                    Text(m.label(AppLocalizations.of(context)),
                        style: AppText.caption.copyWith(
                            color: palette.textPrimary,
                            fontWeight: m == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Feature 1 - the "Upload payment proof" area at the top of the form. A dashed
/// card with a receipt/camera icon when empty; once a file is chosen it shows a
/// thumbnail (or PDF chip) and a "Scanning…" state while OCR runs. Tapping opens
/// the Camera / Gallery / PDF source sheet.
class _UploadProof extends StatelessWidget {
  const _UploadProof({
    required this.path,
    required this.isPdf,
    required this.busy,
    required this.scanning,
    required this.onTap,
  });

  final String? path;
  final bool isPdf;
  final bool busy;
  final bool scanning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final empty = path == null;
    return Semantics(
      button: true,
      label: l10n.t(empty ? 'uploadPaymentProof' : 'changePaymentProof'),
      child: PressableScale(
        pressedScale: 0.99,
        child: GestureDetector(
          onTap: busy ? null : onTap,
          child: _DashedBorder(
            active: !empty,
            dashed: empty,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: busy
                  ? Row(
                      children: [
                        const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.4)),
                        const SizedBox(width: AppSpacing.sm),
                        Text(l10n.t(scanning ? 'scanning' : 'attaching'),
                            style: AppText.body
                                .copyWith(color: palette.textSecondary)),
                      ],
                    )
                  : empty
                      ? Row(
                          children: [
                            Container(
                              width: AppSizes.iconContainerSm,
                              height: AppSizes.iconContainerSm,
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.chip),
                              ),
                              child: const Icon(Icons.receipt_long_rounded,
                                  color: AppColors.primaryGreen, size: 22),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l10n.t('uploadPaymentProof'),
                                      style: AppText.subtitle.copyWith(
                                          color: palette.textPrimary,
                                          fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(l10n.t('uploadProofSubtitle'),
                                      style: AppText.caption.copyWith(
                                          color: palette.textSecondary)),
                                ],
                              ),
                            ),
                            const Icon(Icons.photo_camera_rounded,
                                color: AppColors.primaryGreen, size: 20),
                          ],
                        )
                      : Row(
                          children: [
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.chip),
                              child: isPdf
                                  ? Container(
                                      width: 56,
                                      height: 56,
                                      color: AppColors.lightBlue
                                          .withValues(alpha: 0.14),
                                      child: const Icon(
                                          Icons.picture_as_pdf_rounded,
                                          color: AppColors.lightBlue,
                                          size: 26),
                                    )
                                  : Image.file(File(path!),
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                            width: 56,
                                            height: 56,
                                            color: palette.surface,
                                            child: Icon(Icons.image_rounded,
                                                color: palette.textFaint),
                                          )),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                  l10n.t(isPdf
                                      ? 'pdfAttachedTapChange'
                                      : 'attachedTapChange'),
                                  style: AppText.body
                                      .copyWith(color: palette.textPrimary)),
                            ),
                            Icon(Icons.edit_rounded,
                                size: 18, color: palette.textFaint),
                          ],
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded container that draws a dashed border when [dashed] (empty upload
/// state), or a solid teal border once a file is attached ([active]).
class _DashedBorder extends StatelessWidget {
  const _DashedBorder({
    required this.child,
    required this.dashed,
    required this.active,
  });

  final Widget child;
  final bool dashed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = active ? AppColors.primaryGreen : palette.border;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: CustomPaint(
        painter: dashed
            ? _DashedRectPainter(
                color: color, radius: AppRadius.card)
            : null,
        foregroundPainter: dashed
            ? null
            : _SolidRectPainter(color: color, radius: AppRadius.card),
        child: child,
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

class _SolidRectPainter extends CustomPainter {
  _SolidRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SolidRectPainter old) => old.color != color;
}

/// The "Auto-filled from receipt ✓" note with a Clear action to discard the
/// extraction.
class _AutoFilledNote extends StatelessWidget {
  const _AutoFilledNote({required this.fields, required this.onClear});

  final Set<String> fields;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.primaryGreen, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.t('autoFilledFromReceipt'),
              style: AppText.caption.copyWith(
                  color: AppColors.darkGreen, fontWeight: FontWeight.w700),
            ),
          ),
          PressableScale(
            pressedScale: 0.9,
            child: GestureDetector(
              onTap: onClear,
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                button: true,
                label: l10n.t('clearAutoFilled'),
                child: Text(l10n.t('clear'),
                    style: AppText.caption.copyWith(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.optional = false});

  final String label;
  final Widget child;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
              style: AppText.label
                  .copyWith(color: palette.textFaint, fontSize: 11.5)),
          if (optional) ...[
            const SizedBox(width: 6),
            Text(AppLocalizations.of(context).t('optional'),
                style: AppText.label
                    .copyWith(color: palette.textFaint, fontSize: 10.5)),
          ],
        ]),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _Selector extends StatelessWidget {
  const _Selector(
      {required this.value, required this.icon, required this.onTap});

  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.98,
      child: Material(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: AppColors.primaryGreen),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle
                          .copyWith(color: palette.textPrimary, fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: i == selectedIndex ? AppColors.brandGradient : null,
                    borderRadius: BorderRadius.circular(AppRadius.chip - 4),
                  ),
                  child: Text(options[i],
                      style: AppText.subtitle.copyWith(
                          color: i == selectedIndex
                              ? Colors.white
                              : palette.textSecondary,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.onSave, required this.label});

  final VoidCallback onSave;
  final String label;

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
          child: PressableScale(
            child: GestureDetector(
              onTap: onSave,
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
                child: Center(
                  child: Text(label,
                      style: AppText.subtitle.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
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
          Text(title,
              style: AppText.headline
                  .copyWith(color: palette.textPrimary, fontSize: 21)),
        ],
      ),
    );
  }
}
