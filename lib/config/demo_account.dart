/// Demo / guest account configuration.
///
/// Used ONLY by the optional "Login as Guest" button on the login screen so
/// testers can enter a demo APK with a single tap. It does **not** bypass or
/// replace authentication - the credentials below are typed into the normal
/// email/password fields and signed in through the existing Supabase flow.
///
/// Production builds leave [isDemoBuild] false (the default). QA APKs enable
/// the button with `--dart-define=INO_DEMO_BUILD=true` and inject credentials
/// via `INO_DEMO_EMAIL` / `INO_DEMO_PASSWORD` so they are never baked into
/// release clients.
library;

/// Email of the demo account that lives in Supabase.
const String demoEmail = String.fromEnvironment(
  'INO_DEMO_EMAIL',
  defaultValue: 'demo@ino.app',
);

/// Password for the demo account. Empty unless passed at build time.
const String demoPassword = String.fromEnvironment('INO_DEMO_PASSWORD');

/// When `true`, the login screen shows the "Login as Guest" button.
const bool isDemoBuild = bool.fromEnvironment(
  'INO_DEMO_BUILD',
  defaultValue: false,
);

/// Dedicated Apple App Store Reviewer email configuration.
/// Can be overridden at build time via `--dart-define=INO_REVIEWER_EMAIL=...`.
const String reviewerEmail = String.fromEnvironment(
  'INO_REVIEWER_EMAIL',
  defaultValue: 'reviewer@ino.app',
);

/// Whether the identifier matches a known reviewer or demo account.
/// This allows the app to present email/password authentication to Apple
/// reviewers and QA testers without disrupting the passwordless OTP flow for
/// standard users.
bool isReviewerIdentifier(String input) {
  final trimmed = input.trim().toLowerCase();
  if (trimmed.isEmpty) return false;
  return trimmed == reviewerEmail.toLowerCase() ||
      trimmed == demoEmail.toLowerCase() ||
      trimmed == 'apple.review@ino.app' ||
      trimmed == 'reviewer@ino.app' ||
      trimmed.startsWith('reviewer@') ||
      trimmed.startsWith('apple.review@');
}
