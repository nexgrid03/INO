import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// Shows a modern, smooth scrolling & directly clickable/typeable time picker dialog styled with INO's theme.
///
/// Features:
/// - Smooth vertical drag/scroll wheels for Hour (1-12) and Minute (00-59).
/// - Every single minute (00, 01, 02, ..., 59) is available and selectable.
/// - Top Hour and Minute boxes are **directly clickable to type manually** with a numeric keypad.
/// - Live two-way synchronization between manual typing and scroll wheels.
/// - Clean, uncluttered design without clumsy preset buttons.
/// - AM/PM switcher with instant feedback.
/// - Haptic feedback on wheel scrolling.
Future<TimeOfDay?> showInoTimePicker(
  BuildContext context, {
  TimeOfDay? initialTime,
  String? title,
  String? cancelText,
  String? confirmText,
}) async {
  return showDialog<TimeOfDay>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => InoTimePickerDialog(
      initialTime: initialTime ?? TimeOfDay.now(),
      title: title,
      cancelText: cancelText,
      confirmText: confirmText,
    ),
  );
}

class InoTimePickerDialog extends StatefulWidget {
  const InoTimePickerDialog({
    super.key,
    required this.initialTime,
    this.title,
    this.cancelText,
    this.confirmText,
  });

  final TimeOfDay initialTime;
  final String? title;
  final String? cancelText;
  final String? confirmText;

  @override
  State<InoTimePickerDialog> createState() => _InoTimePickerDialogState();
}

class _InoTimePickerDialogState extends State<InoTimePickerDialog> {
  static const double _itemExtent = 44.0;
  static const int _loopMultiplier = 1000; // Large range for infinite loop effect

  late int _selectedHour12; // 1 - 12
  late int _selectedMinute; // 0 - 59
  late bool _isAm; // true = AM, false = PM

  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late FixedExtentScrollController _periodController;

  late TextEditingController _hourTextController;
  late TextEditingController _minuteTextController;
  late FocusNode _hourFocusNode;
  late FocusNode _minuteFocusNode;

  @override
  void initState() {
    super.initState();
    final hour24 = widget.initialTime.hour;
    _selectedMinute = widget.initialTime.minute;
    _isAm = hour24 < 12;

    _selectedHour12 = hour24 % 12;
    if (_selectedHour12 == 0) _selectedHour12 = 12;

    _hourTextController =
        TextEditingController(text: _selectedHour12.toString());
    _minuteTextController = TextEditingController(
      text: _selectedMinute.toString().padLeft(2, '0'),
    );

    _hourFocusNode = FocusNode();
    _minuteFocusNode = FocusNode();

    _hourFocusNode.addListener(() {
      if (_hourFocusNode.hasFocus) {
        _hourTextController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _hourTextController.text.length,
        );
      } else {
        // Format on blur
        final h = int.tryParse(_hourTextController.text) ?? _selectedHour12;
        final clamped = h.clamp(1, 12);
        setState(() {
          _selectedHour12 = clamped;
          _hourTextController.text = clamped.toString();
        });
        _animateHourWheelTo(clamped);
      }
    });

