import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/currency.dart';
import '../../models/investment_models.dart';
import '../../services/app_settings.dart';
import '../../services/gallery_import_service.dart';
import '../../services/investment_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/common/save_consent_sheet.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/wallet_modules/module_kit.dart';

/// The user-facing name of an [InvestmentType] in the active language.
///
/// The enum's own `name` remains the persisted value - only the label the user
/// reads is translated, so switching language never rewrites stored data.
String investmentTypeLabel(AppLocalizations l10n, InvestmentType type) =>
    l10n.t(switch (type) {
      InvestmentType.stocks => 'invTypeStocks',
      InvestmentType.mutualFunds => 'invTypeMutualFunds',
      InvestmentType.etf => 'invTypeEtf',
      InvestmentType.bonds => 'invTypeBonds',
      InvestmentType.fixedDeposit => 'invTypeFixedDeposit',
      InvestmentType.gold => 'invTypeGold',
      InvestmentType.crypto => 'invTypeCrypto',
      InvestmentType.ppf => 'invTypePpf',
      InvestmentType.nps => 'invTypeNps',
      InvestmentType.sip => 'invTypeSip',
      InvestmentType.realEstate => 'invTypeRealEstate',
      InvestmentType.other => 'invTypeOther',
    });

/// The short label used on chips and the allocation legend.
String investmentTypeShortLabel(AppLocalizations l10n, InvestmentType type) =>
    type == InvestmentType.fixedDeposit
        ? l10n.t('invTypeFixedDepositShort')
        : investmentTypeLabel(l10n, type);

/// Add / edit one holding.
///
/// The form adapts to the instrument: units and unit price only appear for
/// things measured in units, and a maturity date only for instruments that
/// actually mature. A live preview strip at the bottom shows the profit/loss
/// the entered numbers imply, so a typo is obvious before saving.
class InvestmentFormScreen extends StatefulWidget {
  const InvestmentFormScreen({super.key, this.existing});

  final Investment? existing;

  @override
  State<InvestmentFormScreen> createState() => _InvestmentFormScreenState();
}

