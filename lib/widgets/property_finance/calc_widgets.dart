import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
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
        content: Text(message ?? 'Copied to clipboard'),
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
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _CalcHeader(title: title, subtitle: subtitle),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                    AppSpacing.screen, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalcHeader extends StatelessWidget {
  const _CalcHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
          AppSpacing.screen, AppSpacing.lg),
      child: Row(
        children: [
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 21, color: palette.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.headline.copyWith(
                        color: palette.textPrimary, fontSize: 21)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        AppText.caption.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A card grouping a set of inputs under an optional [title].
class CalcInputCard extends StatelessWidget {
  const CalcInputCard({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.internal),
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
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: c, width: w),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppText.label
                .copyWith(color: palette.textFaint, fontSize: 11.5)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType:
              TextInputType.numberWithOptions(decimal: allowDecimal),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
                RegExp(allowDecimal ? r'[0-9.]' : r'[0-9]')),
          ],
          onChanged: (_) => onChanged(),
          style: AppText.title.copyWith(color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppText.body.copyWith(color: palette.textFaint),
            prefixText: prefix == null ? null : '$prefix  ',
            prefixStyle:
                AppText.title.copyWith(color: palette.textSecondary),
            suffixText: suffix,
            suffixStyle:
                AppText.subtitle.copyWith(color: palette.textFaint),
            filled: true,
            fillColor: palette.surfaceVariant,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: border(palette.border),
            enabledBorder: border(palette.border),
            focusedBorder: border(AppColors.primaryGreen, 1.6),
          ),
        ),
      ],
    );
  }
}

/// The headline result of a calculator — a gradient card with a big value and
/// a copy action.
class HeroResultCard extends StatelessWidget {
  const HeroResultCard({
    super.key,
    required this.label,
    required this.value,
    this.copyText,
    this.gradient = AppColors.brandGradient,
  });

  final String label;
  final String value;

  /// If set, shows a copy button that copies this text.
  final String? copyText;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.internal),
      decoration: BoxDecoration(
        gradient: gradient,
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
class CalcSegmented<T> extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppText.label
                .copyWith(color: palette.textFaint, fontSize: 11.5)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              for (final o in options)
                Expanded(
                  child: PressableScale(
                    pressedScale: 0.97,
                    child: GestureDetector(
                      onTap: () => onChanged(o),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: o == selected
                              ? AppColors.brandGradient
                              : null,
                          borderRadius:
                              BorderRadius.circular(AppRadius.chip - 4),
                        ),
                        child: Text(
                          labelOf(o),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle.copyWith(
                            color: o == selected
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
      ],
    );
  }
}
