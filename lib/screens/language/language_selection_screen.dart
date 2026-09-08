import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/ino_logo.dart';
import '../../widgets/pressable_scale.dart';
import '../auth/login_screen.dart';

/// Language configuration descriptor for the selection page.
class _LanguageOption {
  const _LanguageOption({
    required this.code,
    required this.title,
    required this.subtitle,
    required this.letterGlyph,
  });

  final String code;
  final String title;
  final String subtitle;
  final String letterGlyph;
}

/// Standalone, premium Language Selection Screen presented before the Login page.
///
/// Features INO's brand shield logo at the top, signature teal brand theme,
/// pill tag header, and a full-width brand gradient "Continue →" CTA.
class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({
    super.key,
    this.targetMode = AuthMode.signIn,
    this.onContinue,
  });

  final AuthMode targetMode;
  final VoidCallback? onContinue;

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  late String _selectedCode;

  static const List<_LanguageOption> _options = [
    _LanguageOption(
      code: 'en',
      title: 'English',
      subtitle: 'English (अंग्रेज़ी)',
      letterGlyph: 'A',
    ),
    _LanguageOption(
      code: 'hi',
      title: 'हिंदी',
      subtitle: 'Hindi (हिंदी)',
      letterGlyph: 'अ',
    ),
    _LanguageOption(
      code: 'te',
      title: 'తెలుగు',
      subtitle: 'Telugu (తెలుగు)',
      letterGlyph: 'అ',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Default to the currently active language in AppSettings or 'en'
    _selectedCode = AppSettings.instance.language.value;
    if (!_options.any((o) => o.code == _selectedCode)) {
      _selectedCode = 'en';
    }
  }

  Future<void> _handleContinue() async {
    HapticFeedback.mediumImpact();
    // Persist language selection globally
    await AppSettings.instance.setLanguage(_selectedCode);

    if (!mounted) return;

    if (widget.onContinue != null) {
      widget.onContinue!();
      return;
    }

    // Navigate to LoginScreen with the specified AuthMode
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) => LoginScreen(initialMode: widget.targetMode),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = palette.isDark;

    return AuthScaffold(
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),

          // Brand Logo: INO Shield Logo at the top
          FadeSlideIn(
            child: const Center(child: InoLogo(size: 64)),
          ),

          const SizedBox(height: 20),

          // Pill Badge: "文A भाषा • Language" in INO teal brand style
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? palette.surfaceVariant
                      : AppColors.tealPale.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? palette.border
                        : AppColors.primaryGreen.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.translate_rounded,
                      size: 16,
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'भाषा • Language',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Main Headline: "Choose your language" with INO brand gradient styling
          FadeSlideIn(
            delay: const Duration(milliseconds: 100),
            child: ShaderMask(
              shaderCallback: (bounds) =>
                  AppColors.brandGradient.createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Text(
                'Choose your language',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Subtitle: "You can change this anytime in Settings"
          FadeSlideIn(
            delay: const Duration(milliseconds: 140),
            child: Text(
              'You can change this anytime in Settings',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: palette.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Language Option Cards
          ...List.generate(_options.length, (index) {
            final option = _options[index];
            final isSelected = _selectedCode == option.code;

            return FadeSlideIn(
              delay: Duration(milliseconds: 180 + (index * 60)),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _LanguageCard(
                  option: option,
                  isSelected: isSelected,
                  isDark: isDark,
                  palette: palette,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCode = option.code);
                  },
                ),
              ),
            );
          }),

          const SizedBox(height: 20),

          // Bottom CTA Button: "Continue →" in INO Brand Gradient
          FadeSlideIn(
            delay: const Duration(milliseconds: 360),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: PressableScale(
                child: InkWell(
                  onTap: _handleContinue,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryGreen.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Continue',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom card widget for each selectable language option themed with INO brand styles.
class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.option,
    required this.isSelected,
    required this.isDark,
    required this.palette,
    required this.onTap,
  });

  final _LanguageOption option;
  final bool isSelected;
  final bool isDark;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? AppColors.primaryGreen.withValues(alpha: 0.14)
                    : AppColors.tealFoam)
                : (isDark ? palette.surface : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryGreen
                  : (isDark
                      ? palette.border
                      : palette.border.withValues(alpha: 0.6)),
              width: isSelected ? 1.8 : 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Letter glyph box (e.g. "A", "अ", "అ")
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.brandGradient : null,
                  color: isSelected
                      ? null
                      : (isDark
                          ? palette.surfaceVariant
                          : AppColors.tealPale.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  option.letterGlyph,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isSelected
                        ? Colors.white
                        : AppColors.primaryGreen,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Title and Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      option.subtitle,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Selection Indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppColors.primaryGreen : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryGreen
                        : (isDark
                            ? palette.border
                            : const Color(0xFFD1D5DB)),
                    width: isSelected ? 0 : 2,
                  ),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
