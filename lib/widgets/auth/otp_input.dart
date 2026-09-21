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
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;
  String? _clipboardOtp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controllers =
        List.generate(widget.length, (_) => TextEditingController());
    _nodes = List.generate(widget.length, (_) => FocusNode());

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
    if (focusIndex >= 0 && focusIndex < _nodes.length) {
      _nodes[focusIndex].requestFocus();
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
          maxLength: 8,
          showCursor: true,
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

  // A value is treated as "pasted / autofilled" when several digits arrive at once.
  bool _looksPasted(String v) => v.length >= 2;
}
