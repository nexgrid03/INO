import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/currency.dart';
import '../../services/app_settings.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// The compact currency pill shown in every calculator header: flag + ISO code
/// + chevron. Tapping opens the searchable [showCurrencyPicker] sheet and
/// persists the choice app-wide via [AppSettings.currency], so all finance
/// tools stay in the same currency.
class CurrencySelector extends StatelessWidget {
  const CurrencySelector({super.key, required this.onChanged});

  /// Called after a new currency is picked and persisted, so the host screen
  /// can rebuild its amounts.
  final ValueChanged<Currency> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final current = Currencies.byCode(AppSettings.instance.currency.value);
    return PressableScale(
      pressedScale: 0.95,
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final picked = await showCurrencyPicker(context, selected: current);
            if (picked == null) return;
            await AppSettings.instance.setCurrency(picked.code);
            onChanged(picked);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(current.flag, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text(
                  current.code,
                  style: AppText.subtitle.copyWith(
                    color: palette.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 17, color: palette.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A searchable bottom-sheet picker over [Currencies.all]. Returns the chosen
/// currency, or null if dismissed.
Future<Currency?> showCurrencyPicker(
  BuildContext context, {
  required Currency selected,
}) {
  final palette = AppPalette.of(context);
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<Currency>(
    context: context,
    backgroundColor: palette.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (context) => _CurrencySheet(
      selected: selected,
      palette: palette,
      title: l10n.t('selectCurrency'),
      searchHint: l10n.t('searchCurrency'),
    ),
  );
}

class _CurrencySheet extends StatefulWidget {
  const _CurrencySheet({
    required this.selected,
    required this.palette,
    required this.title,
    required this.searchHint,
  });

  final Currency selected;
  final AppPalette palette;
  final String title;
  final String searchHint;

  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? Currencies.all
        : Currencies.all
            .where((c) =>
                c.code.toLowerCase().contains(q) ||
                c.name.toLowerCase().contains(q) ||
                c.symbol.toLowerCase().contains(q))
            .toList();

    return SafeArea(
      child: Padding(
        // Keep the list clear of the keyboard while searching.
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
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
              Text(widget.title,
                  style: AppText.title.copyWith(color: palette.textPrimary)),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  style: AppText.body.copyWith(color: palette.textPrimary),
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    hintStyle: AppText.body.copyWith(color: palette.textFaint),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 20, color: palette.textFaint),
                    filled: true,
                    fillColor: palette.surfaceVariant,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      borderSide: const BorderSide(
                          color: AppColors.primaryGreen, width: 1.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                      AppSpacing.xs, AppSpacing.md, AppSpacing.md),
                  itemCount: matches.length,
                  itemBuilder: (context, i) {
                    final c = matches[i];
                    final isSelected = c.code == widget.selected.code;
                    return ListTile(
                      onTap: () => Navigator.of(context).pop(c),
                      leading:
                          Text(c.flag, style: const TextStyle(fontSize: 22)),
                      title: Text(
                        '${c.code} · ${c.name}',
                        style: AppText.subtitle.copyWith(
                          color: palette.textPrimary,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        c.symbol,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppColors.primaryGreen, size: 22)
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
