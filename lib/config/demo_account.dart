/// Demo / guest account configuration.
///
/// Used ONLY by the optional "Login as Guest" button on the login screen so
/// testers can enter a demo APK with a single tap. It does **not** bypass or
/// replace authentication — the credentials below are typed into the normal
/// email/password fields and signed in through the existing Supabase flow.
///
/// To point the guest button at a different demo user, change [demoEmail] /
/// [demoPassword]. To remove the button from a production build, flip
/// [isDemoBuild] to `false` — the code stays in place but the button is hidden.
library;

/// Email of the demo account that lives in Supabase.
const String demoEmail = 'demo@ino.app';

/// Password for the demo account above.
const String demoPassword = 'DemoUser@123';

/// When `true`, the login screen shows the "Login as Guest" button.
/// Set to `false` for production releases to hide it completely.
const bool isDemoBuild = true;
