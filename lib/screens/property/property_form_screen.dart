import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/area_unit.dart';
import '../../models/currency.dart';
import '../../models/property_models.dart';
import '../../services/app_settings.dart';
import '../../services/gallery_import_service.dart';
import '../../services/property_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/common/save_consent_sheet.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet_modules/module_kit.dart';

/// Add / edit a property.
///
/// One long form, but broken into the six sections of the brief - Basics,
/// Location, Ownership, Legal, Financial, Notes - each in its own card so the
/// screen reads as a checklist rather than a wall of inputs. Only the property
/// name is required; everything else can be filled in whenever the user has it.
class PropertyFormScreen extends StatefulWidget {
  const PropertyFormScreen({super.key, this.existing});

  /// When set the form edits this property instead of creating a new one.
  final Property? existing;

  @override
  State<PropertyFormScreen> createState() => _PropertyFormScreenState();
}

class _PropertyFormScreenState extends State<PropertyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _store = PropertyStore.instance;

  // Basics
  final _name = TextEditingController();
  final _purchasePrice = TextEditingController();
  final _currentValue = TextEditingController();
  final _area = TextEditingController();
  PropertyType _type = PropertyType.house;
  PropertyStatus _status = PropertyStatus.owned;
  AreaUnit _areaUnit = AreaUnit.squareFeet;
  DateTime? _purchaseDate;
  String? _imagePath;

  // Location
  final _country = TextEditingController();
  final _state = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _pin = TextEditingController();
  final _maps = TextEditingController();

  // Ownership
  final _owner = TextEditingController();
  final _ownership = TextEditingController();
  final _regNumber = TextEditingController();
  DateTime? _regDate;
  List<CoOwner> _coOwners = [];

  // Legal
  final _will = TextEditingController();
  final _nominee = TextEditingController();
  final _nomineeRelation = TextEditingController();
  final _heirs = TextEditingController();
  final _taxId = TextEditingController();
  final _encumbrance = TextEditingController();
  final _loanProvider = TextEditingController();
  final _outstanding = TextEditingController();
  bool _hasLoan = false;

  // Financial
  final _emi = TextEditingController();
  final _annualTax = TextEditingController();
  final _maintenance = TextEditingController();
  final _rent = TextEditingController();
  final _otherExpenses = TextEditingController();

  // Notes
  final _notes = TextEditingController();
  final _reminder = TextEditingController();

  List<PropertyAttachment> _attachments = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p == null) return;
    _name.text = p.name;
    _type = p.type;
    _status = p.status;
    _imagePath = p.imagePath;
    _purchaseDate = p.purchaseDate;
    _purchasePrice.text = _numText(p.purchasePrice);
    _currentValue.text = _numText(p.currentValue);
    _area.text = _numText(p.area);
    _areaUnit = p.areaUnit;
    _country.text = p.country ?? '';
    _state.text = p.state ?? '';
    _city.text = p.city ?? '';
    _address.text = p.address ?? '';
    _pin.text = p.pinCode ?? '';
    _maps.text = p.mapsUrl ?? '';
    _owner.text = p.ownerName ?? '';
    _ownership.text = _numText(p.ownershipPercent);
    _regNumber.text = p.registrationNumber ?? '';
    _regDate = p.registrationDate;
    _coOwners = [...p.coOwners];
    _will.text = p.willDetails ?? '';
    _nominee.text = p.nomineeName ?? '';
    _nomineeRelation.text = p.nomineeRelationship ?? '';
    _heirs.text = p.legalHeirs.join(', ');
    _taxId.text = p.taxId ?? '';
    _encumbrance.text = p.encumbrance ?? '';
    _hasLoan = p.hasLoan;
    _loanProvider.text = p.loanProvider ?? '';
    _outstanding.text = _numText(p.outstandingLoan);
    _emi.text = _numText(p.emi);
    _annualTax.text = _numText(p.annualTax);
    _maintenance.text = _numText(p.maintenanceCharges);
    _rent.text = _numText(p.rentalIncome);
    _otherExpenses.text = _numText(p.otherExpenses);
    _notes.text = p.notes ?? '';
    _reminder.text = p.reminderNote ?? '';
    _attachments = [...p.attachments];
  }

  /// Renders a stored number without a trailing ".0" so the field reads the way
  /// the user typed it.
  static String _numText(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _purchasePrice, _currentValue, _area, //
      _country, _state, _city, _address, _pin, _maps,
      _owner, _ownership, _regNumber,
      _will, _nominee, _nomineeRelation, _heirs, _taxId, _encumbrance,
      _loanProvider, _outstanding,
      _emi, _annualTax, _maintenance, _rent, _otherExpenses,
      _notes, _reminder,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Currency get _currency =>
      Currencies.byCode(AppSettings.instance.currency.value);

  double? _parse(TextEditingController c) {
    final raw = c.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  String? _emptyOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  // ---- Actions -------------------------------------------------------------

  Future<void> _pickImage() async {
    final path = await GalleryImportService.instance.pickImage();
    if (path == null || !mounted) return;
    setState(() => _imagePath = path);
  }

  Future<void> _pickType() async {
    final i = await showModulePicker(
      context,
      title: 'Property type',
      labels: [for (final t in PropertyType.values) t.label],
      icons: [for (final t in PropertyType.values) t.icon],
      selectedIndex: PropertyType.values.indexOf(_type),
    );
    if (i == null || !mounted) return;
    setState(() => _type = PropertyType.values[i]);
  }

  Future<void> _pickStatus() async {
    final i = await showModulePicker(
      context,
      title: 'Property status',
      labels: [for (final s in PropertyStatus.values) s.label],
      icons: [for (final s in PropertyStatus.values) s.icon],
      colors: [for (final s in PropertyStatus.values) s.color],
      selectedIndex: PropertyStatus.values.indexOf(_status),
    );
    if (i == null || !mounted) return;
    setState(() => _status = PropertyStatus.values[i]);
  }

  Future<void> _pickAreaUnit() async {
    final i = await showModulePicker(
      context,
      title: 'Area unit',
      labels: [for (final u in AreaUnit.values) u.label],
      selectedIndex: AreaUnit.values.indexOf(_areaUnit),
    );
    if (i == null || !mounted) return;
    setState(() => _areaUnit = AreaUnit.values[i]);
  }

  Future<void> _pickDate({required bool purchase}) async {
    final picked = await showModuleDatePicker(
      context,
      initial: (purchase ? _purchaseDate : _regDate) ?? DateTime.now(),
      last: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (purchase) {
        _purchaseDate = picked;
      } else {
        _regDate = picked;
      }
    });
  }

  Future<void> _addCoOwner() async {
    final result = await showModalBottomSheet<CoOwner>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CoOwnerSheet(),
    );
    if (result == null || !mounted) return;
    setState(() => _coOwners = [..._coOwners, result]);
  }

  Future<void> _addAttachment() async {
    final kindIndex = await showModulePicker(
      context,
      title: 'Attach document',
      labels: [for (final k in PropertyDocKind.values) k.label],
      icons: [for (final k in PropertyDocKind.values) k.icon],
    );
    if (kindIndex == null || !mounted) return;
    final kind = PropertyDocKind.values[kindIndex];
    final path = await GalleryImportService.instance.pickImage();
    if (path == null || !mounted) return;
    setState(() {
      _attachments = [
        ..._attachments,
        PropertyAttachment(
          id: 'att_${DateTime.now().microsecondsSinceEpoch}',
          kind: kind,
          name: kind.label,
          path: path,
          addedAt: DateTime.now(),
        ),
      ];
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      showModuleToast(context, 'Give the property a name first', error: true);
      return;
    }
    FocusScope.of(context).unfocus();

    // The consent gate: nothing is stored until the user agrees.
    if (!await showDataConsentSheet(context, what: 'this property')) return;
    if (!mounted) return;
    setState(() => _saving = true);

    final now = DateTime.now();
    final heirs = _heirs.text
        .split(',')
        .map((h) => h.trim())
        .where((h) => h.isNotEmpty)
        .toList();

    final property = Property(
      id: widget.existing?.id ?? _store.newId('prop'),
      name: _name.text.trim(),
      type: _type,
      status: _status,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      imagePath: _imagePath,
      purchaseDate: _purchaseDate,
      purchasePrice: _parse(_purchasePrice),
      currentValue: _parse(_currentValue),
      area: _parse(_area),
      areaUnit: _areaUnit,
      country: _emptyOrNull(_country),
      state: _emptyOrNull(_state),
      city: _emptyOrNull(_city),
      address: _emptyOrNull(_address),
      pinCode: _emptyOrNull(_pin),
      mapsUrl: _emptyOrNull(_maps),
      ownerName: _emptyOrNull(_owner),
      coOwners: _coOwners,
      ownershipPercent: _parse(_ownership),
      registrationNumber: _emptyOrNull(_regNumber),
      registrationDate: _regDate,
      willDetails: _emptyOrNull(_will),
      nomineeName: _emptyOrNull(_nominee),
      nomineeRelationship: _emptyOrNull(_nomineeRelation),
      legalHeirs: heirs,
      taxId: _emptyOrNull(_taxId),
      encumbrance: _emptyOrNull(_encumbrance),
      hasLoan: _hasLoan,
      loanProvider: _hasLoan ? _emptyOrNull(_loanProvider) : null,
      outstandingLoan: _hasLoan ? _parse(_outstanding) : null,
      emi: _parse(_emi),
      annualTax: _parse(_annualTax),
      maintenanceCharges: _parse(_maintenance),
      rentalIncome: _parse(_rent),
      otherExpenses: _parse(_otherExpenses),
      notes: _emptyOrNull(_notes),
      reminderNote: _emptyOrNull(_reminder),
      attachments: _attachments,
      isFavorite: widget.existing?.isFavorite ?? false,
    );

    if (_isEdit) {
      await _store.update(property);
    } else {
      await _store.add(property);
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (_isEdit) {
      await showSuccessBurst(context, 'Changes saved');
    }
    if (!mounted) return;
    Navigator.of(context).pop(property);
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final glass = divineGlassEnabled(context);
    final symbol = _currency.symbol;
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        sky: glass,
        child: SafeArea(
          top: !glass,
          bottom: false,
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                ModuleHeader(
                  title: _isEdit ? 'Edit property' : 'Add property',
                  subtitle: _isEdit
                      ? widget.existing!.name
                      : 'Only the name is required',
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 140),
                    children: [
                // ---- Photo ----
                FadeSlideIn(
                  child: _PhotoPicker(
                    imagePath: _imagePath,
                    type: _type,
                    onPick: _pickImage,
                    onClear: () => setState(() => _imagePath = null),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Basics ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 40),
                  child: ModuleSection(
                    title: 'Basic information',
                    icon: Icons.home_work_rounded,
                    children: [
                      ModuleField(
                        label: 'Property name',
                        controller: _name,
                        hint: 'e.g. Green Meadows Villa',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter a property name'
                            : null,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ModulePickerField(
                              label: 'Type',
                              value: _type.label,
                              icon: _type.icon,
                              onTap: _pickType,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModulePickerField(
                              label: 'Status',
                              value: _status.label,
                              icon: _status.icon,
                              accent: _status.color,
                              onTap: _pickStatus,
                            ),
                          ),
                        ],
                      ),
                      ModulePickerField(
                        label: 'Purchase date',
                        value: _purchaseDate == null
                            ? null
                            : formatModuleDate(_purchaseDate!),
                        hint: 'Select a date',
                        icon: Icons.event_rounded,
                        trailingIcon: Icons.calendar_month_rounded,
                        onTap: () => _pickDate(purchase: true),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ModuleField(
                              label: 'Purchase price',
                              controller: _purchasePrice,
                              hint: '0',
                              prefixText: '$symbol ',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModuleField(
                              label: 'Current value',
                              controller: _currentValue,
                              hint: '0',
                              prefixText: '$symbol ',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ModuleField(
                              label: 'Area',
                              controller: _area,
                              hint: '0',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            flex: 4,
                            child: ModulePickerField(
                              label: 'Unit',
                              value: _areaUnit.shortLabel,
                              icon: Icons.square_foot_rounded,
                              onTap: _pickAreaUnit,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Location ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: ModuleSection(
                    title: 'Location',
                    icon: Icons.place_rounded,
                    accent: const Color(0xFF4383EA),
                    children: [
                      ModuleField(
                        label: 'Full address',
                        controller: _address,
                        hint: 'Street, locality, landmark',
                        maxLines: 2,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ModuleField(
                              label: 'City',
                              controller: _city,
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModuleField(
                              label: 'State',
                              controller: _state,
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ModuleField(
                              label: 'Country',
                              controller: _country,
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModuleField(
                              label: 'PIN code',
                              controller: _pin,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                            ),
                          ),
                        ],
                      ),
                      ModuleField(
                        label: 'Google Maps link',
                        controller: _maps,
                        hint: 'Paste a maps URL or plus code',
                        keyboardType: TextInputType.url,
                        textCapitalization: TextCapitalization.none,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Ownership ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: ModuleSection(
                    title: 'Ownership',
                    icon: Icons.badge_rounded,
                    accent: const Color(0xFF9B6DE0),
                    children: [
                      ModuleField(
                        label: 'Owner name',
                        controller: _owner,
                        textCapitalization: TextCapitalization.words,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ModuleField(
                              label: 'Your share',
                              controller: _ownership,
                              hint: '100',
                              suffix: const Padding(
                                padding: EdgeInsets.only(right: 12),
                                child: Text('%'),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModuleField(
                              label: 'Registration no.',
                              controller: _regNumber,
                              textCapitalization: TextCapitalization.characters,
                            ),
                          ),
                        ],
                      ),
                      ModulePickerField(
                        label: 'Registration date',
                        value:
                            _regDate == null ? null : formatModuleDate(_regDate!),
                        hint: 'Select a date',
                        icon: Icons.event_available_rounded,
                        trailingIcon: Icons.calendar_month_rounded,
                        onTap: () => _pickDate(purchase: false),
                      ),
                      _CoOwnerList(
                        coOwners: _coOwners,
                        onAdd: _addCoOwner,
                        onRemove: (i) => setState(() {
                          _coOwners = [..._coOwners]..removeAt(i);
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Legal ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 160),
                  child: ModuleSection(
                    title: 'Legal details',
                    icon: Icons.gavel_rounded,
                    accent: const Color(0xFFF5704A),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ModuleField(
                              label: 'Nominee',
                              controller: _nominee,
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModuleField(
                              label: 'Relationship',
                              controller: _nomineeRelation,
                              hint: 'e.g. Spouse',
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                        ],
                      ),
                      ModuleField(
                        label: 'Legal heirs',
                        controller: _heirs,
                        hint: 'Comma-separated names',
                        textCapitalization: TextCapitalization.words,
                      ),
                      ModuleField(
                        label: 'Will details',
                        controller: _will,
                        hint: 'Where the will is held, executor, clauses',
                        maxLines: 3,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ModuleField(
                              label: 'Property tax ID',
                              controller: _taxId,
                              textCapitalization: TextCapitalization.characters,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModuleField(
                              label: 'Encumbrance',
                              controller: _encumbrance,
                              hint: 'e.g. None',
                            ),
                          ),
                        ],
                      ),
                      ModuleSwitchField(
                        label: 'Loan against property',
                        subtitle: 'Track the lender and what is still owed',
                        icon: Icons.account_balance_rounded,
                        value: _hasLoan,
                        onChanged: (v) => setState(() => _hasLoan = v),
                      ),
                      // The lender fields only exist while there IS a loan, so
                      // the form never asks for something that can't apply.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _hasLoan
                            ? Row(
                                children: [
                                  Expanded(
                                    child: ModuleField(
                                      label: 'Loan provider',
                                      controller: _loanProvider,
                                      textCapitalization:
                                          TextCapitalization.words,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: ModuleField(
                                      label: 'Outstanding',
                                      controller: _outstanding,
                                      hint: '0',
                                      prefixText: '$symbol ',
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Financial ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 200),
                  child: ModuleSection(
                    title: 'Financial information',
                    icon: Icons.payments_rounded,
                    accent: AppColors.success,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ModuleField(
                              label: 'EMI / month',
                              controller: _emi,
                              hint: '0',
                              prefixText: '$symbol ',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModuleField(
                              label: 'Rental income / month',
                              controller: _rent,
                              hint: '0',
                              prefixText: '$symbol ',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ModuleField(
                              label: 'Annual property tax',
                              controller: _annualTax,
                              hint: '0',
                              prefixText: '$symbol ',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModuleField(
                              label: 'Maintenance / year',
                              controller: _maintenance,
                              hint: '0',
                              prefixText: '$symbol ',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                        ],
                      ),
                      ModuleField(
                        label: 'Other expenses / year',
                        controller: _otherExpenses,
                        hint: '0',
                        prefixText: '$symbol ',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Documents ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 240),
                  child: ModuleSection(
                    title: 'Documents',
                    icon: Icons.folder_copy_rounded,
                    accent: const Color(0xFF0891B2),
                    subtitle: 'Deed, registration, tax receipts, plans',
                    trailing: ModuleIconButton(
                      icon: Icons.add_rounded,
                      size: 34,
                      tooltip: 'Attach',
                      onTap: _addAttachment,
                    ),
                    children: [
                      if (_attachments.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'Nothing attached yet.',
                            style: AppText.caption
                                .copyWith(color: palette.textFaint),
                          ),
                        )
                      else
                        for (var i = 0; i < _attachments.length; i++)
                          _AttachmentRow(
                            attachment: _attachments[i],
                            onRemove: () => setState(() {
                              _attachments = [..._attachments]..removeAt(i);
                            }),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Notes ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 280),
                  child: ModuleSection(
                    title: 'Notes',
                    icon: Icons.sticky_note_2_rounded,
                    accent: const Color(0xFF64748B),
                    children: [
                      ModuleField(
                        label: 'Custom notes',
                        controller: _notes,
                        hint: 'Anything worth remembering about this property',
                        maxLines: 4,
                      ),
                      ModuleField(
                        label: 'Important reminder',
                        controller: _reminder,
                        hint: 'e.g. Property tax due every April',
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _SaveBar(
        label: _isEdit ? 'Save changes' : 'Add property',
        busy: _saving,
        onSave: _save,
      ),
    );
  }
}

/// The sticky save bar every module form carries.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.label,
    required this.onSave,
    required this.busy,
  });

  final String label;
  final VoidCallback onSave;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: GradientButton(label: label, busy: busy, onTap: onSave),
      ),
    );
  }
}

/// The photo well at the top of the form: tap to pick, tap the badge to clear.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.imagePath,
    required this.type,
    required this.onPick,
    required this.onClear,
  });

  final String? imagePath;
  final PropertyType type;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final has = imagePath != null && File(imagePath!).existsSync();
    return PressableScale(
      pressedScale: 0.99,
      child: GestureDetector(
        onTap: onPick,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 168,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (has)
                Image.file(
                  File(imagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.brandGradient,
                          boxShadow: AppShadows.glow(AppColors.primaryGreen,
                              opacity: 0.25),
                        ),
                        child: const Icon(Icons.add_a_photo_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(height: 10),
                      Text('Add a property photo',
                          style: AppText.subtitle
                              .copyWith(color: palette.textPrimary)),
                      const SizedBox(height: 2),
                      Text('Optional, but it makes the card yours',
                          style: AppText.caption
                              .copyWith(color: palette.textSecondary)),
                    ],
                  ),
                ),
              if (has)
                Positioned(
                  top: 10,
                  right: 10,
                  child: ModuleIconButton(
                    icon: Icons.close_rounded,
                    size: 34,
                    tooltip: 'Remove photo',
                    onTap: onClear,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The co-owner list inside the Ownership section.
class _CoOwnerList extends StatelessWidget {
  const _CoOwnerList({
    required this.coOwners,
    required this.onAdd,
    required this.onRemove,
  });

  final List<CoOwner> coOwners;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Co-owners',
                style: AppText.label.copyWith(color: palette.textPrimary)),
            const Spacer(),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_rounded, size: 17),
              label: const Text('Add'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        if (coOwners.isEmpty)
          Text(
            'No co-owners recorded.',
            style: AppText.caption.copyWith(color: palette.textFaint),
          )
        else
          for (var i = 0; i < coOwners.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
                decoration: BoxDecoration(
                  color: palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded,
                        size: 17, color: Color(0xFF9B6DE0)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        coOwners[i].relationship == null
                            ? coOwners[i].name
                            : '${coOwners[i].name} · ${coOwners[i].relationship}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(color: palette.textPrimary),
                      ),
                    ),
                    if (coOwners[i].sharePercent != null)
                      Text(
                        '${coOwners[i].sharePercent!.toStringAsFixed(0)}%',
                        style: AppText.label
                            .copyWith(color: palette.textSecondary),
                      ),
                    IconButton(
                      onPressed: () => onRemove(i),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      color: palette.textFaint,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachment, required this.onRemove});

  final PropertyAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
        decoration: BoxDecoration(
          color: palette.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(attachment.kind.icon, size: 17, color: const Color(0xFF0891B2)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(color: palette.textPrimary),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 17),
              color: palette.textFaint,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// The add-co-owner sheet: name, relationship and share.
class _CoOwnerSheet extends StatefulWidget {
  const _CoOwnerSheet();

  @override
  State<_CoOwnerSheet> createState() => _CoOwnerSheetState();
}

class _CoOwnerSheetState extends State<_CoOwnerSheet> {
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _share = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    _share.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      CoOwner(
        name: name,
        relationship:
            _relation.text.trim().isEmpty ? null : _relation.text.trim(),
        sharePercent: double.tryParse(_share.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.large)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Add co-owner',
                  style: AppText.title.copyWith(color: palette.textPrimary)),
              const SizedBox(height: AppSpacing.md),
              ModuleField(
                label: 'Name',
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
              ),
              Row(
                children: [
                  Expanded(
                    child: ModuleField(
                      label: 'Relationship',
                      controller: _relation,
                      hint: 'e.g. Brother',
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ModuleField(
                      label: 'Share',
                      controller: _share,
                      hint: '50',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              GradientButton(label: 'Add co-owner', onTap: _save),
            ],
          ),
        ),
      ),
    );
  }
}
