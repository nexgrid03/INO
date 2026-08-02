import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/common/success_tick_mark.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';

/// Full-screen confirmation after a document is uploaded / saved to a wallet.
///
/// Matches the Figma success frame: pulsing tick, "Success" title, document
/// summary card with ENCRYPTED badge, and a Done CTA that pops the stack.
class DocumentUploadSuccessScreen extends StatefulWidget {
  const DocumentUploadSuccessScreen({
    super.key,
    required this.documentName,
    required this.walletLabel,
    this.encrypted = false,
  });

  final String documentName;
  final String walletLabel;
  final bool encrypted;

  @override
  State<DocumentUploadSuccessScreen> createState() =>
      _DocumentUploadSuccessScreenState();
}

class _DocumentUploadSuccessScreenState
    extends State<DocumentUploadSuccessScreen> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  void _done() {
    // Pop this success screen and the Add Document form underneath.
    final nav = Navigator.of(context);
    nav.pop(); // success
    if (nav.canPop()) nav.pop(true); // add form
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        body: InoBackground(
          sky: true,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.lg,
                AppSpacing.screen,
                AppSpacing.xl,
              ),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  const SuccessTickMark(size: 92),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('success'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.t('documentSavedSecurely'),
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(
                      color: palette.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  InoCard(
                    radius: AppRadius.card,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.description_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.documentName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.subtitle.copyWith(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                l10n
                                    .t('savedToWalletLabel')
                                    .replaceAll('{wallet}', widget.walletLabel),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.encrypted) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen
                                  .withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              l10n.t('encryptedBadge'),
                              style: const TextStyle(
                                color: AppColors.primaryGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(flex: 3),
                  PressableScale(
                    child: GestureDetector(
                      onTap: _done,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 54,
                        width: double.infinity,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryGreen
                                  .withValues(alpha: 0.32),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Text(
                          l10n.t('done'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
