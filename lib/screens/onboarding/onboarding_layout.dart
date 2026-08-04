/// Layout metrics taken from the committed [SecuredIntroScreen]
/// ("Your Documents Are Secured") — the source of truth for onboarding
/// placement. Keep the three onboarding slides aligned to these values.
class OnboardingLayout {
  OnboardingLayout._();

  /// Lock-scene box on SecuredIntroScreen.
  static const double sceneSize = 300;

  /// Minimum scene side on very short phones (SE / small Android).
  static const double sceneMin = 200;

  /// Scale of the 160px onboarding icon stack inside [sceneSize].
  /// ~1.35 → ~216px circle, closer to the secured intro ring (~210).
  static const double illustrationScale = 1.35;

  /// Copy horizontal inset (`Padding.symmetric(horizontal: 34)`).
  static const double textHorizontal = 34;

  /// CTA horizontal inset (`fromLTRB(28, 0, 28, …)`).
  static const double bottomHorizontal = 28;

  /// Extra space under Skip / Get Started (on top of [SafeArea]).
  /// Higher than before so Skip isn't flush with the screen edge on SE.
  static const double bottomPadding = 36;

  /// Minimum bottom inset even when the device reports 0 safe padding
  /// (Chrome device mode / some Android gesture bars).
  static const double safeBottomMinimum = 16;

  /// Title style on SecuredIntroScreen.
  static const double titleSize = 27;
  static const double titleHeight = 1.15;

  /// Vertical rhythm: Spacer(flex: 5) → scene → Spacer(2) → copy → Spacer(2) → CTA.
  static const int spacerTop = 5;
  static const int spacerMid = 2;
  static const int spacerBottom = 2;
}
