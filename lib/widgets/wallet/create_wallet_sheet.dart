import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/wallet_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/ino_options_sheet.dart';
import '../pressable_scale.dart';

/// Opens the Create Wallet sheet and returns the created [CustomWallet], or
/// null if the user dismissed it. The wallet is already persisted to
/// [CustomWalletStore] by the time this resolves.
///
/// Phone: capped bottom sheet (not full-screen). Wide / desktop / web: centered
/// dialog popup so it never occupies the entire viewport.
Future<CustomWallet?> showCreateWalletSheet(BuildContext context) {
  final palette = AppPalette.of(context);
  final width = MediaQuery.sizeOf(context).width;
  final useDialog = width >= 600;
  // Force solid opaque sheet chrome — never translucent glass over the scrim.
  final sheetBg = palette.isDark ? palette.surface : Colors.white;

  if (useDialog) {
    return showDialog<CustomWallet>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.85;
        final inset = MediaQuery.viewInsetsOf(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: inset.bottom),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                maxHeight: maxH,
              ),
              child: Material(
                color: sheetBg,
                borderRadius: BorderRadius.circular(AppRadius.large),
                clipBehavior: Clip.antiAlias,
                child: const CreateWalletSheet(asDialog: true),
              ),
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<CustomWallet>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: sheetBg,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.85;
      return Theme(
        data: Theme.of(ctx).copyWith(
          bottomSheetTheme: BottomSheetThemeData(
            backgroundColor: sheetBg,
            modalBackgroundColor: sheetBg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          canvasColor: sheetBg,
        ),
        child: SafeArea(
          child: ColoredBox(
            color: sheetBg,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: const CreateWalletSheet(),
            ),
          ),
        ),
      );
    },
  );
}

/// A premium bottom sheet for creating a wallet of your own: a name field
/// (validated, de-duplicated against built-ins too), an icon picker and an
/// accent picker, with a live preview of the card it will become.
class CreateWalletSheet extends StatefulWidget {
  const CreateWalletSheet({super.key, this.asDialog = false});

  /// When true, content is framed for a centered dialog (rounded on all sides).
  final bool asDialog;

  @override
  State<CreateWalletSheet> createState() => _CreateWalletSheetState();
}

class _CreateWalletSheetState extends State<CreateWalletSheet> {
  final _controller = TextEditingController();
  String _iconKey = 'folder';
  int _colorValue = kWalletAccentValues.first;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.t('enterWalletName'));
      return;
    }
    if (name.length < 2) {
      setState(() => _error = l10n.t('nameTooShort'));
      return;
    }
    if (CustomWalletStore.instance.exists(name)) {
      setState(() => _error = l10n.t('walletAlreadyExists'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final CustomWallet created;
    try {
      created = await CustomWalletStore.instance.add(
        CustomWallet(name: name, iconKey: _iconKey, colorValue: _colorValue),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.t('somethingWentWrong');
      });
      return;
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(created);
  }

  Widget _previewRow(AppLocalizations l10n, Color color, AppPalette palette) {
    // Same borderless chip as [WalletGrid] tiles — no accent ring.
    return Row(
      children: [
        Container(
          width: AppSizes.iconContainer,
          height: AppSizes.iconContainer,
          decoration: BoxDecoration(
            color: color.withValues(alpha: palette.isDark ? 0.22 : 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            walletIconFor(_iconKey),
            color: color,
            size: 26,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _controller.text.trim().isEmpty
                    ? l10n.t('newWallet')
                    : _controller.text.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.headline.copyWith(
                  color: palette.textPrimary,
                  fontSize: 19,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.t('newWalletSubtitle'),
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final color = Color(_colorValue);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final sheetBg = palette.isDark ? palette.surface : Colors.white;
    final radius = widget.asDialog
        ? BorderRadius.circular(AppRadius.large)
        : const BorderRadius.vertical(top: Radius.circular(AppRadius.large));

    return Material(
      color: sheetBg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.asDialog ? 0 : bottomInset),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.sm,
              AppSpacing.screen,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.asDialog)
                  const SizedBox(height: AppSpacing.sm)
                else
                  const Center(child: InoSheetGrip()),
                const SizedBox(height: AppSpacing.md),
                // Live preview of the wallet card.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    gradient: palette.cardGradient,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: palette.border),
                    boxShadow: AppShadows.card,
                  ),
                  child: _previewRow(l10n, color, palette),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.t('walletName'),
                  style: AppText.subtitle
                      .copyWith(color: palette.textPrimary, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _save(),
                  decoration:
                      _decoration(context, l10n.t('walletNameHint'), color),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: AppColors.critical,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _error!,
                        style:
                            AppText.label.copyWith(color: AppColors.critical),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.t('icon'),
                  style: AppText.subtitle
                      .copyWith(color: palette.textPrimary, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final option in kWalletIcons)
                      _IconSwatch(
                        icon: option.icon,
                        selected: option.key == _iconKey,
                        color: color,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _iconKey = option.key);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.t('accent'),
                  style: AppText.subtitle
                      .copyWith(color: palette.textPrimary, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final value in kWalletAccentValues)
                      _ColorSwatch(
                        value: value,
                        selected: value == _colorValue,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _colorValue = value);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                PressableScale(
                  child: Container(
                    height: AppSizes.button,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: AppShadows.glow(AppColors.primaryGreen),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _saving ? null : _save,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: Center(
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      l10n.t('createWallet'),
                                      style: AppText.subtitle.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(BuildContext context, String hint, Color accent) {
    final palette = AppPalette.of(context);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body.copyWith(color: palette.textFaint),
      filled: true,
      fillColor: palette.isDark
          ? palette.surfaceVariant
          : AppColors.tealFoam,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: border(palette.border),
      enabledBorder: border(palette.border),
      focusedBorder: border(accent, 1.6),
    );
  }
}

class _IconSwatch extends StatelessWidget {
  const _IconSwatch({
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.22)
                : (palette.isDark
                    ? palette.surfaceVariant
                    : AppColors.tealFoam),
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Icon(
            icon,
            size: 23,
            color: selected ? color : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = Color(value);
    return PressableScale(
      pressedScale: 0.88,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? palette.textPrimary : Colors.transparent,
              width: 2.4,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }
}
