import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/voice_command.dart';
import '../../services/voice_navigation_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// A small, **highlighted** voice-assistant button — a filled brand-gradient
/// circle with a white mic and a soft teal glow, meant to sit beside the
/// notification bell so the voice action clearly stands out. It looks identical
/// everywhere it's used (Home, Wallet, …). Tapping it opens the voice-command
/// sheet; when a command is recognized, the matched destination navigates itself
/// (via [VoiceCommand.navigate]) — no host wiring required.
class VoiceMicIconButton extends StatelessWidget {
  const VoiceMicIconButton({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: 'Voice assistant',
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            showVoiceCommandSheet(context);
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 21),
          ),
        ),
      ),
    );
  }
}

/// Opens the voice-command bottom sheet. On a successful match the destination
/// navigates itself, so callers don't need the result.
Future<void> showVoiceCommandSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.large),
      ),
    ),
    builder: (_) => const _VoiceCommandSheet(),
  );
}

class _VoiceCommandSheet extends StatefulWidget {
  const _VoiceCommandSheet();

  @override
  State<_VoiceCommandSheet> createState() => _VoiceCommandSheetState();
}

class _VoiceCommandSheetState extends State<_VoiceCommandSheet>
    with SingleTickerProviderStateMixin {
  final VoiceNavigationService _service = VoiceNavigationService.instance;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  String _lang = 'en';
  bool _popScheduled = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lang = Localizations.localeOf(context).languageCode;
      _service.start(languageCode: _lang);
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _service.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (_service.status == VoiceStatus.matched && !_popScheduled) {
      _popScheduled = true;
      final matched = _service.match;
      // Let the user see the "Opening …" confirmation briefly, then close the
      // sheet and let the destination navigate itself (works from anywhere).
      Future.delayed(const Duration(milliseconds: 750), () {
        if (mounted) Navigator.of(context).pop();
        matched?.navigate();
      });
    }
  }

  void _retry() {
    _popScheduled = false;
    _service.start(languageCode: _lang);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _body(palette),
          ],
        ),
      ),
    );
  }

  Widget _body(AppPalette palette) {
    switch (_service.status) {
      case VoiceStatus.idle:
      case VoiceStatus.initializing:
        return _listeningView(palette, warmingUp: true);
      case VoiceStatus.listening:
        return _listeningView(palette, warmingUp: false);
      case VoiceStatus.matched:
        return _matchedView(palette);
      case VoiceStatus.noMatch:
        return _noMatchView(palette);
      case VoiceStatus.denied:
        return _deniedView(palette);
      case VoiceStatus.unavailable:
        return _messageView(
          palette,
          icon: Icons.mic_off_rounded,
          title: 'Voice commands unavailable',
          message:
              'Speech recognition isn’t available on this device. You can still '
              'use the buttons to get around.',
        );
      case VoiceStatus.error:
        return _messageView(
          palette,
          icon: Icons.error_outline_rounded,
          title: 'Something went wrong',
          message: 'Please try the voice command again.',
          showRetry: true,
        );
    }
  }

  // ---- States ---------------------------------------------------------------

  Widget _listeningView(AppPalette palette, {required bool warmingUp}) {
    final heard = _service.recognizedText.trim();
    final preview = heard.isEmpty ? null : matchVoiceCommand(heard);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PulsingMic(pulse: _pulse, active: !warmingUp),
        const SizedBox(height: AppSpacing.lg),
        Text(
          warmingUp ? 'Getting ready…' : 'Listening…',
          style: AppText.title.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: AppSpacing.md),
        if (heard.isEmpty)
          Text(
            'Say a command like “Open Notes”.',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: palette.textSecondary),
          )
        else ...[
          _LiveField(palette: palette, label: 'RECOGNIZED', value: '“$heard”'),
          const SizedBox(height: AppSpacing.sm),
          _LiveField(
            palette: palette,
            label: 'MATCHED',
            value: preview?.route ?? '—',
            accent: preview != null,
          ),
        ],
      ],
    );
  }

  Widget _matchedView(AppPalette palette) {
    final label = _service.match?.spokenLabel ?? '';
    final icon = _service.match?.icon ?? Icons.check_rounded;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            gradient: AppColors.brandGradient,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 44),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Opening $label',
          style: AppText.title.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.primaryGreen,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              'Matched ${_service.match?.route ?? ''}',
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _noMatchView(AppPalette palette) {
    final heard = _service.recognizedText.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.hearing_disabled_rounded,
            color: AppColors.warning,
            size: 36,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          "Didn't catch a command",
          style: AppText.title.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          heard.isEmpty
              ? 'Please try again.'
              : 'Heard “$heard”. Please try again.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        _actions(palette, primaryLabel: 'Try again', onPrimary: _retry),
      ],
    );
  }

  Widget _deniedView(AppPalette palette) {
    return _messageView(
      palette,
      icon: Icons.mic_off_rounded,
      title: 'Microphone access needed',
      message: _service.permanentlyDenied
          ? 'Enable microphone access in Settings to use voice commands.'
          : 'INO needs the microphone to hear your voice commands.',
      primaryLabel: _service.permanentlyDenied ? 'Open Settings' : 'Try again',
      onPrimary: _service.permanentlyDenied ? _service.openSettings : _retry,
    );
  }

  Widget _messageView(
    AppPalette palette, {
    required IconData icon,
    required String title,
    required String message,
    bool showRetry = false,
    String? primaryLabel,
    VoidCallback? onPrimary,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: palette.textSecondary, size: 34),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(title, style: AppText.title.copyWith(color: palette.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        _actions(
          palette,
          primaryLabel: primaryLabel ?? (showRetry ? 'Try again' : null),
          onPrimary: onPrimary ?? (showRetry ? _retry : null),
        ),
      ],
    );
  }

  Widget _actions(
    AppPalette palette, {
    String? primaryLabel,
    VoidCallback? onPrimary,
  }) {
    return Row(
      children: [
        Expanded(
          child: PressableScale(
            child: Material(
              color: palette.surfaceVariant,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
                side: BorderSide(color: palette.border),
              ),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: SizedBox(
                  height: AppSizes.button,
                  child: Center(
                    child: Text(
                      'Close',
                      style: AppText.subtitle.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (primaryLabel != null && onPrimary != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: PressableScale(
              child: GestureDetector(
                onTap: onPrimary,
                child: Container(
                  height: AppSizes.button,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Center(
                    child: Text(
                      primaryLabel,
                      style: AppText.subtitle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The animated, pulsing microphone shown while listening.
class _PulsingMic extends StatelessWidget {
  const _PulsingMic({required this.pulse, required this.active});

  final Animation<double> pulse;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (active) ...[_ring(0.0), _ring(0.5)],
              child!,
            ],
          );
        },
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 38),
        ),
      ),
    );
  }

  /// One expanding, fading concentric ring. [phase] offsets it so two rings
  /// ripple out in sequence.
  Widget _ring(double phase) {
    final t = (pulse.value + phase) % 1.0;
    final size = 84.0 + t * 56.0;
    final opacity = (1.0 - t) * 0.35;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryGreen.withValues(alpha: opacity),
      ),
    );
  }
}

/// A centered label/value pair for the live "Recognized / Matched" readout.
class _LiveField extends StatelessWidget {
  const _LiveField({
    required this.palette,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final AppPalette palette;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: AppText.label.copyWith(
            color: palette.textFaint,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(
            color: accent ? AppColors.primaryGreen : palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}
