import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/ino_back_button.dart';
import '../common/ino_background.dart';
import '../common/liquid_glass.dart';
import '../divine_glass/divine_glass.dart';
import '../pressable_scale.dart';

/// A consistent page chrome for every Profile sub-screen (Change Password,
/// Cloud Backup, About, …): a transparent back-button app bar over the themed
/// background, with the content laid out by the caller.
///
/// Under Launcher (Divine Glass), uses the Figma frosted Top App Bar with a
/// sky wash so headings always have a proper glass background and back control.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final launcher = InoStyle.usesDivineGlass(context);

    if (launcher) {
      return Scaffold(
        backgroundColor: palette.bg,
        extendBodyBehindAppBar: false,
        appBar: DivineGlassAppBar.asPreferredSize(
          context,
          title: title,
          centerTitle: false,
          actions: actions,
        ),
        body: InoBackground(
          showDots: false,
          sky: true,
          child: SafeArea(
            top: false,
            child: child,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: palette.bg,
      // Let the aurora backdrop flow up behind the transparent app bar.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Center(child: InoBackButton(size: 42)),
        ),
        title: Text(
          title,
          style: AppText.appBarHeading(palette.headingInk, prominent: true),
        ),
        centerTitle: true,
        actions: actions,
      ),
      body: InoBackground(
        showDots: false,
        child: SafeArea(
          top: false,
          child: Padding(
            // Re-apply the inset the extended body no longer receives.
            padding: EdgeInsets.only(
              top: kToolbarHeight + MediaQuery.paddingOf(context).top,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A rounded, grouped container (matches the Profile settings groups) for use as
/// a section card inside a sub-screen.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final launcher = InoStyle.usesDivineGlass(context);

    if (launcher) {
      return LiquidGlass(
        borderRadius: BorderRadius.circular(AppRadius.card),
        blur: 20,
        padding: padding ?? const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(width: double.infinity, child: child),
      );
    }

    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: child,
    );
  }
}

/// A full-width brand-gradient primary button with a busy spinner. Mirrors the
/// auth CTA but is dark-aware and usable outside the auth flow.
class SettingsPrimaryButton extends StatelessWidget {
  const SettingsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final disabled = busy || onPressed == null;
    return PressableScale(
      pressedScale: disabled ? 1.0 : 0.97,
      child: Opacity(
        opacity: disabled && !busy ? 0.6 : 1,
        child: GestureDetector(
          onTap: disabled ? null : onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              gradient: danger ? null : InoStyle.gradient(context, AppColors.brandGradient),
              color: danger ? AppColors.critical : null,
              // Divine Glass CTA: a full pill, not a rounded rectangle.
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: [
                BoxShadow(
                  color: (danger ? AppColors.critical : AppColors.primaryGreen)
                      .withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
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
