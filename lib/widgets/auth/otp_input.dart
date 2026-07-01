import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// A row of individual OTP entry boxes (6 by default).
///
/// Behaves the way users expect from banking apps:
///   • auto-advances to the next box as digits are typed,
///   • backspace on an empty box steps back and clears the previous digit,
///   • pasting a full code (e.g. from an SMS autofill) distributes across boxes,
///   • the focused box lifts with a brand glow.
///
/// Reports the current value via [onChanged] and fires [onCompleted] once every
/// box is filled — keeping the parent screen purely about verification logic.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.enabled = true,
  });

  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool enabled;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _controllers =
        List.generate(widget.length, (_) => TextEditingController());
    _nodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _emit() {
    final value = _value;
    widget.onChanged?.call(value);
    if (value.length == widget.length) {
      widget.onCompleted?.call(value);
    }
  }

  void _onChanged(int index, String raw) {
    // Handle a pasted / autofilled multi-digit string by spreading it out.
    if (raw.length > 1) {
      _distribute(raw);
      return;
    }

    if (raw.isNotEmpty && index < widget.length - 1) {
      _nodes[index + 1].requestFocus();
    }
    _emit();
  }

  void _distribute(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    for (int i = 0; i < widget.length; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    final filled = digits.length.clamp(0, widget.length);
    final focusIndex = (filled - 1).clamp(0, widget.length - 1);
    _nodes[focusIndex].requestFocus();
    _emit();
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _nodes[index - 1].requestFocus();
      _emit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (index) {
        return Padding(
          padding: EdgeInsets.only(right: index == widget.length - 1 ? 0 : 10),
          child: _OtpBox(
            controller: _controllers[index],
            node: _nodes[index],
            enabled: widget.enabled,
            onChanged: (v) => _onChanged(index, v),
            onKey: (event) => _onKey(index, event),
          ),
        );
      }),
    );
  }
}

class _OtpBox extends StatefulWidget {
  const _OtpBox({
    required this.controller,
    required this.node,
    required this.enabled,
    required this.onChanged,
    required this.onKey,
  });

  final TextEditingController controller;
  final FocusNode node;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(KeyEvent) onKey;

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.node.addListener(() {
      if (widget.node.hasFocus != _focused) {
        setState(() => _focused = widget.node.hasFocus);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.controller.text.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 48,
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused || filled
              ? AppColors.primaryGreen
              : const Color(0xFFE2E8F0),
          width: _focused ? 1.8 : 1.2,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.18),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      alignment: Alignment.center,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (event) => widget.onKey(event),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.node,
          enabled: widget.enabled,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          // Allow a longer buffer so a full pasted code reaches onChanged.
          maxLength: 6,
          showCursor: true,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) {
            if (v.length > 1 && _looksPasted(v)) {
              // A full code was pasted / SMS-autofilled: hand it up whole so
              // the parent can distribute it across every box.
              widget.onChanged(v);
              return;
            }
            if (v.length > 1) {
              // Typing into an already-filled box: keep just the newest digit
              // and advance.
              final last = v.substring(v.length - 1);
              widget.controller.text = last;
              widget.controller.selection =
                  const TextSelection.collapsed(offset: 1);
              widget.onChanged(last);
              return;
            }
            widget.onChanged(v); // 0 (cleared) or 1 digit
          },
        ),
      ),
    );
  }

  // A value is treated as "pasted" when several digits arrive at once.
  bool _looksPasted(String v) => v.length >= 4;
}
