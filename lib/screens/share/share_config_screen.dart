import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/document_share.dart';
import '../../models/wallet_detail_models.dart';
import '../../repositories/share_repository.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import 'qr_share_screen.dart';

/// Share Configuration screen — choose how long a QR share stays valid, then
/// generate it.
///
/// Reuses the existing document set (no new storage) and the app's green + light
/// blue design language. On "Generate QR" it creates one `document_shares` row
/// (via the RPC, which verifies ownership server-side) and hands off to
/// [QrShareScreen]. It never fabricates a share: a failure surfaces an error and
/// leaves the user on this screen.
class ShareConfigScreen extends StatefulWidget {
  const ShareConfigScreen({super.key, required this.documents});

  /// The documents the user selected to share (must have real [DocumentRecord.id]s).
  final List<DocumentRecord> documents;

  @override
  State<ShareConfigScreen> createState() => _ShareConfigScreenState();
}

class _ShareConfigScreenState extends State<ShareConfigScreen> {
  ShareDuration _duration = ShareDuration.twentyFourHours;
  bool _generating = false;

  Future<void> _generate() async {
    if (_generating) return;
    final ids = widget.documents.map((d) => d.id).toList();
    developer.log(
      'Share requested → ids=$ids duration=${_duration.label} '
      '(${_duration.seconds}s)',
      name: 'share',
    );
    if (!mounted) return;
    setState(() => _generating = true);
    try {
      final share = await ShareRepository.instance.createShare(
        documentIds: ids,
        duration: _duration,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              QrShareScreen(share: share, documents: widget.documents),
        ),
      );
      return; // screen is being replaced — don't touch state below.
    } on ShareBackendNotConfiguredException {
      if (!mounted) return;
      _showBackendNotConfigured();
    } on ShareException catch (e) {
      // Shows the exact Supabase/validation message.
      _fail(e.message);
    } catch (e) {
      developer.log('Share generate unexpected error: $e', name: 'share');
      _fail('Could not generate the share. Please try again.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.critical,
      ),
    );
  }

  /// Clear, actionable state when the Supabase backend for sharing hasn't been
  /// deployed yet (the `create_document_share` RPC is missing).
  void _showBackendNotConfigured() {
    if (!mounted) return;
    final palette = AppPalette.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large)),
        title: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.warning),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text('QR Sharing Backend Not Configured',
                  style: AppText.title
                      .copyWith(color: palette.textPrimary, fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          'The sharing service isn’t set up on the server yet. Deploy the '
          'Supabase migration and the “share” Edge Function '
          '(see supabase/README_document_sharing.md), then try again.',
          style: AppText.body.copyWith(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK',
                style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final docs = widget.documents;
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(count: docs.length, onClose: () => Navigator.of(context).pop()),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.lg),
                children: [
                  _sectionLabel('Selected Documents', palette),
                  const SizedBox(height: AppSpacing.sm),
                  InoCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    child: Column(
                      children: [
                        for (var i = 0; i < docs.length; i++) ...[
                          if (i > 0)
                            Divider(height: 1, color: palette.border),
                          _DocRow(record: docs[i]),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _sectionLabel('Expiry Duration', palette),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'The QR code stops working automatically when it expires.',
                    style: AppText.caption.copyWith(color: palette.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DurationGrid(
                    selected: _duration,
                    onSelected: (d) => setState(() => _duration = d),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SecurityNote(palette: palette),
                ],
              ),
            ),
            _ActionBar(
              generating: _generating,
              onCancel: () => Navigator.of(context).pop(),
              onGenerate: _generate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, AppPalette palette) => Text(
        text.toUpperCase(),
        style: AppText.label.copyWith(color: palette.textFaint, letterSpacing: 1.0),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onClose});

  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
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
                onTap: onClose,
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 21, color: palette.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Share via QR',
                    style: AppText.headline
                        .copyWith(color: palette.textPrimary, fontSize: 21)),
                const SizedBox(height: 2),
                Text(
                  '$count document${count == 1 ? '' : 's'} selected',
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

class _DocRow extends StatelessWidget {
  const _DocRow({required this.record});

  final DocumentRecord record;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(record.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text(record.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.check_circle_rounded,
              color: AppColors.primaryGreen, size: 20),
        ],
      ),
    );
  }
}

class _DurationGrid extends StatelessWidget {
  const _DurationGrid({required this.selected, required this.onSelected});

  final ShareDuration selected;
  final ValueChanged<ShareDuration> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.6,
      children: [
        for (final d in ShareDuration.values)
          _DurationChip(
            duration: d,
            active: d == selected,
            onTap: () => onSelected(d),
          ),
      ],
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.duration,
    required this.active,
    required this.onTap,
  });

  final ShareDuration duration;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: PressableScale(
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          gradient: active ? AppColors.brandGradient : null,
          color: active ? null : palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(
            color: active ? Colors.transparent : palette.border,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 18,
              color: active ? Colors.white : palette.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              duration.label,
              style: AppText.subtitle.copyWith(
                color: active ? Colors.white : palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.lightBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.lightBlue.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_rounded,
              color: AppColors.lightBlue, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Anyone with the link can view only these documents until it '
              'expires. Your wallet, account and other documents stay private. '
              'You can revoke access at any time.',
              style: AppText.caption.copyWith(
                color: palette.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.generating,
    required this.onCancel,
    required this.onGenerate,
  });

  final bool generating;
  final VoidCallback onCancel;
  final VoidCallback onGenerate;

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
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
              AppSpacing.screen, AppSpacing.sm),
          child: Row(
            children: [
              PressableScale(
                child: Material(
                  color: palette.surface,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    side: BorderSide(color: palette.border),
                  ),
                  child: InkWell(
                    onTap: generating ? null : onCancel,
                    child: SizedBox(
                      height: AppSizes.button,
                      width: 104,
                      child: Center(
                        child: Text('Cancel',
                            style: AppText.subtitle
                                .copyWith(color: palette.textSecondary)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
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
                        onTap: generating ? null : onGenerate,
                        borderRadius: BorderRadius.circular(AppRadius.button),
                        child: Center(
                          child: generating
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.qr_code_2_rounded,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text('Generate QR',
                                        style: AppText.subtitle.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
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
    );
  }
}
