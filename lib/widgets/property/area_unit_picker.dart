import 'package:flutter/material.dart';

import '../../models/area_unit.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// A shared bottom-sheet picker for [AreaUnit]s, used by the quick converter and
/// the area-input section. Returns the chosen unit, or null if dismissed.
Future<AreaUnit?> showAreaUnitPicker(
  BuildContext context, {
  required AreaUnit selected,
  String title = 'Select Unit',
}) {
  final palette = AppPalette.of(context);
  return showModalBottomSheet<AreaUnit>(
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
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
              children: [
                for (final u in AreaUnit.values)
                  ListTile(
                    onTap: () => Navigator.of(context).pop(u),
                    title: Text(
                      u.label,
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontWeight:
                            u == selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      u.alias == null
                          ? u.shortLabel
                          : '${u.shortLabel} · ${u.alias}',
                      style:
                          AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                    trailing: u == selected
                        ? const Icon(Icons.check_circle_rounded,
                            color: AppColors.primaryGreen, size: 22)
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
