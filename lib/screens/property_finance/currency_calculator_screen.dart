import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/currency.dart';
import '../../services/app_settings.dart';
import '../../services/currency_rate_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/property_finance/calc_widgets.dart';
import '../../widgets/property_finance/currency_selector.dart';
import '../../widgets/common/ino_loader.dart';

/// Currency Converter - enter an amount in one currency and read it in another
/// (rupee → dollar → pound → …), across every currency in [Currencies.all].
///
/// Three parts, in the order they're used:
///  1. **the pair** - From / To pills (searchable pickers) with a swap button;
///  2. **the rate** - prefilled from [CurrencyRateService] and EDITABLE, because
///     the shipped table is indicative rather than a live feed;
///  3. **every currency** - the same amount converted into all the others, with
///     a Copy All, mirroring the Area Converter's "all units" summary.
class CurrencyCalculatorScreen extends StatefulWidget {
  const CurrencyCalculatorScreen({super.key});

  @override
  State<CurrencyCalculatorScreen> createState() =>
      _CurrencyCalculatorScreenState();
}

class _CurrencyCalculatorScreenState extends State<CurrencyCalculatorScreen> {
  final _svc = CurrencyRateService.instance;

  final _amount = TextEditingController();

  /// The rate field: prefilled from the service, editable so the user can enter
  /// today's exact rate. Reset whenever the pair changes.
  final _rate = TextEditingController();

  /// True once the user has typed in the rate field - their number then survives
  /// a live-rate refresh, and the result is labelled as their rate.
  bool _rateTyped = false;

  /// True while the live fetch is in flight (first open only).
  bool _loadingRates = false;

  /// Start from the user's app-wide currency (usually INR) into USD - the pair
  /// people reach for first. If they already work in USD, offer EUR instead.
  late Currency _from = Currencies.byCode(AppSettings.instance.currency.value);
  late Currency _to = Currencies.byCode(_from.code == 'USD' ? 'EUR' : 'USD');

  @override
  void initState() {
    super.initState();
    _resetRate();
    _loadLiveRates();
  }

  /// Refreshes the ECB rates once per visit. Failure is silent - the shipped
  /// baseline already gives a working converter.
  Future<void> _loadLiveRates() async {
    setState(() => _loadingRates = true);
    final ok = await _svc.fetch();
    if (!mounted) return;
    setState(() {
      _loadingRates = false;
      // Live rates supersede the prefilled baseline, unless the user has
      // already typed a rate of their own.
      if (ok && !_rateTyped) _resetRate();
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    super.dispose();
  }

  /// Puts the service's rate for the current pair back into the field (used on
  /// first build, on every pair change, when live rates land, and by "reset").
  void _resetRate() {
    _rate.text = _svc.formatRate(_svc.rate(_from, _to));
    _rateTyped = false;
  }

  double get _value => double.tryParse(_amount.text.trim()) ?? 0;

  /// The rate actually used: what's in the field, falling back to the service's
  /// rate when it's been emptied or is nonsense.
  double get _effectiveRate {
    final typed = double.tryParse(_rate.text.trim()) ?? 0;
    return typed > 0 ? typed : _svc.rate(_from, _to);
  }

  /// True while the user's own number is in play - the breakdown then says the
  /// result uses their rate rather than a fetched or shipped one.
  bool get _rateEdited =>
      _rateTyped && (_effectiveRate - _svc.rate(_from, _to)).abs() > 1e-12;

  Future<void> _pick({required bool from}) async {
    final picked = await showCurrencyPicker(
      context,
      selected: from ? _from : _to,
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        // Picking the currency that's already on the other side swaps instead
        // of collapsing the pair into "USD → USD".
        if (picked.code == _to.code) _to = _from;
        _from = picked;
      } else {
        if (picked.code == _from.code) _from = _to;
        _to = picked;
      }
      _resetRate();
    });
  }

