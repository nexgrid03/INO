import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../dashboard/section_header.dart';

/// A titled group of settings rows: a [SectionHeader] then a single card with
/// the [tiles] stacked and separated by hairline dividers (indented past the
/// icon column). Keeps every Profile section visually identical.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.tiles,
    this.icon,
    this.iconColor,
  });

  final String title;
  final IconData? icon;
  final Color? iconColor;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, icon: icon, iconColor: iconColor),
        InoCard(
          radius: AppRadius.card,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 58,
                    endIndent: 12,
                    color: palette.border,
                  ),
                tiles[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
