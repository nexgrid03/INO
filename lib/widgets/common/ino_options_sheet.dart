import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// Scrollable modal bottom sheet for option lists (themes, language, etc.).
///
/// Default [showModalBottomSheet] caps height at ~half the screen — a tall
/// list overflows with yellow/black stripes and hides trailing options. This
/// helper allows up to [maxHeightFraction] of the screen and scrolls the rest.
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
          child: ListView(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            children: [
              ...children,
              const SizedBox(height: AppSpacing.sm),
            ],
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
