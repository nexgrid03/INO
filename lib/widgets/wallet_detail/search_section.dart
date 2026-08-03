import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';
import '../divine_glass/divine_glass.dart';

/// Section 3 - Smart Search.
///
/// A prominent rounded search field (name · tags · category · record number).
/// Rendered inside a pinned [SliverPersistentHeader] via [SearchHeaderDelegate]
/// so it stays accessible while the document list scrolls.
class DetailSearchBar extends StatelessWidget {
  const DetailSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final launcher = divineGlassEnabled(context);
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: launcher ? 16 : 14, color: palette.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: AppLocalizations.of(context).t('searchDocumentsHint'),
        hintStyle: TextStyle(fontSize: launcher ? 16 : 14, color: palette.textFaint),
        prefixIcon: Icon(Icons.search_rounded, color: palette.textFaint),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: Icon(Icons.close_rounded,
                  color: palette.textFaint, size: 20),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            );
          },
        ),
        filled: true,
        fillColor: launcher ? Colors.transparent : palette.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(launcher ? 12 : AppRadius.search),
          borderSide: BorderSide(
            color: launcher
                ? Colors.white.withValues(alpha: 0.8)
                : palette.border,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(launcher ? 12 : AppRadius.search),
          borderSide: BorderSide(
            color: launcher
                ? Colors.white.withValues(alpha: 0.8)
                : palette.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(launcher ? 12 : AppRadius.search),
          borderSide:
              BorderSide(color: AppColors.primaryGreen, width: 1.6),
        ),
      ),
    );

    if (!launcher) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.search),
          boxShadow: palette.cardShadow,
        ),
        child: field,
      );
    }

    return LiquidGlass(
      borderRadius: BorderRadius.circular(12),
      blur: 6,
      frost: 0.85,
      shadow: false,
      padding: EdgeInsets.zero,
      child: field,
    );
  }
}

/// Keeps the search bar pinned at the top of the scroll. A solid background
/// (the scaffold colour) prevents document cards bleeding through underneath.
class SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  SearchHeaderDelegate({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.background,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final Color background;

  static const double _height = 72;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // The child MUST fill the declared extent exactly: a pinned persistent
    // header whose content is shorter than [maxExtent] makes paintExtent <
    // layoutExtent, which asserts and blanks the whole scroll view. Fixing the
    // height (and centring the field) keeps the geometry valid.
    return Container(
      height: _height,
      color: background,
      alignment: Alignment.center,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: DetailSearchBar(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
      ),
    );
  }

  @override
  bool shouldRebuild(SearchHeaderDelegate old) =>
      old.background != background ||
      old.controller != controller ||
      old.focusNode != focusNode;
}