    _minuteFocusNode.addListener(() {
      if (_minuteFocusNode.hasFocus) {
        _minuteTextController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _minuteTextController.text.length,
        );
      } else {
        // Format on blur
        final m = int.tryParse(_minuteTextController.text) ?? _selectedMinute;
        final clamped = m.clamp(0, 59);
        setState(() {
          _selectedMinute = clamped;
          _minuteTextController.text = clamped.toString().padLeft(2, '0');
        });
        _animateMinuteWheelTo(clamped);
      }
    });

    // Center the controllers in the looped list
    final initialHourIndex =
        (_loopMultiplier ~/ 2) * 12 + (_selectedHour12 - 1);
    final initialMinuteIndex =
        (_loopMultiplier ~/ 2) * 60 + _selectedMinute;

    _hourController =
        FixedExtentScrollController(initialItem: initialHourIndex);
    _minuteController =
        FixedExtentScrollController(initialItem: initialMinuteIndex);
    _periodController =
        FixedExtentScrollController(initialItem: _isAm ? 0 : 1);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    _hourTextController.dispose();
    _minuteTextController.dispose();
    _hourFocusNode.dispose();
    _minuteFocusNode.dispose();
    super.dispose();
  }

  TimeOfDay get _currentTime {
    int hour24;
    if (_isAm) {
      hour24 = (_selectedHour12 == 12) ? 0 : _selectedHour12;
    } else {
      hour24 = (_selectedHour12 == 12) ? 12 : _selectedHour12 + 12;
    }
    return TimeOfDay(hour: hour24, minute: _selectedMinute);
  }

  void _animateHourWheelTo(int hour) {
    if (!_hourController.hasClients) return;
    final currentItem = _hourController.selectedItem;
    final currentBase = currentItem - (currentItem % 12);
    final targetIndex = currentBase + (hour - 1);
    _hourController.animateToItem(
      targetIndex,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _animateMinuteWheelTo(int minute) {
    if (!_minuteController.hasClients) return;
    final currentItem = _minuteController.selectedItem;
    final currentBase = currentItem - (currentItem % 60);
    final targetIndex = currentBase + minute;
    _minuteController.animateToItem(
      targetIndex,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _onHourWheelChanged(int index) {
    final hour = (index % 12) + 1;
    if (hour != _selectedHour12) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedHour12 = hour;
        if (!_hourFocusNode.hasFocus) {
          _hourTextController.text = hour.toString();
        }
      });
    }
  }

  void _onMinuteWheelChanged(int index) {
    final minute = index % 60;
    if (minute != _selectedMinute) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedMinute = minute;
        if (!_minuteFocusNode.hasFocus) {
          _minuteTextController.text = minute.toString().padLeft(2, '0');
        }
      });
    }
  }

  void _onHourTextChanged(String raw) {
    if (raw.isEmpty) return;
    final val = int.tryParse(raw);
    if (val != null) {
      if (val >= 1 && val <= 12) {
        setState(() => _selectedHour12 = val);
        _animateHourWheelTo(val);
        if (raw.length >= 2 || val > 1) {
          _minuteFocusNode.requestFocus();
        }
      }
    }
  }

  void _onMinuteTextChanged(String raw) {
    if (raw.isEmpty) return;
    final val = int.tryParse(raw);
    if (val != null) {
      if (val >= 0 && val <= 59) {
        setState(() => _selectedMinute = val);
        _animateMinuteWheelTo(val);
      }
    }
  }

  void _togglePeriod(bool isAm) {
    if (_isAm != isAm) {
      HapticFeedback.selectionClick();
      setState(() => _isAm = isAm);
      _periodController.animateToItem(
        isAm ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final titleText = (widget.title ?? 'PICK A TIME').toUpperCase();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 330,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(color: palette.border),
            boxShadow: palette.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_filled_rounded,
                      size: 18,
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      titleText,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Direct Clickable / Editable Time Display Cards
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Editable Hour Box
                    _EditableDisplayBox(
                      controller: _hourTextController,
                      focusNode: _hourFocusNode,
                      label: 'Hour',
                      palette: palette,
                      onChanged: _onHourTextChanged,
                      onTap: () => _hourFocusNode.requestFocus(),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        ':',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                    // Editable Minute Box
                    _EditableDisplayBox(
                      controller: _minuteTextController,
                      focusNode: _minuteFocusNode,
                      label: 'Minute',
                      palette: palette,
                      onChanged: _onMinuteTextChanged,
                      onTap: () => _minuteFocusNode.requestFocus(),
                    ),
                    const SizedBox(width: 12),
                    // AM / PM Toggle Box
                    _AmPmToggle(
                      isAm: _isAm,
                      onChanged: _togglePeriod,
                      palette: palette,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 3. Scrollable Wheels Section
              Container(
                height: 180,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: palette.isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: palette.border.withValues(alpha: 0.6),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Center selection highlight lens
                    IgnorePointer(
                      child: Container(
                        height: _itemExtent,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          border: Border.all(
                            color:
                                AppColors.primaryGreen.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),

                    // Three Wheels
                    Row(
                      children: [
                        // Hours Wheel (1 - 12)
                        Expanded(
                          child: ListWheelScrollView.useDelegate(
                            controller: _hourController,
                            itemExtent: _itemExtent,
                            perspective: 0.003,
                            diameterRatio: 1.4,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: _onHourWheelChanged,
                            childDelegate: ListWheelChildBuilderDelegate(
                              builder: (context, index) {
                                final hour = (index % 12) + 1;
                                final isSelected = hour == _selectedHour12;
                                return Center(
                                  child: Text(
                                    hour.toString(),
                                    style: TextStyle(
                                      fontSize: isSelected ? 22 : 16,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.primaryGreen
                                          : palette.textFaint,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Colon separator
                        Text(
                          ':',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: palette.textSecondary,
                          ),
                        ),

                        // Minutes Wheel (All 00 to 59 selectable)
                        Expanded(
                          child: ListWheelScrollView.useDelegate(
                            controller: _minuteController,
                            itemExtent: _itemExtent,
                            perspective: 0.003,
                            diameterRatio: 1.4,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: _onMinuteWheelChanged,
                            childDelegate: ListWheelChildBuilderDelegate(
                              builder: (context, index) {
                                final minute = index % 60;
                                final isSelected = minute == _selectedMinute;
                                return Center(
                                  child: Text(
                                    minute.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: isSelected ? 22 : 16,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.primaryGreen
                                          : palette.textFaint,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Period Wheel (AM / PM)
                        Expanded(
                          child: ListWheelScrollView.useDelegate(
                            controller: _periodController,
                            itemExtent: _itemExtent,
                            perspective: 0.003,
                            diameterRatio: 1.4,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: (index) {
                              final isAm = index % 2 == 0;
                              if (isAm != _isAm) {
                                HapticFeedback.selectionClick();
                                setState(() => _isAm = isAm);
                              }
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 2,
                              builder: (context, index) {
                                final isAmItem = index == 0;
                                final isSelected = isAmItem == _isAm;
                                return Center(
                                  child: Text(
                                    isAmItem ? 'AM' : 'PM',
                                    style: TextStyle(
                                      fontSize: isSelected ? 18 : 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.primaryGreen
                                          : palette.textFaint,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 4. Actions Footer
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textSecondary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        widget.cancelText ?? 'Cancel',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.primaryGreen.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            FocusScope.of(context).unfocus();
                            Navigator.of(context).pop(_currentTime);
                          },
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 10,
                            ),
                            child: Text(
                              widget.confirmText ?? 'OK',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
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
          ),
        ),
      ),
    );
  }
}

class _EditableDisplayBox extends StatelessWidget {
  const _EditableDisplayBox({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.palette,
    required this.onChanged,
    required this.onTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final AppPalette palette;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: focusNode,
        builder: (context, _) {
          final isFocused = focusNode.hasFocus;
          return Container(
            width: 78,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: isFocused
                  ? (palette.isDark
                      ? AppColors.primaryGreen.withValues(alpha: 0.22)
                      : AppColors.primaryGreen.withValues(alpha: 0.16))
                  : (palette.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : AppColors.primaryGreen.withValues(alpha: 0.08)),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: isFocused
                    ? AppColors.primaryGreen
                    : AppColors.primaryGreen.withValues(alpha: 0.28),
                width: isFocused ? 2.0 : 1.0,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Theme(
                  data: Theme.of(context).copyWith(
                    inputDecorationTheme: const InputDecorationTheme(
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    cursorColor: AppColors.primaryGreen,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                      height: 1.1,
                    ),
                    decoration: const InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isFocused
                        ? AppColors.primaryGreen
                        : palette.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AmPmToggle extends StatelessWidget {
  const _AmPmToggle({
    required this.isAm,
    required this.onChanged,
    required this.palette,
  });

  final bool isAm;
  final ValueChanged<bool> onChanged;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          _AmPmButton(
            text: 'AM',
            selected: isAm,
            onTap: () => onChanged(true),
            palette: palette,
          ),
          _AmPmButton(
            text: 'PM',
            selected: !isAm,
            onTap: () => onChanged(false),
            palette: palette,
          ),
        ],
      ),
    );
  }
}

class _AmPmButton extends StatelessWidget {
  const _AmPmButton({
    required this.text,
    required this.selected,
    required this.onTap,
    required this.palette,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryGreen
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip - 2),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}
