import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile/settings_scaffold.dart';

/// One heading + body paragraph in a legal document.
class LegalSection {
  const LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}

/// A reusable reader for legal text (Privacy Policy, Terms & Conditions),
/// rendered in-app from bundled content so it works offline and matches the
/// app's look — no external webview needed.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.updated,
    required this.sections,
  });

  final String title;
  final String updated;
  final List<LegalSection> sections;

  /// The INO Privacy Policy.
  factory LegalDocumentScreen.privacy() => const LegalDocumentScreen(
        title: 'Privacy Policy',
        updated: 'Last updated: July 2026',
        sections: [
          LegalSection(
            'Overview',
            'INO (Intelligent Network Organizer) helps you store and organize your '
                'personal documents securely. This policy explains what we collect, '
                'how we use it, and the choices you have.',
          ),
          LegalSection(
            'Information we collect',
            'Account details you provide (name, email, phone), the documents and '
                'metadata you add, and basic app preferences. We do not sell your '
                'personal data.',
          ),
          LegalSection(
            'How your documents are stored',
            'Files are kept in a private, access-controlled cloud bucket reachable '
                'only with your authenticated session. Documents you mark as protected '
                'require on-device biometric authentication before they can be opened.',
          ),
          LegalSection(
            'Biometrics',
            'Biometric checks happen entirely on your device through the operating '
                'system. INO never receives, stores, or transmits your fingerprint or '
                'face data — only a secure on/off preference.',
          ),
          LegalSection(
            'Your controls',
            'You can export or download all your data at any time, back it up to the '
                'cloud, and permanently delete your account — which removes your '
                'documents, files and profile.',
          ),
          LegalSection(
            'Contact',
            'Questions about privacy? Reach us from Profile → Contact Support.',
          ),
        ],
      );

  /// The INO Terms & Conditions.
  factory LegalDocumentScreen.terms() => const LegalDocumentScreen(
        title: 'Terms & Conditions',
        updated: 'Last updated: July 2026',
        sections: [
          LegalSection(
            'Acceptance',
            'By using INO you agree to these terms. If you don’t agree, please don’t '
                'use the app.',
          ),
          LegalSection(
            'Your account',
            'You’re responsible for keeping your credentials safe and for the activity '
                'on your account. Enable biometric lock and two-factor authentication '
                'for extra protection.',
          ),
          LegalSection(
            'Acceptable use',
            'Use INO only for lawful purposes and only for documents you have the '
                'right to store. Don’t attempt to disrupt or reverse-engineer the '
                'service.',
          ),
          LegalSection(
            'Your content',
            'You retain ownership of everything you upload. You grant INO the limited '
                'permission needed to store and display your content back to you.',
          ),
          LegalSection(
            'Availability & liability',
            'The service is provided “as is”. We work to keep it reliable but can’t '
                'guarantee uninterrupted availability, and we’re not liable for '
                'indirect losses to the extent permitted by law.',
          ),
          LegalSection(
            'Changes',
            'We may update these terms; continued use after an update means you accept '
                'the revised terms.',
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsScaffold(
      title: title,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xl),
        children: [
          Text(updated,
              style: AppText.caption.copyWith(color: palette.textFaint)),
          const SizedBox(height: AppSpacing.lg),
          for (final s in sections) ...[
            Text(s.heading,
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(s.body,
                style: AppText.body
                    .copyWith(color: palette.textSecondary, height: 1.6)),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}
