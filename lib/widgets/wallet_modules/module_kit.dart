import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/shiny_icon.dart';
import '../pressable_scale.dart';

/// The shared building blocks of the four data-driven wallet modules (Property,
/// Investment, Banking, Password Vault).
///
/// Everything here is a thin composition of the existing design system -
/// [AppPalette] colours, [AppSpacing]/[AppRadius] tokens, [AppText] type and the
/// brand [PressableScale] tactility - so the new modules are visually
/// indistinguishable from the screens that shipped before them. Building the
/// forms out of these keeps four large screens consistent without four copies
/// of the same field code.

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// A titled section card: icon chip, title, optional trailing action, then the
/// section's rows. The unit every detail screen and every form is built from.
class ModuleSection extends StatelessWidget {
  const ModuleSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.accent,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 16),
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color? accent;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = accent ?? AppColors.primaryGreen;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: palette.cardGradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShinyIcon(
                icon: icon,
                color: color,
                size: 38,
                iconSize: 19,
                radius: 12,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.title.copyWith(
                        color: palette.textPrimary,
                        fontSize: 15.5,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ],
      ),
    );
  }
}

/// A label → value row inside a [ModuleSection]. Renders nothing when [value]
/// is null or blank, so a detail screen shows only what the user filled in
/// instead of a wall of em-dashes.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.onTap,
    this.copyable = false,
    this.monospace = false,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final Color? valueColor;
  final VoidCallback? onTap;

  /// Adds a copy button that puts [value] on the clipboard.
  final bool copyable;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final v = value?.trim();
    if (v == null || v.isEmpty) return const SizedBox.shrink();
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: palette.textFaint),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 6,
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: AppText.subtitle.copyWith(
                color: valueColor ?? palette.textPrimary,
                fontSize: 13.5,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: 6),
            _MiniIconButton(
              icon: Icons.copy_rounded,
              tooltip: 'Copy',
              onTap: () {
                Clipboard.setData(ClipboardData(text: v));
                HapticFeedback.selectionClick();
                showModuleToast(context, '$label copied');
              },
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.textFaint),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: row,
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final button = PressableScale(
      pressedScale: 0.85,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: palette.border),
          ),
          child: Icon(icon, size: 15, color: palette.textSecondary),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// A compact metric tile: value on top, label beneath, tinted by [accent].
/// Used in the portfolio/summary strips across all four modules.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bold = InoStyle.of(context) == ThemeStyle.bold;
    final fill = bold
        ? InoStyle.boldFill(accent)
        : Color.alphaBlend(
            accent.withValues(alpha: palette.isDark ? 0.16 : 0.09),
            palette.surface,
          );
    final textPrimary = bold ? Colors.white : palette.textPrimary;
    final textSecondary =
        bold ? InoStyle.boldTextSecondary : palette.textSecondary;
    final tile = Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.chip + 2),
        border: Border.all(
          color: bold ? InoStyle.boldBorder(accent) : accent.withValues(alpha: 0.35),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: bold ? Colors.white : accent),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.title.copyWith(color: textPrimary, fontSize: 16),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: textSecondary, fontSize: 11.5),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return PressableScale(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: tile,
      ),
    );
  }
}

/// The premium empty state every module shows before its first record: a
/// gradient glyph, a headline, a line of guidance and a primary CTA.
class ModuleEmptyState extends StatelessWidget {
  const ModuleEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.accent = AppColors.primaryGreen,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        children: [
          // Soft halo behind a gradient glyph - the same treatment the wallet
          // detail empty state uses.
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.24),
                  accent.withValues(alpha: 0),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: InoStyle.gradient(context, AppColors.brandGradient),
                boxShadow: AppShadows.glow(accent, opacity: 0.28),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.title.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GradientButton(
            label: actionLabel,
            icon: Icons.add_rounded,
            onTap: onAction,
            expand: false,
          ),
        ],
      ),
    );
  }
}

/// A compact gradient CTA - the pill used inside cards and sheets where the
/// full-height [PrimaryButton] would be too heavy.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.expand = true,
    this.busy = false,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool expand;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return PressableScale(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            gradient: InoStyle.gradient(context, AppColors.brandGradient),
            borderRadius: BorderRadius.circular(AppRadius.button),
            boxShadow: enabled
                ? AppShadows.glow(AppColors.primaryGreen, opacity: 0.30)
                : null,
          ),
          child: Opacity(
            opacity: enabled || busy ? 1 : 0.55,
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: busy
                  ? const [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ]
                  : [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 19),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form fields
// ---------------------------------------------------------------------------

/// The shared field decoration: filled surface-variant, chip radius, accent
/// focus ring. Every field in every module form uses this one function.
InputDecoration moduleFieldDecoration(
  BuildContext context, {
  String? hint,
  Widget? prefix,
  Widget? suffix,
  Color accent = AppColors.primaryGreen,
  String? prefixText,
}) {
  final palette = AppPalette.of(context);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: AppText.body.copyWith(color: palette.textFaint),
    prefixIcon: prefix,
    prefixText: prefixText,
    prefixStyle: AppText.subtitle.copyWith(color: palette.textSecondary),
    suffixIcon: suffix,
    filled: true,
    fillColor: palette.surfaceVariant,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(palette.border),
    enabledBorder: border(palette.border),
    focusedBorder: border(accent, 1.6),
    errorBorder: border(AppColors.critical),
    focusedErrorBorder: border(AppColors.critical, 1.6),
  );
}

