import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/area_unit.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/ino_options_sheet.dart';

/// A shared bottom-sheet picker for [AreaUnit]s, used by the quick converter and
/// the area-input section. Returns the chosen unit, or null if dismissed.
Future<AreaUnit?> showAreaUnitPicker(
  BuildContext context, {
  required AreaUnit selected,
  String? title,
}) {
  final palette = AppPalette.of(context);
  title ??= AppLocalizations.of(context).t('selectUnit');
  return showInoOptionsSheet<AreaUnit>(
    context: context,
    backgroundColor: palette.surface,
    maxHeightFraction: 0.7,
    builder: (context, _) => InoOptionsSheetBody(
      title: title!,
      titleStyle: AppText.title.copyWith(color: palette.textPrimary),
      children: [
        for (final u in AreaUnit.values)
          ListTile(
            onTap: () => Navigator.of(context).pop(u),
            tileColor: u == selected ? AppColors.tealFoam : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              side: BorderSide(
                color: u == selected ? AppColors.tealPale : Colors.transparent,
              ),
            ),
            title: Text(
              u.label,
              style: AppText.subtitle.copyWith(
                color: palette.textPrimary,
                fontWeight: u == selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            subtitle: Text(
              u.alias == null
                  ? u.shortLabel
                  : '${u.shortLabel} · ${u.alias}',
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
            trailing: u == selected
                ? Icon(Icons.check_circle_rounded,
                    color: AppColors.primaryGreen, size: 22)
                : null,
          ),
      ],
    ),
  );
}
