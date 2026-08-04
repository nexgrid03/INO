import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Premium auth / settings text field.
///
/// Label sits **above** the field (never on the outline), so borders never
/// cut through text. Used by Login, Signup, Forgot Password and Contact Support.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onSubmitted,
    this.suffix,
    this.inputFormatters,
    this.autofillHints,
    this.enabled = true,
    this.minLines,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final int? minLines;
  final int maxLines;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (_node.hasFocus != _focused) {
        setState(() => _focused = _node.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final borderColor = _focused ? AppColors.primaryGreen : palette.border;
    final fill = palette.isDark ? palette.surfaceVariant : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            // Primary ink — secondary slate washed out on aqua skies.
            color: palette.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          focusNode: _node,
          enabled: widget.enabled,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textCapitalization: widget.textCapitalization,
          validator: widget.validator,
          onFieldSubmitted: widget.onSubmitted,
          inputFormatters: widget.inputFormatters,
          autofillHints: widget.autofillHints,
          minLines: widget.minLines,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            // Label is rendered above — keep the outline clean.
            hintText: widget.hint,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            isDense: true,
            filled: true,
            fillColor: fill,
            prefixIcon: Icon(
              widget.icon,
              color: _focused
                  ? AppColors.primaryGreen
                  : AppColors.primaryGreen.withValues(alpha: 0.65),
            ),
            suffixIcon: widget.suffix,
            hintStyle: TextStyle(
              color: palette.textFaint,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: (widget.minLines ?? 1) > 1 ? 16 : 16,
            ),
            border: _border(borderColor),
            enabledBorder: _border(palette.border),
            focusedBorder: _border(AppColors.primaryGreen, width: 1.6),
            errorBorder: _border(AppColors.critical),
            focusedErrorBorder: _border(AppColors.critical, width: 1.6),
            disabledBorder: _border(palette.border.withValues(alpha: 0.5)),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1.2}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
      gapPadding: 0,
    );
  }
}
