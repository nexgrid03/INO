import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile/settings_scaffold.dart';
import 'contact_support_screen.dart';

class _Faq {
  const _Faq(this.question, this.answer, this.tags);
  final String question;
  final String answer;
  final String tags;
}

const List<_Faq> _faqs = [
  _Faq(
    'How do I add a document?',
    'Tap the + button on Home or Wallet, choose a category, then scan with your '
        'camera or import from your gallery. INO enhances the image and saves it '
        'securely to your vault.',
    'add upload scan import document',
  ),
  _Faq(
    'How do I protect a document with biometrics?',
    'Open a document’s menu and choose “Protect”, or toggle “Protect with '
        'Biometrics” when adding it. Protected documents require Face/Fingerprint '
        'unlock before they can be opened.',
    'biometric protect lock face fingerprint security',
  ),
  _Faq(
    'Is my data encrypted?',
    'Your files are stored in a private, access-controlled cloud bucket and are '
        'only reachable with your signed-in session. Protected items add a '
        'biometric gate on top.',
    'encryption security private storage safe',
  ),
  _Faq(
    'How do backups work?',
    'Cloud Backup creates a JSON archive of your account and document metadata '
        'and uploads it to your private storage. Turn on Auto Backup to keep it '
        'current, or back up manually any time.',
    'backup cloud restore export sync',
  ),
  _Faq(
    'How do I enable two-factor authentication?',
    'Go to Security → Two-Factor Authentication, tap Enable, add the setup key '
        'to an authenticator app, and enter the 6-digit code to confirm.',
    '2fa two factor totp authenticator security code',
  ),
  _Faq(
    'How do I change or reset my password?',
    'Security → Change Password. Confirm your current password, then set a new, '
        'strong one. You’ll see a live strength meter as you type.',
    'password change reset credential security',
  ),
  _Faq(
    'Can I use INO in dark mode?',
    'Yes — Preferences → Dark Mode. Your choice is remembered across restarts '
        'and applies instantly across the whole app.',
    'dark mode theme appearance light',
  ),
  _Faq(
    'How do I delete my account?',
    'Scroll to the bottom of Profile and choose Delete Account. You’ll confirm, '
        're-enter your password, and then your documents, files and profile are '
        'permanently removed.',
    'delete account remove erase data privacy',
  ),
];

/// Help Center — searchable FAQ with a shortcut to Contact Support.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key, this.supportEmail});

  final String? supportEmail;

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _query = TextEditingController();
  String _term = '';

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      final t = _query.text.trim().toLowerCase();
      if (t != _term) setState(() => _term = t);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<_Faq> get _results {
    if (_term.isEmpty) return _faqs;
    return _faqs
        .where((f) =>
            f.question.toLowerCase().contains(_term) ||
            f.answer.toLowerCase().contains(_term) ||
            f.tags.contains(_term))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final results = _results;
    return SettingsScaffold(
      title: 'Help Center',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, AppSpacing.xs, AppSpacing.screen, AppSpacing.sm),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search help…',
                hintStyle: TextStyle(color: palette.textFaint),
                prefixIcon:
                    Icon(Icons.search_rounded, color: palette.textSecondary),
                suffixIcon: _term.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: palette.textSecondary),
                        onPressed: _query.clear,
                      ),
                filled: true,
                fillColor: palette.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  borderSide: const BorderSide(
                      color: AppColors.primaryGreen, width: 1.4),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.xs,
                  AppSpacing.screen, AppSpacing.xl),
              children: [
                if (results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xl),
                    child: Column(
                      children: [
                        Icon(Icons.help_outline_rounded,
                            color: palette.textFaint, size: 40),
                        const SizedBox(height: AppSpacing.sm),
                        Text('No results for “${_query.text.trim()}”',
                            style: AppText.body
                                .copyWith(color: palette.textSecondary)),
                      ],
                    ),
                  )
                else
                  for (final f in results) _FaqTile(faq: f),
                const SizedBox(height: AppSpacing.lg),
                SettingsCard(
                  child: Row(
                    children: [
                      const Icon(Icons.support_agent_rounded,
                          color: AppColors.primaryGreen),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Still need help?',
                            style: AppText.subtitle
                                .copyWith(color: palette.textPrimary)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ContactSupportScreen(
                                supportEmail: widget.supportEmail),
                          ),
                        ),
                        child: const Text('Contact us',
                            style: TextStyle(
                                color: AppColors.primaryGreen,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.faq});

  final _Faq faq;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: palette.border),
          boxShadow: palette.cardShadow,
        ),
        // A Material provides the surface colour + ink target for the
        // ExpansionTile's internal ListTile (no colored box in between).
        child: Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.button),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              iconColor: AppColors.primaryGreen,
              collapsedIconColor: palette.textSecondary,
              title: Text(faq.question,
                  style: AppText.subtitle.copyWith(color: palette.textPrimary)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(faq.answer,
                      style: AppText.body.copyWith(
                          color: palette.textSecondary, height: 1.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
