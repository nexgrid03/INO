import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// A row of individual OTP entry boxes (6 by default) with native OS autofill
/// and smart clipboard autofill support for Email and Mobile OTPs.
///
/// Features:
///   • Native Android / iOS SMS & Email one-time code autofill ([AutofillHints.oneTimeCode]).
///   • Automatic clipboard detection when switching back from Email/SMS apps.
///   • Instant multi-digit distribution when pasted or autofilled.
///   • Auto-advances focus to the next box as digits are typed.
///   • Backspace on an empty box clears and steps back to previous box.
///   • Reports value via [onChanged] and fires [onCompleted] when all boxes are filled.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.enabled = true,
    this.showClipboardPrompt = true,
  });

  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool showClipboardPrompt;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> with WidgetsBindingObserver {
  /// Invisible sentinel placed in empty boxes (after index 0) so iOS UIKit
  /// still receives a deleteBackward / onChanged event when Backspace is
  /// pressed on the soft keyboard without needing to move the cursor back first.
  static const String _sentinel = '\u200B';

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;
  late final List<String> _prevDigits;
  String? _clipboardOtp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controllers = List.generate(
      widget.length,
      (i) => TextEditingController(text: i == 0 ? '' : _sentinel),
    );
    _nodes = List.generate(widget.length, (_) => FocusNode());
    _prevDigits = List.filled(widget.length, '');

    // Check clipboard on initial load
    _checkClipboard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User may have copied OTP from email or SMS notification and switched back
      _checkClipboard();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    if (!widget.enabled || !widget.showClipboardPrompt) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      final digits = text.replaceAll(RegExp(r'\D'), '');
      if (digits.length == widget.length && digits != _value) {
        if (mounted) {
          setState(() => _clipboardOtp = digits);
        }
      }
    } catch (_) {
      // Ignore clipboard access exceptions
    }
  }

  String get _value => _prevDigits.join();

  void _setBox(int index, String digit) {
    _prevDigits[index] = digit;
    final text = digit.isNotEmpty ? digit : (index == 0 ? '' : _sentinel);
    _controllers[index].value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _focusBox(int index) {
    if (index < 0 || index >= _nodes.length) return;
    _nodes[index].requestFocus();
    final len = _controllers[index].text.length;
    _controllers[index].selection = TextSelection.collapsed(offset: len);
  }

  void _emit() {
    final value = _value;
    widget.onChanged?.call(value);
    if (value.length == widget.length) {
      widget.onCompleted?.call(value);
    }
  }

  void _onChanged(int index, String raw) {
    final digits = raw.replaceAll(_sentinel, '').replaceAll(RegExp(r'\D'), '');

    if (digits.isEmpty) {
      final wasDeleted = raw.isEmpty;
      final hadDigit = _prevDigits[index].isNotEmpty;
      if (!wasDeleted) {
        // Non-digit character typed: restore previous box contents.
        _setBox(index, _prevDigits[index]);
        return;
      }
      if (hadDigit) {
        // Digit in this box was deleted.
        _setBox(index, '');
        _emit();
        return;
      }
      // Empty box had its sentinel deleted via Backspace: clear previous box
      // and step focus back.
      _setBox(index, '');
      if (index > 0) {
        _setBox(index - 1, '');
        _focusBox(index - 1);
        _emit();
      }
      return;
    }

    // Multi-digit paste / autofill, or typing a second digit into a filled box.
    if (digits.length > 1) {
      final prev = _prevDigits[index];
      if (prev.isNotEmpty && digits.length == 2) {
        final nextDigit =
            digits.startsWith(prev) ? digits.substring(1) : digits.substring(0, 1);
        _setBox(index, nextDigit);
        if (index < widget.length - 1) {
          _focusBox(index + 1);
        }
        _emit();
        return;
      }
      _distribute(digits);
      return;
    }

    _setBox(index, digits);
    if (index < widget.length - 1) {
      _focusBox(index + 1);
    }
    _emit();
  }

  void _distribute(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    for (int i = 0; i < widget.length; i++) {
      _setBox(i, i < digits.length ? digits[i] : '');
    }
    final filled = digits.length.clamp(0, widget.length);
    final focusIndex = (filled - 1).clamp(0, widget.length - 1);
    if (focusIndex >= 0 && focusIndex < _nodes.length) {
      _focusBox(focusIndex);
    }
    setState(() => _clipboardOtp = null);
    _emit();
  }

  void _pasteFromClipboard() async {
    HapticFeedback.mediumImpact();
    if (_clipboardOtp != null) {
      _distribute(_clipboardOtp!);
      return;
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isNotEmpty) {
        _distribute(text);
      }
    } catch (_) {}
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _prevDigits[index].isEmpty &&
        index > 0) {
      _setBox(index - 1, '');
      _focusBox(index - 1);
      _emit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AutofillGroup(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final available = constraints.maxWidth;
              final box = available.isFinite
                  ? (((available - gap * (widget.length - 1)) / widget.length)
                      .clamp(28.0, 48.0))
                  : 48.0;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < widget.length; index++) ...[
                    if (index > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: box,
                      child: _OtpBox(
                        controller: _controllers[index],
                        node: _nodes[index],
                        enabled: widget.enabled,
                        onChanged: (v) => _onChanged(index, v),
                        onKey: (event) => _onKey(index, event),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),

        // Smart Clipboard Autofill Suggestion Pill
        if (_clipboardOtp != null && widget.enabled) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pasteFromClipboard,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.content_paste_rounded,
                    size: 14,
                    color: AppColors.primaryGreen,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Autofill from clipboard: $_clipboardOtp',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
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

  void _handleFocus() {
    if (!mounted) return;
    final hasFocus = widget.node.hasFocus;
    if (hasFocus) {
      final text = widget.controller.text;
      // Keep the caret after the invisible sentinel so Backspace on iOS
      // always deletes it rather than sitting at offset 0.
      if (text == '\u200B') {
        widget.controller.selection =
            TextSelection.collapsed(offset: text.length);
      }
    }
    if (hasFocus != _focused) {
      setState(() => _focused = hasFocus);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.node.addListener(_handleFocus);
  }

  @override
  void dispose() {
    widget.node.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.controller.text.replaceAll('\u200B', '').isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused
              ? AppColors.primaryGreen
              : (filled
                  ? AppColors.primaryGreen.withValues(alpha: 0.7)
                  : AppColors.tealPale),
          width: _focused ? 1.8 : 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Focus(
        onKeyEvent: (_, event) => widget.onKey(event),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.node,
          enabled: widget.enabled,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          cursorColor: AppColors.primaryGreen,
          autofillHints: const [AutofillHints.oneTimeCode],
          // Allow full multi-digit buffer so pasted/autofilled codes reach onChanged.
          maxLength: 12,
          showCursor: true,
          onTap: () {
            final text = widget.controller.text;
            if (text == '\u200B') {
              widget.controller.selection =
                  TextSelection.collapsed(offset: text.length);
            }
          },
          style: TextStyle(
            color: AppColors.primaryGreen,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