class _InvestmentFormScreenState extends State<InvestmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _store = InvestmentStore.instance;

  final _name = TextEditingController();
  final _institution = TextEditingController();
  final _account = TextEditingController();
  final _units = TextEditingController();
  final _unitPrice = TextEditingController();
  final _invested = TextEditingController();
  final _current = TextEditingController();
  final _nominee = TextEditingController();
  final _notes = TextEditingController();

  InvestmentType _type = InvestmentType.stocks;
  DateTime? _purchaseDate;
  DateTime? _maturityDate;
  List<InvestmentAttachment> _attachments = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  /// Units × price only makes sense for instruments that trade in units.
  bool get _showsUnits => switch (_type) {
        InvestmentType.stocks ||
        InvestmentType.mutualFunds ||
        InvestmentType.etf ||
        InvestmentType.gold ||
        InvestmentType.crypto =>
          true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    final i = widget.existing;
    if (i == null) return;
    _name.text = i.name;
    _type = i.type;
    _institution.text = i.institution ?? '';
    _account.text = i.accountNumber ?? '';
    _units.text = _numText(i.units);
    _unitPrice.text = _numText(i.purchasePrice);
    _invested.text = _numText(i.investedAmount);
    _current.text = _numText(i.currentValue);
    _nominee.text = i.nominee ?? '';
    _notes.text = i.notes ?? '';
    _purchaseDate = i.purchaseDate;
    _maturityDate = i.maturityDate;
    _attachments = [...i.attachments];
  }

  static String _numText(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _institution, _account, _units, _unitPrice, //
      _invested, _current, _nominee, _notes,
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

  /// What the form currently implies was invested - the explicit amount, else
  /// units × unit price. Mirrors [Investment.invested] exactly.
  double get _impliedInvested {
    final explicit = _parse(_invested);
    if (explicit != null) return explicit;
    final u = _parse(_units);
    final p = _parse(_unitPrice);
    if (u != null && p != null) return u * p;
    return 0;
  }

  Future<void> _pickType() async {
    final l10n = AppLocalizations.of(context);
    final i = await showModulePicker(
      context,
      title: l10n.t('investmentType'),
      labels: [
        for (final t in InvestmentType.values) investmentTypeLabel(l10n, t),
      ],
      icons: [for (final t in InvestmentType.values) t.icon],
      colors: [for (final t in InvestmentType.values) t.color],
      selectedIndex: InvestmentType.values.indexOf(_type),
    );
    if (i == null || !mounted) return;
    setState(() => _type = InvestmentType.values[i]);
  }

  Future<void> _pickDate({required bool purchase}) async {
    final picked = await showModuleDatePicker(
      context,
      initial: (purchase ? _purchaseDate : _maturityDate) ?? DateTime.now(),
      // A maturity date is in the future; a purchase date never is.
      first: purchase ? null : DateTime.now(),
      last: purchase ? DateTime.now() : null,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (purchase) {
        _purchaseDate = picked;
      } else {
        _maturityDate = picked;
      }
    });
  }

  Future<void> _attach() async {
    final path = await GalleryImportService.instance.pickImage();
    if (path == null || !mounted) return;
    setState(() {
      _attachments = [
        ..._attachments,
        InvestmentAttachment(
          id: 'inv_att_${DateTime.now().microsecondsSinceEpoch}',
          name: 'Statement ${_attachments.length + 1}',
          path: path,
        ),
      ];
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) {
      showModuleToast(context, l10n.t('nameTheInvestmentFirst'), error: true);
      return;
    }
    FocusScope.of(context).unfocus();

    // The consent gate: nothing is stored until the user agrees.
    if (!await showDataConsentSheet(context, what: l10n.t('thisInvestment'))) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);

    final now = DateTime.now();
    final investment = Investment(
      id: widget.existing?.id ?? _store.newId('inv'),
      name: _name.text.trim(),
      type: _type,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      institution: _emptyOrNull(_institution),
      accountNumber: _emptyOrNull(_account),
      units: _showsUnits ? _parse(_units) : null,
      purchasePrice: _showsUnits ? _parse(_unitPrice) : null,
      investedAmount: _parse(_invested),
      currentValue: _parse(_current),
      purchaseDate: _purchaseDate,
      maturityDate: _type.hasMaturity ? _maturityDate : null,
      nominee: _emptyOrNull(_nominee),
      notes: _emptyOrNull(_notes),
      attachments: _attachments,
      isFavorite: widget.existing?.isFavorite ?? false,
    );

    if (_isEdit) {
      await _store.update(investment);
    } else {
      await _store.add(investment);
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (_isEdit) await showSuccessBurst(context, l10n.t('changesSaved'));
    if (!mounted) return;
    Navigator.of(context).pop(investment);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final currency = _currency;
    final symbol = currency.symbol;
    final invested = _impliedInvested;
    final current = _parse(_current) ?? invested;
    final profit = current - invested;
    final hasNumbers = invested > 0 || current > 0;

    final glass = divineGlassEnabled(context);
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
                  title: l10n
                      .t(_isEdit ? 'editInvestment' : 'addInvestment'),
                  subtitle: _isEdit
                      ? widget.existing!.name
                      : investmentTypeLabel(l10n, _type),
                ),
                Expanded(
                  child: ListView(
                    padding:
                        const EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 140),
                    children: [
                // ---- Instrument ----
                FadeSlideIn(
                  child: ModuleSection(
                    title: l10n.t('instrument'),
                    icon: _type.icon,
                    accent: _type.color,
                    children: [
                      ModulePickerField(
                        label: l10n.t('investmentType'),
                        value: investmentTypeLabel(l10n, _type),
                        icon: _type.icon,
                        accent: _type.color,
                        onTap: _pickType,
                      ),
                      ModuleField(
                        label: l10n.t('investmentName'),
                        controller: _name,
                        hint: l10n.t('investmentNameHint'),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? l10n.t('enterAName')
                            : null,
                      ),
                      ModuleField(
                        label: l10n.t('institutionBroker'),
                        controller: _institution,
                        hint: l10n.t('institutionBrokerHint'),
                        textCapitalization: TextCapitalization.words,
                      ),
                      ModuleField(
                        label: l10n.t('accountFolioNumber'),
                        controller: _account,
                        hint: l10n.t('onlyLast4DigitsShown'),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Amounts ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 50),
                  child: ModuleSection(
                    title: l10n.t('amounts'),
                    icon: Icons.payments_rounded,
                    accent: AppColors.success,
                    subtitle: l10n.t(_showsUnits
                        ? 'amountsUnitsSubtitle'
                        : 'amountsSubtitle'),
                    children: [
                      // Units only exist for unit-based instruments.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _showsUnits
                            ? Row(
                                children: [
                                  Expanded(
                                    child: ModuleField(
                                      label: l10n.t('units'),
                                      controller: _units,
                                      hint: '0',
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: ModuleField(
                                      label: l10n.t('pricePerUnit'),
                                      controller: _unitPrice,
                                      hint: '0',
                                      prefixText: '$symbol ',
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ModuleField(
                              label: l10n.t('investedAmount'),
                              controller: _invested,
                              hint: _showsUnits ? l10n.t('autoFromUnits') : '0',
                              prefixText: '$symbol ',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModuleField(
                              label: l10n.t('currentValue'),
                              controller: _current,
                              hint: '0',
                              prefixText: '$symbol ',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      // Live P&L - derived exactly the way the store does it.
                      if (hasNumbers)
                        _ProfitPreview(
                          invested: invested,
                          current: current,
                          profit: profit,
                          currency: currency,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Dates & nominee ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 100),
                  child: ModuleSection(
                    title: l10n.t('datesAndNominee'),
                    icon: Icons.event_rounded,
                    accent: const Color(0xFF4383EA),
                    children: [
                      ModulePickerField(
                        label: l10n.t('purchaseDate'),
                        value: _purchaseDate == null
                            ? null
                            : formatModuleDate(_purchaseDate!),
                        hint: l10n.t('selectADate'),
                        icon: Icons.event_rounded,
                        trailingIcon: Icons.calendar_month_rounded,
                        onTap: () => _pickDate(purchase: true),
                      ),
                      // Maturity only applies to instruments that mature.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _type.hasMaturity
                            ? ModulePickerField(
                                label: l10n.t('maturityDate'),
                                value: _maturityDate == null
                                    ? null
                                    : formatModuleDate(_maturityDate!),
                                hint: l10n.t('selectADate'),
                                icon: Icons.event_available_rounded,
                                trailingIcon: Icons.calendar_month_rounded,
                                onTap: () => _pickDate(purchase: false),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      ModuleField(
                        label: l10n.t('nominee'),
                        controller: _nominee,
                        textCapitalization: TextCapitalization.words,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Documents & notes ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 150),
                  child: ModuleSection(
                    title: l10n.t('documentsAndNotes'),
                    icon: Icons.folder_copy_rounded,
                    accent: const Color(0xFF0891B2),
                    trailing: ModuleIconButton(
                      icon: Icons.attach_file_rounded,
                      size: 34,
                      tooltip: l10n.t('attach'),
                      onTap: _attach,
                    ),
                    children: [
                      if (_attachments.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            l10n.t('attachStatementOptional'),
                            style: AppText.caption
                                .copyWith(color: palette.textFaint),
                          ),
                        )
                      else
                        for (var i = 0; i < _attachments.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
                              decoration: BoxDecoration(
                                color: palette.surfaceVariant,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.chip),
                                border: Border.all(color: palette.border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.description_rounded,
                                      size: 17, color: Color(0xFF0891B2)),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      _attachments[i].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.body
                                          .copyWith(color: palette.textPrimary),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(() {
                                      _attachments = [..._attachments]
                                        ..removeAt(i);
                                    }),
                                    icon: const Icon(Icons.close_rounded,
                                        size: 17),
                                    color: palette.textFaint,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ModuleField(
                        label: l10n.t('notes'),
                        controller: _notes,
                        hint: l10n.t('investmentNotesHint'),
                        maxLines: 3,
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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: SafeArea(
          top: false,
          child: GradientButton(
            label: l10n.t(_isEdit ? 'saveChanges' : 'addInvestment'),
            busy: _saving,
            onTap: _save,
          ),
        ),
      ),
    );
  }
}

/// The live profit/loss strip under the amount fields.
class _ProfitPreview extends StatelessWidget {
  const _ProfitPreview({
    required this.invested,
    required this.current,
    required this.profit,
    required this.currency,
  });

  final double invested;
  final double current;
  final double profit;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final up = profit >= 0;
    final color = up ? AppColors.success : AppColors.critical;
    final pct = invested <= 0 ? null : (profit / invested) * 100;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.t(up ? 'unrealisedGain' : 'unrealisedLoss'),
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          ),
          Text(
            pct == null
                ? money(profit.abs(), currency)
                : '${up ? '+' : '-'}${money(profit.abs(), currency)}  (${pct.abs().toStringAsFixed(1)}%)',
            style: AppText.subtitle.copyWith(color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
