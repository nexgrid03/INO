import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/ino_back_button.dart';
import '../common/ino_background.dart';
import '../dashboard/ino_card.dart';
import '../divine_glass/divine_glass.dart';
import '../pressable_scale.dart';

/// Copies [text] to the clipboard with haptic + snackbar feedback. Shared by
/// every calculator's result card.
void copyToClipboard(BuildContext context, String text, {String? message}) {
  Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.selectionClick();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message ?? AppLocalizations.of(context).t('copied')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryGreen,
      ),
    );
}

/// A consistent header + scrollable body used by every calculator screen.
class CalculatorScaffold extends StatelessWidget {
  const CalculatorScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  /// Optional header action (e.g. the currency pill).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final launcher = divineGlassEnabled(context);

    final scrollBody = SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md,
        AppSpacing.screen,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );

    if (launcher) {
      // Scaffold.appBar owns status-bar + bar height — body never overlaps.
      return Scaffold(
        backgroundColor: palette.bg,
        appBar: DivineGlassAppBar.asPreferredSize(
          context,
          title: title,
          subtitle: subtitle,
          centerTitle: false,
          trailing: trailing,
        ),
        body: InoBackground(
          sky: true,
          child: scrollBody,
        ),
      );
    }

    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        child: SafeArea(
          child: Column(
            children: [
              _CalcHeader(title: title, subtitle: subtitle, trailing: trailing),
              Expanded(child: scrollBody),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalcHeader extends StatelessWidget {
  const _CalcHeader({
    required this.title,
    // Kept for call-site compatibility; section headings are title-only.
    String? subtitle,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
          AppSpacing.screen, AppSpacing.lg),
      child: Row(
        children: [
          const InoBackButton(size: 42),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: AppText.headline.copyWith(
                color: palette.textPrimary,
                fontSize: 21,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A card grouping a set of inputs under an optional [title].
///
/// Solid surface (not frosted glass) so nested [CalcField]s don't read as a
/// second card stacked inside the first.
class CalcInputCard extends StatelessWidget {
  const CalcInputCard({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.internal),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!,
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// A labelled numeric input with an optional ₹/unit prefix and suffix.
///
/// Flat field that sits inside [CalcInputCard] — no nested bordered box.
/// Currency symbol is an inline prefix in the same row as the text.
class CalcField extends StatelessWidget {
  const CalcField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.prefix,
    this.suffix,
    this.allowDecimal = true,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? hint;
  final String? prefix;
  final String? suffix;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppText.label
                .copyWith(color: palette.textFaint, fontSize: 11.5)),
        const SizedBox(height: 4),
        // Single input row on the parent card — no second card chrome.
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: palette.border, width: 1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (prefix != null) ...[
                Text(
                  prefix!,
                  style: AppText.title.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.numberWithOptions(
                      decimal: allowDecimal),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(allowDecimal ? r'[0-9.]' : r'[0-9]')),
                  ],
                  onChanged: (_) => onChanged(),
                  style: AppText.title.copyWith(color: palette.textPrimary),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: AppText.body.copyWith(color: palette.textFaint),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 8),
                Text(
                  suffix!,
                  style: AppText.subtitle.copyWith(color: palette.textFaint),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The headline result of a calculator - a gradient card with a big value and
/// a copy action.
class HeroResultCard extends StatelessWidget {
   HeroResultCard({
    super.key,
    required this.label,
    required this.value,
    this.copyText,
    this.gradient,
  });

  final String label;
  final String value;

  /// If set, shows a copy button that copies this text.
  final String? copyText;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.internal),
      decoration: BoxDecoration(
        // Deeper in the bold theme, lighter in soft.
        gradient: InoStyle.gradient(
          context,
          gradient ?? AppColors.brandGradient,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: AppText.subtitle
                        .copyWith(color: Colors.white.withValues(alpha: 0.9))),
              ),
              if (copyText != null)
                _MiniIconButton(
                  icon: Icons.copy_rounded,
                  onTap: () => copyToClipboard(context, copyText!,
                      message: '$label copied'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.bigNumber.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, color: Colors.white, size: 17),
        ),
      ),
    );
  }
}

/// A card that lists secondary results as label/value rows.
class ResultBreakdownCard extends StatelessWidget {
  const ResultBreakdownCard({super.key, required this.rows});

  final List<ResultRow> rows;

  @override
  Widget build(BuildContext context) {
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.internal, vertical: AppSpacing.xs),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1, color: AppPalette.of(context).border),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One label/value line inside a [ResultBreakdownCard].
class ResultRow extends StatelessWidget {
  const ResultRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style:
                    AppText.body.copyWith(color: palette.textSecondary)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: AppText.subtitle.copyWith(
              color: valueColor ?? palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small info/empty hint card shown before a valid input is entered.
class CalcHint extends StatelessWidget {
  const CalcHint({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.internal),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: palette.textFaint, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message,
                style: AppText.body
                    .copyWith(color: palette.textSecondary, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// A segmented single-choice selector (e.g. purity 18K/22K/24K, unit Grams/Tola).
///
/// Horizontally scrollable chips; selecting an option scrolls it to the center
/// so clipped options on the right stay discoverable.
class CalcSegmented<T> extends StatefulWidget {
  const CalcSegmented({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  State<CalcSegmented<T>> createState() => _CalcSegmentedState<T>();
}

class _CalcSegmentedState<T> extends State<CalcSegmented<T>> {
  final _scroll = ScrollController();
  final _keys = <T, GlobalKey>{};

  GlobalKey _keyFor(T o) => _keys.putIfAbsent(o, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollSelectedToCenter());
  }

  @override
  void didUpdateWidget(covariant CalcSegmented<T> old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollSelectedToCenter());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollSelectedToCenter() {
    final key = _keys[widget.selected];
    final ctx = key?.currentContext;
    if (ctx == null || !_scroll.hasClients) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _onSelect(T o) {
    widget.onChanged(o);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollSelectedToCenter());
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: AppText.label
                .copyWith(color: palette.textFaint, fontSize: 11.5)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    for (final o in widget.options)
                      Padding(
                        key: _keyFor(o),
                        padding: const EdgeInsets.only(right: 2),
                        child: PressableScale(
                          pressedScale: 0.97,
                          child: GestureDetector(
                            onTap: () => _onSelect(o),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              height: 38,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: o == widget.selected
                                    ? InoStyle.gradient(
                                        context, AppColors.brandGradient)
                                    : null,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.chip - 4),
                              ),
                              child: Text(
                                widget.labelOf(o),
                                maxLines: 1,
                                softWrap: false,
                                style: AppText.subtitle.copyWith(
                                  color: o == widget.selected
                                      ? Colors.white
                                      : palette.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Soft edge fade — hints there is more to the right.
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: 28,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(AppRadius.chip - 1),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          palette.surfaceVariant.withValues(alpha: 0),
                          palette.surfaceVariant,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
