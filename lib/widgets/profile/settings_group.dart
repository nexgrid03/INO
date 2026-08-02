import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';

/// A grouped inset settings list - the core primitive of the redesigned Profile
/// page (the Apple Settings / Google Account pattern).
///
/// Frosted glass surface across themes.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children, this.caption});

  /// Optional section label (e.g. "SECURITY"). Rendered uppercase + spaced.
  final String? caption;

  /// The rows (typically [SettingsRow]s) stacked inside the group.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: 62,
          color: palette.border,
        ));
      }
      rows.add(children[i]);
    }

    final body = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Column(children: rows),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, AppSpacing.xs),
            child: Text(
              caption!.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: palette.textFaint,
              ),
            ),
          ),
        LiquidGlass(
          borderRadius: BorderRadius.circular(AppRadius.card),
          blur: 20,
          frost: palette.isDark ? 1.05 : 0.72,
          padding: EdgeInsets.zero,
          child: body,
        ),
      ],
    );
  }
}
