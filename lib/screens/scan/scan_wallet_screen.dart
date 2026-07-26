import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/wallet_repository.dart' show SupabaseWalletRepository;
import '../../l10n/app_localizations.dart';
import '../../models/wallet_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/shiny_icon.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet/create_wallet_sheet.dart';
import '../../widgets/wallet/wallet_grid.dart' show localizedWalletName;

/// Screen 5 - "Where should this go?".
///
/// The last decision before saving a scan: which wallet files it. Every wallet
/// the user has is listed (built-ins + their own), the OCR suggestion is
/// pre-selected and badged as such, and a "Create new wallet" row means a
/// document never has to be filed somewhere that doesn't fit.
///
/// Shown only when the flow was started WITHOUT a wallet already in hand (Home,
/// the quick menu, voice). Scanning from inside a wallet skips this step - that
/// wallet is the answer.
class ScanWalletScreen extends StatefulWidget {
  const ScanWalletScreen({
    super.key,
    required this.suggestedWallet,
    required this.onBack,
    required this.onSelected,
  });

  /// The wallet OCR proposed - pre-selected, and marked "Suggested" in the list.
  final String suggestedWallet;

  final VoidCallback onBack;

  /// Called with the wallet the user committed to.
  final ValueChanged<String> onSelected;

  @override
  State<ScanWalletScreen> createState() => _ScanWalletScreenState();
}

class _ScanWalletScreenState extends State<ScanWalletScreen> {
  /// Read fresh on every build so a wallet created from the sheet below is in
  /// the list immediately.
  List<WalletCategory> get _wallets => SupabaseWalletRepository.categories;

  late String _selected = widget.suggestedWallet;

  Future<void> _createWallet() async {
    final created = await showCreateWalletSheet(context);
    if (created == null || !mounted) return;
    // A wallet made for this document is obviously the one it goes into.
    setState(() => _selected = created.name);
  }

  void _confirm() {
    HapticFeedback.selectionClick();
    widget.onSelected(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final wallets = _wallets;
    // A suggestion for a wallet that no longer exists shouldn't be badged.
    final hasSuggestion = wallets.any((w) => w.name == widget.suggestedWallet);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: widget.onBack),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  0,
                  AppSpacing.screen,
                  AppSpacing.lg,
                ),
                children: [
                  for (var i = 0; i < wallets.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: FadeSlideIn(
                        delay: Duration(milliseconds: (i * 40).clamp(0, 320)),
                        child: _WalletOption(
                          category: wallets[i],
                          selected: wallets[i].name == _selected,
                          suggested:
                              hasSuggestion &&
                              wallets[i].name == widget.suggestedWallet,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = wallets[i].name);
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  _CreateWalletRow(onTap: _createWallet),
                ],
              ),
            ),
            _ActionBar(
              walletLabel: localizedWalletName(l10n, _selected),
              onContinue: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable wallet row: its own icon and accent, a "Suggested" badge on
/// the OCR pick, and a check when chosen.
class _WalletOption extends StatelessWidget {
  const _WalletOption({
    required this.category,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });

  final WalletCategory category;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final accent = category.gradient.first;

    // InoCard's own onTap gives the ripple + brand "squish"; the selected row
    // carries the brand edge, the rest keep the hairline border.
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      onTap: onTap,
      borderColor: selected ? AppColors.primaryGreen : null,
      child: Row(
        children: [
          ShinyIcon(
            icon: category.icon,
            color: accent,
            size: AppSizes.iconContainer,
            iconSize: 22,
            radius: AppRadius.chip,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        localizedWalletName(l10n, category.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (suggested) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          l10n.t('suggested'),
                          style: AppText.label.copyWith(
                            color: AppColors.primaryGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  category.contents.take(3).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 23,
            color: selected ? AppColors.primaryGreen : palette.textFaint,
          ),
        ],
      ),
    );
  }
}

/// "Create new wallet" - a dashed-feel row that opens the Create Wallet sheet
/// and selects whatever it creates.
class _CreateWalletRow extends StatelessWidget {
  const _CreateWalletRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return PressableScale(
      pressedScale: 0.985,
      child: Material(
        color: palette.surfaceVariant,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: palette.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm + 2),
            child: Row(
              children: [
                Container(
                  width: AppSizes.iconContainer,
                  height: AppSizes.iconContainer,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: AppColors.primaryGreen,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.t('createNewWallet'),
                    style: AppText.subtitle.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.textFaint,
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onBack,
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 21,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('whereToSave'),
                  style: AppText.headline.copyWith(
                    color: palette.textPrimary,
                    fontSize: 21,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.t('whereToSaveSubtitle'),
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom bar: one brand CTA naming the wallet the document is going into, so
/// the destination is unmissable even without scrolling back up.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.walletLabel, required this.onContinue});

  final String walletLabel;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.sm,
            AppSpacing.screen,
            AppSpacing.sm,
          ),
          child: PressableScale(
            child: Container(
              height: AppSizes.button,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(AppRadius.button),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onContinue,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${AppLocalizations.of(context).t('saveTo')} '
                            '$walletLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.subtitle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
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
    );
  }
}
