import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/voice_greeting_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// A small, non-blocking "Mute greeting" pill shown at the top of the shell
/// while the spoken welcome greeting is playing.
///
/// Tapping it silences the greeting IMMEDIATELY and persists
/// `welcomeSound = false` (via [VoiceGreetingService.muteNow]) so it won't play
/// on the next launch either — no confirmation dialog, the mute intent is
/// honoured instantly. The pill auto-dismisses when the greeting finishes or
/// after 3 seconds, whichever comes first.
///
/// Renders nothing (zero layout, no hit-testing) whenever the greeting isn't
/// audible, so hosting it costs nothing on every other launch.
class WelcomeSoundPill extends StatefulWidget {
  const WelcomeSoundPill({super.key});

  @override
  State<WelcomeSoundPill> createState() => _WelcomeSoundPillState();
}

class _WelcomeSoundPillState extends State<WelcomeSoundPill> {
  final ValueNotifier<bool> _speaking = VoiceGreetingService.instance.speaking;

  bool _visible = false;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _speaking.addListener(_onSpeakingChanged);
    // The greeting can already be mid-utterance when the shell (re)builds.
    if (_speaking.value) _show();
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _speaking.removeListener(_onSpeakingChanged);
    super.dispose();
  }

  void _onSpeakingChanged() {
    if (!mounted) return;
    _speaking.value ? _show() : _hide();
  }

  void _show() {
    setState(() => _visible = true);
    _autoDismiss?.cancel();
    // Auto-dismiss after 3s even if the greeting is still finishing — the
    // pill is a moment-of-playback affordance, not a persistent banner.
    _autoDismiss = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _hide() {
    _autoDismiss?.cancel();
    if (_visible) setState(() => _visible = false);
  }

  Future<void> _mute() async {
    _hide();
    await VoiceGreetingService.instance.muteNow();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        offset: _visible ? Offset.zero : const Offset(0, -1.2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: _visible ? 1 : 0,
          child: Center(
            child: Semantics(
              button: true,
              label: l10n.t('muteGreeting'),
              child: PressableScale(
                pressedScale: 0.94,
                child: Material(
                  color: palette.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    side: BorderSide(color: palette.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  elevation: 0,
                  child: InkWell(
                    onTap: _mute,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.volume_off_rounded,
                              size: 18, color: AppColors.primaryGreen),
                          const SizedBox(width: 7),
                          Text(
                            l10n.t('muteGreeting'),
                            style: AppText.caption.copyWith(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
