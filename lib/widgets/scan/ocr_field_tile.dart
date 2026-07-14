import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// A labelled field wrapper used on the OCR results screen. Keeps every editable
/// row visually consistent — a small label (with an optional "Optional" hint)
/// above the editable control.
class OcrField extends StatelessWidget {
  const OcrField({
    super.key,
    required this.label,
    required this.child,
    this.optional = false,
  });

  final String label;
  final Widget child;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: AppText.subtitle
                    .copyWith(color: palette.textPrimary, fontSize: 13)),
            if (optional) ...[
              const SizedBox(width: 6),
              Text(AppLocalizations.of(context).t('optional'),
                  style:
                      AppText.label.copyWith(color: palette.textFaint, fontSize: 11)),
            ],
          ],
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

/// An editable text input styled for the OCR review cards.
class OcrTextField extends StatelessWidget {
  const OcrTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.validator,
    this.textCapitalization = TextCapitalization.words,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      textCapitalization: textCapitalization,
      style: AppText.body.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.body.copyWith(color: palette.textFaint),
        filled: true,
        fillColor: palette.surfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: border(palette.border),
        enabledBorder: border(palette.border),
        focusedBorder: border(AppColors.primaryGreen, 1.6),
        errorBorder: border(AppColors.critical),
        focusedErrorBorder: border(AppColors.critical, 1.6),
      ),
    );
  }
}

/// A tappable selector row (wallet / category / date) styled to match
/// [OcrTextField]. Shows the current value or a muted placeholder.
class OcrSelector extends StatelessWidget {
  const OcrSelector({
    super.key,
    required this.value,
    required this.placeholder,
    required this.leading,
    required this.onTap,
    this.trailing = Icons.keyboard_arrow_down_rounded,
  });

  final String? value;
  final String placeholder;
  final IconData leading;
  final IconData trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasValue = value != null && value!.isNotEmpty;
    return PressableScale(
      pressedScale: 0.98,
      child: Material(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(leading, size: 19, color: AppColors.primaryGreen),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    hasValue ? value! : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      color: hasValue ? palette.textPrimary : palette.textFaint,
                    ),
                  ),
                ),
                Icon(trailing, size: 20, color: palette.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
