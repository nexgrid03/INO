import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile/settings_scaffold.dart';

/// One heading + body paragraph in a legal document.
///
/// Both fields hold localization keys, resolved at build time. A plain string
/// still renders as-is because [AppLocalizations.t] falls back to the key.
class LegalSection {
  const LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}

/// A reusable reader for legal text (Privacy Policy, Terms & Conditions),
/// rendered in-app from bundled content so it works offline and matches the
/// app's look - no external webview needed.
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
        title: 'privacyPolicy',
        updated: 'legalLastUpdated',
        sections: [
          LegalSection('overview', 'privacyOverviewBody'),
          LegalSection('privacyCollectHeading', 'privacyCollectBody'),
          LegalSection('privacyStorageHeading', 'privacyStorageBody'),
          LegalSection('privacyBiometricsHeading', 'privacyBiometricsBody'),
          LegalSection('privacyProcessorsHeading', 'privacyProcessorsBody'),
          LegalSection('privacyRightsHeading', 'privacyRightsBody'),
          LegalSection('privacyControlsHeading', 'privacyControlsBody'),
          LegalSection('privacyContactHeading', 'privacyContactBody'),
        ],
      );

  /// The INO Terms & Conditions.
  factory LegalDocumentScreen.terms() => const LegalDocumentScreen(
        title: 'termsConditions',
        updated: 'legalLastUpdated',
        sections: [
          LegalSection('termsAcceptanceHeading', 'termsAcceptanceBody'),
          LegalSection('termsAccountHeading', 'termsAccountBody'),
          LegalSection('termsAcceptableUseHeading', 'termsAcceptableUseBody'),
          LegalSection('termsContentHeading', 'termsContentBody'),
          LegalSection('termsLiabilityHeading', 'termsLiabilityBody'),
          LegalSection('termsChangesHeading', 'termsChangesBody'),
        ],
      );

  static Widget _buildBodyWithLinks(String text, AppPalette palette) {
    final linkRegex = RegExp(
      r'(https?:\/\/[^\s\)\.\,]+(?:\.[^\s\)\.\,]+)*|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})',
    );
    final matches = linkRegex.allMatches(text);
    if (matches.isEmpty) {
      return Text(
        text,
        style: AppText.body.copyWith(color: palette.textSecondary, height: 1.6),
      );
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: AppText.body.copyWith(color: palette.textSecondary, height: 1.6),
        ));
      }

      final matchedText = match.group(0)!;
      final isEmail = matchedText.contains('@') && !matchedText.startsWith('http');
      final targetUri = isEmail ? Uri.parse('mailto:$matchedText') : Uri.parse(matchedText);

      spans.add(
        TextSpan(
          text: matchedText,
          style: AppText.body.copyWith(
            color: AppColors.primaryGreen,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
            height: 1.6,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              try {
                if (await canLaunchUrl(targetUri)) {
                  await launchUrl(
                    targetUri,
                    mode: isEmail
                        ? LaunchMode.platformDefault
                        : LaunchMode.externalApplication,
                  );
                }
              } catch (_) {}
            },
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: AppText.body.copyWith(color: palette.textSecondary, height: 1.6),
      ));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SettingsScaffold(
      title: l10n.t(title),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xl),
        children: [
          // "Last updated" pill chip - foam fill, hairline, brand glyph.
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: palette.isDark
                    ? palette.surfaceVariant
                    : AppColors.tealFoam,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Icon(Icons.verified_user_rounded,
                      size: 14, color: AppColors.primaryGreen),
                  const SizedBox(width: 6),
                  Text(l10n.t(updated),
                      style: AppText.caption.copyWith(
                          color: palette.textSecondary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final s in sections) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                gradient: palette.cardGradient,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: palette.border),
                boxShadow: palette.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.t(s.heading),
                      style:
                          AppText.title.copyWith(color: palette.textPrimary)),
                  const SizedBox(height: AppSpacing.xs),
                  _buildBodyWithLinks(l10n.t(s.body), palette),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
