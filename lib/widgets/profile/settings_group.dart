import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// A grouped inset settings list — the core primitive of the redesigned Profile
/// page (the Apple Settings / Google Account pattern).
///
/// A small uppercase [caption] sits above a single white, softly-shadowed
/// container whose rows are separated by hairline dividers indented past the
/// icon column. Groups are the ONLY structure on the page, so the whole screen
/// reads as one calm, scannable settings list rather than a stack of cards.
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
          indent: 62, // clears the 14 pad + 34 icon + 14 gap column
          color: palette.border,
        ));
      }
      rows.add(children[i]);
    }

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
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: palette.border),
            boxShadow: palette.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.button),
            child: Column(children: rows),
          ),
        ),
      ],
    );
  }
}