  void _swap() {
    setState(() {
      final f = _from;
      _from = _to;
      _to = f;
      _resetRate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = _value;
    final valid = value > 0 && _effectiveRate > 0;
    final converted = _svc.convert(
      value,
      _from,
      _to,
      rateOverride: _rateEdited ? _effectiveRate : null,
    );

    return CalculatorScaffold(
      title: l10n.t('currencyCalculator'),
      subtitle: l10n.t('currencySubtitle'),
      children: [
        CalcInputCard(
          title: l10n.t('convertAmount'),
          children: [
            CalcField(
              label: l10n.t('amount'),
              controller: _amount,
              prefix: _from.symbol,
              hint: 'e.g. 1000',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            _PairRow(
              from: _from,
              to: _to,
              onPickFrom: () => _pick(from: true),
              onPickTo: () => _pick(from: false),
              onSwap: _swap,
            ),
            const SizedBox(height: AppSpacing.sm),
            CalcField(
              label:
                  '${l10n.t('exchangeRate')} · 1 ${_from.code} = ? '
                  '${_to.code}',
              controller: _rate,
              hint: _svc.formatRate(_svc.rate(_from, _to)),
              onChanged: () => setState(() => _rateTyped = true),
            ),
            const SizedBox(height: AppSpacing.xs),
            _RateNote(
              edited: _rateEdited,
              live: _svc.isLivePair(_from, _to),
              loading: _loadingRates,
              onReset: () => setState(_resetRate),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!valid)
          CalcHint(message: l10n.t('currencyHint'))
        else ...[
          HeroResultCard(
            label: '${_svc.format(value, _from)} ${_from.code} → ${_to.code}',
            value: _svc.format(converted, _to),
            copyText: _svc.format(converted, _to),
            gradient:  LinearGradient(
              colors: [AppColors.lightBlue, AppColors.primaryGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ResultBreakdownCard(
            rows: [
              ResultRow(
                label: l10n.t('exchangeRate'),
                value: _svc.rateLine(
                  _from,
                  _to,
                  rateOverride: _rateEdited ? _effectiveRate : null,
                ),
              ),
              ResultRow(
                label: l10n.t('inverseRate'),
                value:
                    '1 ${_to.code} = '
                    '${_svc.formatRate(_effectiveRate == 0 ? 0 : 1 / _effectiveRate)} '
                    '${_from.code}',
              ),
              ResultRow(
                label: l10n.t('rateSource'),
                value: _rateEdited
                    ? l10n.t('yourRate')
                    : _svc.isLivePair(_from, _to)
                    ? l10n.t('liveRate')
                    : l10n.t('indicativeRate'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // The picked pair is the hero above; listing it again from the rate
          // table would contradict it whenever the user typed their own rate.
          _AllCurrenciesCard(amount: value, from: _from, exclude: _to),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// From → To pair
// ---------------------------------------------------------------------------

/// The From / swap / To row. Each side opens the same searchable currency sheet
/// used by the other calculators ([showCurrencyPicker]), so all 60+ currencies
/// are reachable and searchable by code, name or symbol.
class _PairRow extends StatelessWidget {
  const _PairRow({
    required this.from,
    required this.to,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onSwap,
  });

  final Currency from;
  final Currency to;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _CurrencyField(
            label: l10n.t('from'),
            currency: from,
            onTap: onPickFrom,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: PressableScale(
            pressedScale: 0.88,
            child: Semantics(
              button: true,
              label: l10n.t('swapCurrencies'),
              child: Material(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onSwap,
                  child:  SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      color: AppColors.primaryGreen,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _CurrencyField(
            label: l10n.t('to'),
            currency: to,
            onTap: onPickTo,
          ),
        ),
      ],
    );
  }
}

/// One side of the pair: a labelled tap target showing flag + code + name.
class _CurrencyField extends StatelessWidget {
  const _CurrencyField({
    required this.label,
    required this.currency,
    required this.onTap,
  });

  final String label;
  final Currency currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.label.copyWith(
            color: palette.textFaint,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 6),
        PressableScale(
          pressedScale: 0.98,
          child: Material(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Text(currency.flag, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        currency.code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 19,
                      color: palette.textFaint,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The honest footnote under the rate field: the shipped rates are indicative,
/// and once the user types their own the note becomes a way back to the table.
class _RateNote extends StatelessWidget {
  const _RateNote({
    required this.edited,
    required this.live,
    required this.loading,
    required this.onReset,
  });

  final bool edited;

  /// True when both sides of the pair came from the live ECB feed.
  final bool live;

  /// True while the first fetch of the visit is still in flight.
  final bool loading;

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    // Three honest states: the user's own rate, a live rate, or the baseline.
    final (IconData icon, String message, Color color) = edited
        ? (Icons.edit_rounded, l10n.t('usingYourRate'), palette.textFaint)
        : live
        ? (Icons.bolt_rounded, l10n.t('ratesLive'), AppColors.primaryGreen)
        : (
            Icons.info_outline_rounded,
            l10n.t('ratesIndicative'),
            palette.textFaint,
          );

    return Row(
      children: [
        if (loading)
          InoLoader(size: 12, color: palette.textFaint)
        else
          Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            loading ? l10n.t('fetchingRates') : message,
            style: AppText.label.copyWith(
              color: loading ? palette.textFaint : color,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
        if (edited)
          TextButton(
            onPressed: onReset,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              l10n.t('resetRate'),
              style: AppText.label.copyWith(
                color: AppColors.primaryGreen,
                fontSize: 11.5,
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// All currencies
// ---------------------------------------------------------------------------

/// The amount converted into EVERY other currency, in registry order, with a
/// Copy All. Collapsed to the majors by default so the page stays scannable;
/// "show all" reveals the full list.
class _AllCurrenciesCard extends StatefulWidget {
  const _AllCurrenciesCard({
    required this.amount,
    required this.from,
    required this.exclude,
  });

  final double amount;
  final Currency from;

  /// The pair's target currency - left out because the hero card above already
  /// shows it (and at the user's rate, which this table-driven list can't know).
  final Currency exclude;

  @override
  State<_AllCurrenciesCard> createState() => _AllCurrenciesCardState();
}

class _AllCurrenciesCardState extends State<_AllCurrenciesCard> {
  /// How many rows to show before "show all" is tapped.
  static const _collapsedCount = 8;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final svc = CurrencyRateService.instance;
    final all = svc.convertToAll(
      widget.amount,
      widget.from,
      excludeCode: widget.exclude.code,
    );
    final shown = _expanded ? all : all.take(_collapsedCount).toList();

    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.internal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${l10n.t('allCurrencies')} (${all.length})',
                  style: AppText.title.copyWith(color: palette.textPrimary),
                ),
              ),
              PressableScale(
                pressedScale: 0.92,
                child: Material(
                  color: AppColors.primaryGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => copyToClipboard(
                      context,
                      svc.asCopyText(
                        widget.amount,
                        widget.from,
                        excludeCode: widget.exclude.code,
                      ),
                      message: l10n.t('copied'),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                           Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: AppColors.primaryGreen,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            l10n.t('copyAll'),
                            style: AppText.label.copyWith(
                              color: AppColors.primaryGreen,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) Divider(height: 1, color: palette.border),
            _CurrencyRow(conversion: shown[i]),
          ],
          if (all.length > _collapsedCount)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? l10n.t('showLess')
                      : '${l10n.t('showAll')} (${all.length - _collapsedCount})',
                  style: AppText.subtitle.copyWith(
                    color: AppColors.primaryGreen,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One "🇺🇸 USD · US Dollar → $11.56" line, tappable to copy just that value.
class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({required this.conversion});

  final CurrencyConversion conversion;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final c = conversion.currency;
    return InkWell(
      onTap: () => copyToClipboard(context, conversion.display),
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Text(c.flag, style: const TextStyle(fontSize: 17)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.code,
                    style: AppText.subtitle.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(
                      color: palette.textFaint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              conversion.display,
              style: AppText.subtitle.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