/// A labelled text field.
class ModuleField extends StatelessWidget {
  const ModuleField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.prefixText,
    this.suffix,
    this.textCapitalization = TextCapitalization.sentences,
    this.validator,
    this.inputFormatters,
    this.obscure = false,
    this.autofocus = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? prefixText;
  final Widget? suffix;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: AppText.label.copyWith(color: palette.textPrimary),
              ),
              if (validator != null) ...[
                const SizedBox(width: 3),
                const Text('*',
                    style: TextStyle(color: AppColors.critical, fontSize: 12)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: obscure ? 1 : maxLines,
            obscureText: obscure,
            autofocus: autofocus,
            textCapitalization: textCapitalization,
            inputFormatters: inputFormatters,
            validator: validator,
            onChanged: onChanged,
            style: AppText.body.copyWith(color: palette.textPrimary),
            decoration: moduleFieldDecoration(
              context,
              hint: hint,
              suffix: suffix,
              prefixText: prefixText,
            ),
          ),
        ],
      ),
    );
  }
}

/// A field that opens a picker instead of a keyboard: shows the current [value]
/// (or [hint] when empty) and a chevron.
class ModulePickerField extends StatelessWidget {
  const ModulePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.hint = 'Select',
    this.icon,
    this.accent,
    this.trailingIcon = Icons.expand_more_rounded,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final String hint;
  final IconData? icon;
  final Color? accent;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final filled = (value ?? '').isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.label.copyWith(color: palette.textPrimary)),
          const SizedBox(height: 6),
          PressableScale(
            pressedScale: 0.985,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon,
                          size: 18, color: accent ?? palette.textSecondary),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        filled ? value! : hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          color:
                              filled ? palette.textPrimary : palette.textFaint,
                        ),
                      ),
                    ),
                    Icon(trailingIcon, size: 20, color: palette.textFaint),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled on/off row (e.g. "Loan against property").
class ModuleSwitchField extends StatelessWidget {
  const ModuleSwitchField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: palette.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: palette.textSecondary),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          AppText.subtitle.copyWith(color: palette.textPrimary)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: AppColors.primaryGreen,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of selectable chips - the filter row shared by
/// every module list.
class ModuleChipRow extends StatelessWidget {
  const ModuleChipRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
    this.icons,
    this.counts,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<IconData>? icons;
  final List<int>? counts;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ModuleChip(
          label: labels[i],
          icon: icons == null ? null : icons![i],
          count: counts == null ? null : counts![i],
          selected: i == selectedIndex,
          onTap: () {
            HapticFeedback.selectionClick();
            onSelect(i);
          },
        ),
      ),
    );
  }
}

class ModuleChip extends StatelessWidget {
  const ModuleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = accent ?? AppColors.primaryGreen;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected
              ? InoStyle.gradient(context, AppColors.brandGradient)
              : null,
          color: selected ? null : palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? Colors.transparent : palette.border,
          ),
          boxShadow: selected
              ? AppShadows.glow(color, opacity: 0.22)
              : palette.cardShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 15,
                  color: selected ? Colors.white : palette.textSecondary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppText.caption.copyWith(
                color: selected ? Colors.white : palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 5),
              Text(
                '$count',
                style: AppText.caption.copyWith(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : palette.textFaint,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Headers & feedback
// ---------------------------------------------------------------------------

/// The compact screen header shared by the module screens: back chevron, title
/// + subtitle, and up to two trailing actions.
class ModuleHeader extends StatelessWidget {
  const ModuleHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        ModuleIconButton(
          icon: Icons.arrow_back_rounded,
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 19, color: AppColors.primaryGreen),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.headline.copyWith(
                        color: palette.textPrimary,
                        fontSize: 21,
                      ),
                    ),
                  ),
                ],
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                ),
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: 8), a],
      ],
    );
  }
}

