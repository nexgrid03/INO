import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/expense_models.dart';
import '../../services/camera_permission_service.dart';
import '../../services/expense_store.dart';
import '../../services/gallery_import_service.dart';
import '../../services/ocr_service.dart';
import '../../services/pdf_import_service.dart';
import '../../services/receipt_parser.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
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
    }
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
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
                  const Icon(Icons.image_rounded, color: AppColors.primaryGreen),
              title: const Text('Photo / Screenshot'),
              subtitle: const Text('Auto-reads amount, date & vendor'),
              onTap: () => Navigator.of(context).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded,
                  color: AppColors.lightBlue),
              title: const Text('PDF Receipt'),
              onTap: () => Navigator.of(context).pop('pdf'),
            ),
            if (_receiptPath != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_rounded, color: AppColors.critical),
                title: const Text('Remove attachment'),
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
      if (choice == 'image') {
        final access = await CameraPermissionService.instance.requestPhotos();
        if (access != CameraAccess.granted) {
          _toast('Photo access is needed to attach a screenshot', error: true);
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
      if (mounted) _toast('Could not attach the receipt', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs OCR on the receipt image and pre-fills empty fields only.
  Future<void> _runOcr(String path) async {
    setState(() => _scanning = true);
    try {
      final extraction = await OcrService.instance.extract(path);
      final data = ReceiptParser.parse(extraction.rawText);
      if (!mounted || data.isEmpty) return;
      final filled = <String>[];
      if (data.amount != null && _amount.text.trim().isEmpty) {
        _amount.text = _fmt(data.amount!);
        filled.add('amount');
      }
      if (data.date != null) {
        _date = DateTime(data.date!.year, data.date!.month, data.date!.day,
            _date.hour, _date.minute);
        filled.add('date');
      }
      if (data.vendorName != null && _vendor.text.trim().isEmpty) {
        _vendor.text = data.vendorName!;
        filled.add('vendor');
      }
      if (data.gstNumber != null && _reference.text.trim().isEmpty) {
        _reference.text = data.gstNumber!;
        filled.add('GSTIN');
      }
      setState(() {});
      if (filled.isNotEmpty) _toast('Auto-filled ${filled.join(', ')} from receipt');
    } catch (_) {
      // OCR is best-effort — silently skip if it can't read the receipt.
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _save() {
    final desc = _description.text.trim();
    if (desc.isEmpty) {
      _toast('Enter a description', error: true);
      return;
    }
    if (_value <= 0) {
      _toast('Enter an amount greater than 0', error: true);
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
    final editing = widget.existing != null;
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
                title: editing ? 'Edit Transaction' : 'Add Transaction',
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
                      options: const ['Expense', 'Income'],
                      selectedIndex: _type == TransactionType.income ? 1 : 0,
                      onChanged: (i) => setState(() => _type = i == 1
                          ? TransactionType.income
                          : TransactionType.expense),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _AmountField(controller: _amount),
                    const SizedBox(height: AppSpacing.md),
                    _Field(
                      label: 'Description',
                      child: _input(_description, 'e.g. Office rent',
                          cap: TextCapitalization.sentences),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Field(
                      label: 'Category',
                      child: _CategoryPicker(
                        selected: _category,
                        onChanged: (c) => setState(() => _category = c),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(children: [
                      Expanded(
                        child: _Field(
                          label: 'Date',
                          child: _Selector(
                              value: _fmtDate(_date),
                              icon: Icons.event_rounded,
                              onTap: _pickDate),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _Field(
                          label: 'Transaction ID',
                          optional: true,
                          child: _input(_reference, 'TXN123456'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.md),
                    Row(children: [
                      Expanded(
                        child: _Field(
                          label: 'GST Amount',
                          optional: true,
                          child: _input(_gst, '0', number: true),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _Field(
                          label: 'Vendor Name',
                          optional: true,
                          child: _input(_vendor, 'e.g. Reliance',
                              cap: TextCapitalization.words),
                        ),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.md),
                    _Field(
                      label: 'Payment Method',
                      optional: true,
                      child: _PaymentPicker(
                        selected: _payment,
                        onChanged: (m) => setState(
                            () => _payment = _payment == m ? null : m),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Field(
                      label: 'Notes',
                      optional: true,
                      child: _input(_note, 'Anything to remember…',
                          cap: TextCapitalization.sentences, maxLines: 3),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Field(
                      label: 'Receipt / Screenshot',
                      optional: true,
                      child: _ReceiptPicker(
                        path: _receiptPath,
                        isPdf: _receiptIsPdf,
                        busy: _busy,
                        scanning: _scanning,
                        onTap: _attach,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _SaveBar(
          onSave: _save, label: editing ? 'Save Changes' : 'Add Transaction'),
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
                    Text(c.label,
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
                    Text(m.label,
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

class _ReceiptPicker extends StatelessWidget {
  const _ReceiptPicker({
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
    return PressableScale(
      pressedScale: 0.99,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          height: path == null ? 64 : 84,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
                color: path == null ? palette.border : AppColors.primaryGreen),
          ),
          child: busy
              ? Row(
                  children: [
                    const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(scanning ? 'Reading receipt…' : 'Attaching…',
                        style:
                            AppText.body.copyWith(color: palette.textSecondary)),
                  ],
                )
              : path == null
                  ? Row(
                      children: [
                        const Icon(Icons.upload_file_rounded,
                            color: AppColors.primaryGreen),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Attach receipt (auto-reads details)',
                            style: AppText.body
                                .copyWith(color: palette.textSecondary)),
                      ],
                    )
                  : Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          child: isPdf
                              ? Container(
                                  width: 60,
                                  height: 60,
                                  color:
                                      AppColors.lightBlue.withValues(alpha: 0.14),
                                  child: const Icon(Icons.picture_as_pdf_rounded,
                                      color: AppColors.lightBlue, size: 28),
                                )
                              : Image.file(File(path!),
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                        width: 60,
                                        height: 60,
                                        color: palette.surface,
                                        child: Icon(Icons.image_rounded,
                                            color: palette.textFaint),
                                      )),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                              isPdf
                                  ? 'PDF attached'
                                  : 'Image attached · tap to change',
                              style: AppText.body
                                  .copyWith(color: palette.textPrimary)),
                        ),
                        Icon(Icons.edit_rounded,
                            size: 18, color: palette.textFaint),
                      ],
                    ),
        ),
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
            Text('Optional',
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
