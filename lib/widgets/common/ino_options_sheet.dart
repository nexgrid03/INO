import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// Scrollable modal bottom sheet for option lists (themes, language, etc.).
///
/// Default [showModalBottomSheet] caps height at ~half the screen — a tall
/// list overflows with yellow/black stripes and hides trailing options. This
/// helper allows up to [maxHeightFraction] of the screen and scrolls the rest.
///
/// Always uses a single chrome owner: theme/modal surface + one [InoSheetGrip]
/// in content (Material drag handle is disabled).
Future<T?> showInoOptionsSheet<T>({
  required BuildContext context,
  required Color backgroundColor,
  required Widget Function(BuildContext context, ScrollController? scroll) builder,
  double maxHeightFraction = 0.85,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    isScrollControlled: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.large),
      ),
    ),
    builder: (context) {
      final maxH = MediaQuery.sizeOf(context).height * maxHeightFraction;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: builder(context, null),
        ),
      );
    },
  );
}

/// Simple label-list picker with optional icons/colors and a selected check.
/// Returns the chosen index, or null when dismissed.
Future<int?> showInoOptionPicker(
  BuildContext context, {
  required String title,
  required List<String> labels,
  List<IconData>? icons,
  List<Color>? colors,
  int? selectedIndex,
  double maxHeightFraction = 0.7,
}) {
  final palette = AppPalette.of(context);
  return showInoOptionsSheet<int>(
    context: context,
    backgroundColor: palette.surface,
    maxHeightFraction: maxHeightFraction,
    builder: (context, _) => InoOptionsSheetBody(
      title: title,
      titleStyle: AppText.title.copyWith(color: palette.textPrimary),
      children: [
        for (var i = 0; i < labels.length; i++)
          ListTile(
            leading: icons == null
                ? null
                : Icon(
                    icons[i % icons.length],
                    color: colors == null
                        ? AppColors.primaryGreen
                        : colors[i % colors.length],
                    size: 21,
                  ),
            title: Text(
              labels[i],
              style: AppText.body.copyWith(
                color: palette.textPrimary,
                fontWeight:
                    i == selectedIndex ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: i == selectedIndex
                ? Icon(Icons.check_rounded, color: AppColors.primaryGreen)
                : null,
            onTap: () => Navigator.of(context).pop(i),
          ),
      ],
    ),
  );
}

/// Standard grip + title + scrollable [children] used by Profile pickers.
class InoOptionsSheetBody extends StatelessWidget {
  const InoOptionsSheetBody({
    super.key,
    required this.title,
    required this.children,
    this.titleStyle,
  });

  final String title;
  final List<Widget> children;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.sm),
        const InoSheetGrip(),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          style: titleStyle ?? AppText.title,
        ),
        const SizedBox(height: AppSpacing.xs),
        Flexible(
          child: ClipRect(
            child: ListView(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              clipBehavior: Clip.hardEdge,
              children: [
                ...children,
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared drag handle for bottom sheets.
class InoSheetGrip extends StatelessWidget {
  const InoSheetGrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppPalette.of(context).border,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}
