import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/perf/image_decode.dart';
import '../../l10n/app_localizations.dart';
import '../../models/area_unit.dart';
import '../../models/currency.dart';
import '../../models/property_models.dart';
import '../../services/app_settings.dart';
import '../../services/property_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/wallet_modules/module_kit.dart';
import 'property_form_screen.dart';

/// The property dashboard - everything recorded about one property, organised
/// into the same sections the form captured it in.
///
/// Reads live from [PropertyStore], so an edit made here (or a favourite
/// toggled from the list) is reflected the moment it happens. Sections with
/// nothing in them are omitted rather than shown empty.
class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  final _store = PropertyStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Currency get _currency =>
      Currencies.byCode(AppSettings.instance.currency.value);

  Future<void> _edit(Property p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PropertyFormScreen(existing: p)),
    );
  }

  Future<void> _delete(Property p) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.t('deletePropertyQ'),
      message: l10n.t('deletePropertyBody').replaceAll('{name}', p.name),
      confirmLabel: l10n.t('delete'),
    );
    if (!ok || !mounted) return;
    await _store.remove(p.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  bool _isValidGoogleMapsUrl(String url) {
    final clean = url.trim();
    return clean.startsWith('https://maps.app.goo.gl/') ||
        clean.startsWith('https://maps.google.com/') ||
        clean.startsWith('https://www.google.com/maps/');
  }

  Future<void> _openMaps(String url) async {
    final clean = url.trim();
    if (!_isValidGoogleMapsUrl(clean)) {
      showModuleToast(context, AppLocalizations.of(context).t('invalidMapsLink'),
          error: true);
      return;
    }
    final uri = Uri.parse(clean);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        if (!mounted) return;
        showModuleToast(
            context, AppLocalizations.of(context).t('couldNotOpenMapsLink'),
            error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final p = _store.byId(widget.propertyId);

    // The property can vanish underneath us (deleted from another screen).
    if (p == null) {
      return Scaffold(
        backgroundColor: palette.bg,
        body: SafeArea(
          child: Center(
            child: Text(l10n.t('propertyNoLongerAvailable'),
                style: AppText.body.copyWith(color: palette.textSecondary)),
          ),
        ),
      );
    }

    final currency = _currency;
    final appreciation = p.appreciation;
    final gain = p.gain;

    final glass = divineGlassEnabled(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        sky: glass,
        child: SafeArea(
          // Frosted ModuleHeader paints under the status bar itself.
          top: !glass,
          bottom: false,
          child: Column(
            children: [
              ModuleHeader(
                title: p.name,
                subtitle: p.locationLine.isEmpty
                    ? p.type.localizedLabel(l10n)
                    : '${p.type.localizedLabel(l10n)} · ${p.locationLine}',
                actions: [
                  ModuleIconButton(
                    icon: p.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: p.isFavorite ? AppColors.warning : null,
                    tooltip: l10n.t('favorite'),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _store.toggleFavorite(p.id);
                    },
                  ),
                  ModuleIconButton(
                    icon: Icons.edit_rounded,
                    tooltip: l10n.t('edit'),
                    onTap: () => _edit(p),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, AppSpacing.md, 16, 40),
                  children: [
              // ---- Hero: photo + status ----
              FadeSlideIn(child: _HeroCard(property: p)),
              const SizedBox(height: AppSpacing.md),

              // ---- Valuation ----
              FadeSlideIn(
                delay: const Duration(milliseconds: 40),
                child: _ValuationCard(
                  l10n: l10n,
                  property: p,
                  currency: currency,
                  appreciation: appreciation,
                  gain: gain,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ---- Quick facts ----
              FadeSlideIn(
                delay: const Duration(milliseconds: 70),
                child: Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        value: p.area == null
                            ? '—'
                            : '${_trim(p.area!)} ${p.areaUnit.shortLabel}',
                        label: l10n.t('area'),
                        icon: Icons.square_foot_rounded,
                        accent: const Color(0xFF0D9488),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatTile(
                        value: p.rentalIncome == null
                            ? '—'
                            : moneyWords(p.rentalIncome!, currency),
                        label: l10n.t('rentPerMonth'),
                        icon: Icons.payments_rounded,
                        accent: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatTile(
                        value: p.annualCost > 0
                            ? moneyWords(p.annualCost, currency)
                            : '—',
                        label: l10n.t('costPerYear'),
                        icon: Icons.receipt_long_rounded,
                        accent: AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ---- Location ----
              if (_hasLocation(p)) ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 100),
                  child: ModuleSection(
                    title: l10n.t('location'),
                    icon: Icons.place_rounded,
                    accent: AppColors.aquaPrimary,
                    children: [
                      DetailRow(label: l10n.t('address'), value: p.address),
                      DetailRow(label: l10n.t('city'), value: p.city),
                      DetailRow(label: l10n.t('stateRegion'), value: p.state),
                      DetailRow(label: l10n.t('country'), value: p.country),
                      DetailRow(label: l10n.t('pinCode'), value: p.pinCode),
                      DetailRow(
                        label: l10n.t('maps'),
                        value: (p.mapsUrl ?? '').trim().isEmpty
                            ? l10n.t('noLocationAdded')
                            : p.mapsUrl,
                        copyable: (p.mapsUrl ?? '').trim().isNotEmpty,
                        copyMessage: l10n.t('locationLinkCopied'),
                        onTap: (p.mapsUrl ?? '').trim().isNotEmpty
                            ? () => _openMaps(p.mapsUrl!)
                            : null,
                        valueColor: (p.mapsUrl ?? '').trim().isNotEmpty
                            ? AppColors.primaryGreen
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ElevatedButton.icon(
                        onPressed: (p.mapsUrl ?? '').trim().isNotEmpty
                            ? () => _openMaps(p.mapsUrl!)
                            : null,
                        icon: const Text('📍', style: TextStyle(fontSize: 16)),
                        label: Text(
                          l10n.t('openInGoogleMaps'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              palette.border.withValues(alpha: 0.3),
                          disabledForegroundColor: palette.textFaint,
                          minimumSize: const Size.fromHeight(46),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.button),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ---- Ownership ----
              if (_hasOwnership(p)) ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 130),
                  child: ModuleSection(
                    title: l10n.t('ownership'),
                    icon: Icons.badge_rounded,
                    accent: const Color(0xFF9B6DE0),
                    children: [
                      DetailRow(label: l10n.t('owner'), value: p.ownerName),
                      DetailRow(
                        label: l10n.t('ownershipShare'),
                        value: p.ownershipPercent == null
                            ? null
                            : '${_trim(p.ownershipPercent!)}%',
                      ),
                      DetailRow(
                        label: l10n.t('registrationNo'),
                        value: p.registrationNumber,
                        copyable: true,
                        monospace: true,
                      ),
                      DetailRow(
                        label: l10n.t('registeredOn'),
                        value: p.registrationDate == null
                            ? null
                            : formatModuleDate(p.registrationDate!),
                      ),
                      for (final c in p.coOwners)
                        DetailRow(
                          label: c.relationship == null
                              ? l10n.t('coOwner')
                              : '${l10n.t('coOwner')} · ${c.relationship}',
                          value: c.sharePercent == null
                              ? c.name
                              : '${c.name} (${_trim(c.sharePercent!)}%)',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ---- Legal ----
              if (_hasLegal(p)) ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 160),
                  child: ModuleSection(
                    title: l10n.t('legalDetails'),
                    icon: Icons.gavel_rounded,
                    accent: const Color(0xFFF5704A),
                    children: [
                      DetailRow(label: l10n.t('nominee'), value: p.nomineeName),
                      DetailRow(
                          label: l10n.t('relationship'),
                          value: p.nomineeRelationship),
                      DetailRow(
                        label: l10n.t('legalHeirs'),
                        value:
                            p.legalHeirs.isEmpty ? null : p.legalHeirs.join(', '),
                      ),
                      DetailRow(label: l10n.t('will'), value: p.willDetails),
                      DetailRow(
                        label: l10n.t('propertyTaxId'),
                        value: p.taxId,
                        copyable: true,
                        monospace: true,
                      ),
                      DetailRow(
                          label: l10n.t('encumbrance'), value: p.encumbrance),
                      if (p.hasLoan) ...[
                        DetailRow(
                            label: l10n.t('loanProvider'),
                            value: p.loanProvider),
                        DetailRow(
                          label: l10n.t('outstandingLoan'),
                          value: p.outstandingLoan == null
                              ? null
                              : money(p.outstandingLoan!, currency),
                          valueColor: AppColors.critical,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ---- Financial ----
              if (_hasFinancial(p)) ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 190),
                  child: ModuleSection(
                    title: l10n.t('financial'),
                    icon: Icons.payments_rounded,
                    accent: AppColors.success,
                    children: [
                      DetailRow(
                        label: l10n.t('emiPerMonth'),
                        value: p.emi == null ? null : money(p.emi!, currency),
                      ),
                      DetailRow(
                        label: l10n.t('rentalIncomePerMonth'),
                        value: p.rentalIncome == null
                            ? null
                            : money(p.rentalIncome!, currency),
                        valueColor: AppColors.success,
                      ),
                      DetailRow(
                        label: l10n.t('annualPropertyTax'),
                        value: p.annualTax == null
                            ? null
                            : money(p.annualTax!, currency),
                      ),
                      DetailRow(
                        label: l10n.t('maintenancePerYear'),
                        value: p.maintenanceCharges == null
                            ? null
                            : money(p.maintenanceCharges!, currency),
                      ),
                      DetailRow(
                        label: l10n.t('otherExpensesPerYear'),
                        value: p.otherExpenses == null
                            ? null
                            : money(p.otherExpenses!, currency),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ---- Documents ----
              if (p.attachments.isNotEmpty) ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 220),
                  child: ModuleSection(
                    title: l10n.t('documents'),
                    icon: Icons.folder_copy_rounded,
                    accent: const Color(0xFF0891B2),
                    subtitle: l10n
                        .t('nAttached')
                        .replaceAll('{n}', '${p.attachments.length}'),
                    children: [
                      for (final a in p.attachments)
                        DetailRow(
                          label: a.kind.localizedLabel(l10n),
                          value: a.name,
                          icon: a.kind.icon,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ---- Notes ----
              if ((p.notes ?? '').isNotEmpty ||
                  (p.reminderNote ?? '').isNotEmpty) ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 250),
                  child: ModuleSection(
                    title: l10n.t('notes'),
                    icon: Icons.sticky_note_2_rounded,
                    accent: const Color(0xFF64748B),
                    children: [
                      if ((p.notes ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            p.notes!,
                            style: AppText.body.copyWith(
                              color: palette.textPrimary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      if ((p.reminderNote ?? '').isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                            border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.notifications_active_rounded,
                                  size: 17, color: AppColors.warning),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  p.reminderNote!,
                                  style: AppText.caption
                                      .copyWith(color: palette.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ---- Danger zone ----
              FadeSlideIn(
                delay: const Duration(milliseconds: 280),
                child: TextButton.icon(
                  onPressed: () => _delete(p),
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  label: Text(l10n.t('deleteProperty')),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.critical,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _hasLocation(Property p) => [
        p.address,
        p.city,
        p.state,
        p.country,
        p.pinCode,
        p.mapsUrl
      ].any((v) => (v ?? '').isNotEmpty);

  static bool _hasOwnership(Property p) =>
      (p.ownerName ?? '').isNotEmpty ||
      (p.registrationNumber ?? '').isNotEmpty ||
      p.ownershipPercent != null ||
      p.registrationDate != null ||
      p.coOwners.isNotEmpty;

  static bool _hasLegal(Property p) =>
      (p.nomineeName ?? '').isNotEmpty ||
      (p.willDetails ?? '').isNotEmpty ||
      (p.taxId ?? '').isNotEmpty ||
      (p.encumbrance ?? '').isNotEmpty ||
      p.legalHeirs.isNotEmpty ||
      p.hasLoan;

  static bool _hasFinancial(Property p) =>
      p.emi != null ||
      p.annualTax != null ||
      p.maintenanceCharges != null ||
      p.rentalIncome != null ||
      p.otherExpenses != null;

  /// Drops a pointless ".0" from whole numbers.
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// The photo hero with the status pill and type badge over it.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final path = property.imagePath;
    // No `existsSync()` here — that was a blocking disk stat on the UI thread
    // every build. `errorBuilder` already renders the same fallback when the
    // file has been moved or deleted.
    final has = path != null && path.isNotEmpty;
    final accent = property.status.color;
    return Container(
      height: 190,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (has)
            Image.file(
              File(path),
              fit: BoxFit.cover,
              // Bound the decode to the 190px band this actually paints into.
              // Passing only the height keeps the aspect ratio intact.
              cacheHeight: context.decodeWidthFor(190),
              errorBuilder: (_, _, _) => _fallback(context, accent),
            )
          else
            _fallback(context, accent),
          // A bottom scrim so the pills stay legible over any photo.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 84,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Row(
              children: [
                _GlassPill(
                  icon: property.type.icon,
                  label: property.type.localizedLabel(l10n),
                ),
                const SizedBox(width: 8),
                _GlassPill(
                  icon: property.status.icon,
                  label: property.status.localizedLabel(l10n),
                  accent: accent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback(BuildContext context, Color accent) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.34),
              accent.withValues(alpha: 0.12),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          property.type.icon,
          size: 54,
          color: Colors.white.withValues(alpha: 0.92),
        ),
      );
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.icon, required this.label, this.accent});

  final IconData icon;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent ?? AppColors.textDark),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.label.copyWith(color: AppColors.textDark),
          ),
        ],
      ),
    );
  }
}

/// Purchase price → current value, with the gain rendered as a progress bar so
/// the appreciation is felt, not just read.
class _ValuationCard extends StatelessWidget {
  const _ValuationCard({
    required this.l10n,
    required this.property,
    required this.currency,
    required this.appreciation,
    required this.gain,
  });

  final AppLocalizations l10n;
  final Property property;
  final Currency currency;
  final double? appreciation;
  final double? gain;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final up = (appreciation ?? 0) >= 0;
    final color = up ? AppColors.success : AppColors.critical;
    // The bar shows the purchase price as a share of the current value, so a
    // gain leaves visible headroom. Capped at 1 for a loss.
    final ratio = (property.purchasePrice == null ||
            property.currentValue == null ||
            property.currentValue! <= 0)
        ? null
        : (property.purchasePrice! / property.currentValue!).clamp(0.0, 1.0);

    return ModuleSection(
      title: l10n.t('valuation'),
      icon: Icons.trending_up_rounded,
      accent: up ? AppColors.success : AppColors.critical,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.t('currentValue'),
                      style: AppText.caption
                          .copyWith(color: palette.textSecondary)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      property.currentValue == null
                          ? l10n.t('notSet')
                          : money(property.currentValue!, currency),
                      style: AppText.headline.copyWith(
                        color: property.currentValue == null
                            ? palette.textFaint
                            : palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (appreciation != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      up
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 13,
                      color: color,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${(appreciation!.abs() * 100).toStringAsFixed(1)}%',
                      style: AppText.label.copyWith(color: color),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (ratio != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Stack(
                children: [
                  Container(height: 8, color: color.withValues(alpha: 0.18)),
                  FractionallySizedBox(
                    widthFactor: v,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        DetailRow(
          label: l10n.t('purchasePrice'),
          value: property.purchasePrice == null
              ? null
              : money(property.purchasePrice!, currency),
        ),
        DetailRow(
          label: l10n.t('purchasedOn'),
          value: property.purchaseDate == null
              ? null
              : formatModuleDate(property.purchaseDate!),
        ),
        DetailRow(
          label: up ? l10n.t('gain') : l10n.t('loss'),
          value: gain == null ? null : money(gain!.abs(), currency),
          valueColor: color,
        ),
      ],
    );
  }
}