/// The circular surface icon button used in headers and card corners.
class ModuleIconButton extends StatelessWidget {
  const ModuleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.size = 42,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;
  final double size;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final button = PressableScale(
      pressedScale: 0.9,
      child: Material(
        color: palette.surface,
        shape: CircleBorder(side: BorderSide(color: palette.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 20, color: color ?? palette.textPrimary),
                if (badge > 0)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.critical,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// The module toast: floating, brand-tinted, consistent across all four screens.
void showModuleToast(BuildContext context, String message,
    {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
        duration: const Duration(seconds: 2),
      ),
    );
}

/// A brief full-screen success animation: a brand ring that draws itself, a
/// check that pops in, then the overlay fades out on its own.
///
/// Awaited by the save flows so the caller pops back only once it has played.
Future<void> showSuccessBurst(BuildContext context, String message) async {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  final entry = OverlayEntry(
    builder: (_) => _SuccessBurst(message: message),
  );
  overlay.insert(entry);
  HapticFeedback.mediumImpact();
  await Future<void>.delayed(const Duration(milliseconds: 1150));
  entry.remove();
}

class _SuccessBurst extends StatefulWidget {
  const _SuccessBurst({required this.message});

  final String message;

  @override
  State<_SuccessBurst> createState() => _SuccessBurstState();
}

class _SuccessBurstState extends State<_SuccessBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // Fade the whole overlay in quickly, hold, then fade out.
          final opacity = t < 0.12
              ? t / 0.12
              : (t > 0.78 ? (1 - (t - 0.78) / 0.22).clamp(0.0, 1.0) : 1.0);
          final pop = Curves.easeOutBack.transform(
            ((t - 0.10) / 0.35).clamp(0.0, 1.0),
          );
          return Opacity(
            opacity: opacity,
            child: Container(
              color: palette.bg.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 0.6 + 0.4 * pop,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.brandGradient,
                        boxShadow: AppShadows.glow(
                          AppColors.primaryGreen,
                          opacity: 0.40,
                        ),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 42),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    widget.message,
                    style: AppText.title.copyWith(color: palette.textPrimary),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A simple pill-shaped skeleton block, used while a module hydrates.
class ModuleSkeleton extends StatefulWidget {
  const ModuleSkeleton({
    super.key,
    this.height = 96,
    this.count = 3,
    this.radius = AppRadius.card,
  });

  final double height;
  final int count;
  final double radius;

  @override
  State<ModuleSkeleton> createState() => _ModuleSkeletonState();
}

class _ModuleSkeletonState extends State<ModuleSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Column(
        children: [
          for (var i = 0; i < widget.count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                height: widget.height,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    palette.surfaceVariant,
                    palette.border,
                    0.25 + 0.35 * _c.value,
                  ),
                  borderRadius: BorderRadius.circular(widget.radius),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pickers
// ---------------------------------------------------------------------------

/// A generic option-picker sheet: a titled list of [labels], the current one
/// ticked. Returns the chosen index, or null when dismissed.
Future<int?> showModulePicker(
  BuildContext context, {
  required String title,
  required List<String> labels,
  List<IconData>? icons,
  List<Color>? colors,
  int? selectedIndex,
}) {
  final palette = AppPalette.of(context);
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: palette.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
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
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: labels.length,
                itemBuilder: (context, i) {
                  final selected = i == selectedIndex;
                  final color = colors == null
                      ? AppColors.primaryGreen
                      : colors[i % colors.length];
                  return ListTile(
                    leading: icons == null
                        ? null
                        : Icon(icons[i % icons.length], color: color, size: 21),
                    title: Text(
                      labels[i],
                      style: AppText.body.copyWith(
                        color: palette.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_rounded,
                            color: AppColors.primaryGreen)
                        : null,
                    onTap: () => Navigator.of(context).pop(i),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    ),
  );
}

/// The app's date picker, themed to the brand accent. Returns null on cancel.
Future<DateTime?> showModuleDatePicker(
  BuildContext context, {
  DateTime? initial,
  DateTime? first,
  DateTime? last,
}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: first ?? DateTime(1900),
    lastDate: last ?? DateTime(now.year + 60),
    builder: (context, child) {
      final palette = AppPalette.of(context);
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: (palette.isDark
                  ? const ColorScheme.dark()
                  : const ColorScheme.light())
              .copyWith(
            primary: AppColors.primaryGreen,
            onPrimary: Colors.white,
            surface: palette.surface,
            onSurface: palette.textPrimary,
          ),
        ),
        child: child!,
      );
    },
  );
}

/// A confirmation dialog for destructive actions. Resolves true on confirm.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final palette = AppPalette.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      title: Text(title,
          style: AppText.title.copyWith(color: palette.textPrimary)),
      content: Text(message,
          style: AppText.body.copyWith(color: palette.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel',
              style: TextStyle(color: palette.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel,
              style: const TextStyle(
                  color: AppColors.critical, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Short month names shared by the module screens.
const List<String> kMonthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "12 Mar 2024" - the module date format.
String formatModuleDate(DateTime d) =>
    '${d.day} ${kMonthNames[d.month - 1]} ${d.year}';
