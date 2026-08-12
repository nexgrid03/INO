import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/liquid_glass.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/profile/settings_scaffold.dart';
import 'contact_support_screen.dart';

/// One FAQ entry. The question and answer are held as translation *keys* so the
/// list stays const while the text follows the app language; [tags] are
/// language-independent search aliases (kept in English so an English query
/// still matches while browsing in another language).
class _Faq {
  const _Faq(this.questionKey, this.answerKey, this.tags);
  final String questionKey;
  final String answerKey;
  final String tags;
}

const List<_Faq> _faqs = [
  _Faq('faqAddDocQ', 'faqAddDocA', 'add upload scan import document'),
  _Faq('faqProtectQ', 'faqProtectA',
      'biometric protect lock face fingerprint security'),
  _Faq('faqEncryptedQ', 'faqEncryptedA',
      'encryption security private storage safe'),
  _Faq('faqBackupQ', 'faqBackupA', 'backup cloud restore export sync'),
  _Faq('faq2faQ', 'faq2faA',
      '2fa two factor totp authenticator security code'),
  _Faq('faqPasswordQ', 'faqPasswordA',
      'password change reset credential security'),
  _Faq('faqDarkModeQ', 'faqDarkModeA', 'dark mode theme appearance light'),
  _Faq('faqDeleteQ', 'faqDeleteA',
      'delete account remove erase data privacy'),
];

/// Help Center - searchable FAQ with a shortcut to Contact Support.
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

  List<_Faq> _results(AppLocalizations l10n) {
    if (_term.isEmpty) return _faqs;
    return _faqs
        .where((f) =>
            l10n.t(f.questionKey).toLowerCase().contains(_term) ||
            l10n.t(f.answerKey).toLowerCase().contains(_term) ||
            f.tags.contains(_term))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final results = _results(l10n);
    final glass = divineGlassEnabled(context);

    return SettingsScaffold(
      title: l10n.t('helpCenter'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.xs,
              AppSpacing.screen,
              AppSpacing.sm,
            ),
            child: _HelpSearchField(
              controller: _query,
              term: _term,
              glass: glass,
              hint: l10n.t('searchHelp'),
            ),
          ),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.xs,
                AppSpacing.screen,
                AppSpacing.xl,
              ),
              children: [
                if (results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xl),
                    child: Column(
                      children: [
                        Icon(Icons.help_outline_rounded,
                            color: palette.textFaint, size: 40),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          l10n
                              .t('helpNoResults')
                              .replaceFirst('{q}', _query.text.trim()),
                          style: AppText.body
                              .copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  )
                else
                  for (final f in results) _FaqTile(faq: f, glass: glass),
                const SizedBox(height: AppSpacing.lg),
                SettingsCard(
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              AppColors.primaryGreen.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.support_agent_rounded,
                          color: AppColors.primaryGreen,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.t('stillNeedHelp'),
                          style: AppText.subtitle
                              .copyWith(color: palette.textPrimary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ContactSupportScreen(
                              supportEmail: widget.supportEmail,
                            ),
                          ),
                        ),
                        child: Text(
                          l10n.t('contactUs'),
                          style: TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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

class _HelpSearchField extends StatelessWidget {
  const _HelpSearchField({
    required this.controller,
    required this.term,
    required this.glass,
    required this.hint,
  });

  final TextEditingController controller;
  final String term;
  final bool glass;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final field = TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: palette.textFaint),
        prefixIcon: Icon(Icons.search_rounded, color: palette.textSecondary),
        suffixIcon: term.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close_rounded, color: palette.textSecondary),
                onPressed: controller.clear,
              ),
        filled: !glass,
        fillColor: glass ? Colors.transparent : palette.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: glass
              ? BorderSide.none
              : BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: glass
              ? BorderSide.none
              : BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: glass
              ? BorderSide(
                  color: AppColors.primaryGreen.withValues(alpha: 0.45),
                  width: 1.2,
                )
              : BorderSide(color: AppColors.primaryGreen, width: 1.4),
        ),
      ),
    );

    if (!glass) return field;

    return LiquidGlass(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      blur: 18,
      frost: 0.55,
      padding: EdgeInsets.zero,
      child: field,
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.faq, required this.glass});

  final _Faq faq;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    final tile = Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        iconColor: AppColors.primaryGreen,
        collapsedIconColor: palette.textSecondary,
        title: Text(
          l10n.t(faq.questionKey),
          style: AppText.subtitle.copyWith(color: palette.textPrimary),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.t(faq.answerKey),
              style: AppText.body.copyWith(
                color: palette.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: glass
          ? AdaptiveGlassCard(
              padding: EdgeInsets.zero,
              radius: 20,
              child: Material(
                type: MaterialType.transparency,
                child: tile,
              ),
            )
          : Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.border),
              ),
              child: Material(
                color: palette.surface,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: tile,
              ),
            ),
    );
  }
}
