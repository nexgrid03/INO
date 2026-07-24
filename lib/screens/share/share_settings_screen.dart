import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/document_share.dart';
import '../../models/share_settings.dart';
import '../../models/wallet_detail_models.dart';
import '../../repositories/share_repository.dart';
import '../../services/document_file_service.dart';
import '../../services/document_processor.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_origin.dart';
import '../../widgets/pressable_scale.dart';
import 'qr_share_screen.dart';

/// Share options — shown BEFORE a share is generated. The user picks a copy
/// style (Original / Black & White / Grayscale / Compressed PDF) and a link
/// expiry; a processed temporary copy is produced and shared (via a QR code or
/// directly), while the original stored file is never modified. PDFs can't be
/// pixel-processed, so the copy-style options are disabled for them.
class ShareSettingsScreen extends StatefulWidget {
  const ShareSettingsScreen({super.key, required this.documents});

  final List<DocumentRecord> documents;

  @override
  State<ShareSettingsScreen> createState() => _ShareSettingsScreenState();
}

class _ShareSettingsScreenState extends State<ShareSettingsScreen> {
  ShareColorMode _color = ShareColorMode.original;
  ShareDuration _duration = ShareDuration.twentyFourHours;
  bool _busy = false;

  /// Copy-style processing is only available when every selected document is an
  /// image (PDFs can't be transformed with the current toolchain).
  bool get _allImages => widget.documents.every((d) =>
      d.filePath != null && !d.filePath!.toLowerCase().endsWith('.pdf'));

  ShareSettings _settings() => ShareSettings(
        colorMode: _allImages ? _color : ShareColorMode.original,
        duration: _duration,
      );

  /// Produces a processed copy (in the chosen copy style) for every selected
  /// document.
  Future<List<ProcessedShareFile>> _processAll(ShareSettings settings) async {
    final results = <ProcessedShareFile>[];
    for (final doc in widget.documents) {
      final local =
          await DocumentFileService.instance.ensureLocal(doc.filePath!);
      final isPdf = doc.filePath!.toLowerCase().endsWith('.pdf');
      final r = await DocumentProcessor.instance.process(
        sourcePath: local.path,
        sourceIsPdf: isPdf,
        settings: settings,
      );
      results.add(r);
    }
    return results;
  }

  Future<void> _generateAndShare() async {
    if (_busy) return;
    final settings = _settings();
    setState(() => _busy = true);
    try {
      final results = await _processAll(settings);
      if (!mounted) return;
      final files = [
        for (var i = 0; i < results.length; i++)
          XFile(results[i].path,
              name: _shareName(widget.documents[i], results[i].isPdf)),
      ];
      final origin = shareOrigin(context);
      await Share.shareXFiles(
        files,
        subject: 'Shared securely from INO',
        sharePositionOrigin: origin,
      );
      if (mounted) Navigator.of(context).maybePop();
    } on DocumentProcessException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Could not generate the share copy. Please try again.',
          error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Generates the QR share through the EXISTING, already-deployed sharing
  /// backend (the `create_document_share` RPC + `share` Edge Function + Vercel
  /// viewer). Two paths, both landing on the same viewer with the EXACT copy
  /// style the user selected:
  ///
  ///   • Original Color (no pixel change) → shares the real documents directly,
  ///     exactly like the pre-existing QR flow.
  ///   • Black & White / Grayscale / Compressed PDF → produces the processed
  ///     copy, uploads it as a hidden document, and shares THAT — so the QR
  ///     opens the selected copy style in the existing viewer.
  Future<void> _generateQr() async {
    if (_busy) return;
    final settings = _settings();
    setState(() => _busy = true);
    try {
      final DocumentShare share;
      if (!settings.requiresImageProcessing) {
        // Original Color → share the real documents via the deployed backend.
        share = await ShareRepository.instance.createShare(
          documentIds: widget.documents.map((d) => d.id).toList(),
          duration: settings.duration,
        );
      } else {
        // Processed copy → transform locally, then share the copy via the SAME
        // deployed backend. The original stored file is never touched.
        final results = await _processAll(settings);
        final items = <ProcessedShareItem>[];
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          final bytes = await File(r.path).readAsBytes();
          items.add(ProcessedShareItem(
            bytes: bytes,
            // Clean display name for the viewer card (the Edge Function adds the
            // right extension on download).
            name: widget.documents[i].name,
            mime: r.isPdf ? 'application/pdf' : 'image/jpeg',
            ext: r.isPdf ? 'pdf' : 'jpg',
          ));
        }
        share = await ShareRepository.instance.createProcessedDocumentShare(
          items: items,
          duration: settings.duration,
        );
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              QrShareScreen(share: share, documents: widget.documents),
        ),
      );
    } on ShareBackendNotConfiguredException {
      if (mounted) _showBackendNotConfigured();
    } on ShareException catch (e) {
      _toast(e.message, error: true);
    } on DocumentProcessException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Could not create the QR code. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showBackendNotConfigured() {
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
              child: Text('Sharing Not Set Up',
                  style: AppText.title
                      .copyWith(color: palette.textPrimary, fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          'The document sharing service isn’t deployed on the server yet. Deploy '
          'the Supabase migration and the “share” Edge Function '
          '(see supabase/README_document_sharing.md), then try again. You can '
          'still use “Generate & Share” to send the copy directly now.',
          style: AppText.body.copyWith(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK',
                style: TextStyle(
                    color: AppColors.primaryGreen, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _shareName(DocumentRecord doc, bool isPdf) {
    final base = doc.name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    final safe = base.isEmpty ? 'document' : base;
    return '$safe (shared).${isPdf ? 'pdf' : 'jpg'}';
  }

  void _toast(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
    ));
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
            _Header(count: docs.length, onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.lg),
                children: [
                  if (!_allImages)
                    _InfoBanner(
                      icon: Icons.picture_as_pdf_rounded,
                      text:
                          'Copy styles apply to image documents. PDFs are shared '
                          'as-is; the link expiry below still applies.',
                    ),
                  if (!_allImages) const SizedBox(height: AppSpacing.md),

                  // Copy style — the ONLY thing the user picks besides expiry.
                  _label('Copy Style', palette),
                  const SizedBox(height: AppSpacing.sm),
                  _ColorGrid(
                    selected: _color,
                    enabled: _allImages,
                    onSelected: (c) => setState(() => _color = c),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Link expiry — enforced server-side by the share backend.
                  _label('Link Expiry', palette),
                  const SizedBox(height: AppSpacing.sm),
                  _ExpiryRow(
                    selected: _duration,
                    onSelected: (d) => setState(() => _duration = d),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Recipients scan the QR to view the shared copy in your '
                    'secure INO viewer. The link stops working when it expires, '
                    'and you can revoke it anytime.',
                    style: AppText.caption.copyWith(color: palette.textFaint),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _QrLinkButton(onTap: _busy ? null : _generateQr),
                ],
              ),
            ),
            _ActionBar(
              busy: _busy,
              onCancel: () => Navigator.of(context).pop(),
              onGenerate: _generateAndShare,
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, AppPalette palette) => Text(
        text.toUpperCase(),
        style:
            AppText.label.copyWith(color: palette.textFaint, letterSpacing: 1.0),
      );
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onBack});

  final int count;
  final VoidCallback onBack;

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
                onTap: onBack,
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
                Text('Share Settings',
                    style: AppText.headline
                        .copyWith(color: palette.textPrimary, fontSize: 21)),
                const SizedBox(height: 2),
                Text('$count document${count == 1 ? '' : 's'} · original stays safe',
                    style:
                        AppText.caption.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
          Icon(icon, color: AppColors.lightBlue, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: AppText.caption
                    .copyWith(color: palette.textSecondary, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _ColorGrid extends StatelessWidget {
  const _ColorGrid(
      {required this.selected, required this.enabled, required this.onSelected});

  final ShareColorMode selected;
  final bool enabled;
  final ValueChanged<ShareColorMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.8,
      children: [
        for (final c in ShareColorMode.values)
          _ChoiceChip(
            icon: c.icon,
            label: c.label,
            active: c == selected,
            enabled: enabled,
            onTap: () => onSelected(c),
          ),
      ],
    );
  }
}

class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({required this.selected, required this.onSelected});

  final ShareDuration selected;
  final ValueChanged<ShareDuration> onSelected;

  static const _options = [
    ShareDuration.twentyFourHours,
    ShareDuration.sevenDays,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _options.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _ChoiceChip(
              icon: Icons.schedule_rounded,
              label: 'Expire after ${_options[i].label}',
              active: _options[i] == selected,
              enabled: true,
              onTap: () => onSelected(_options[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final on = active && enabled;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: on ? AppColors.brandGradient : null,
        color: on ? null : palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: on ? Colors.transparent : palette.border),
        boxShadow: on
            ? [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18, color: on ? Colors.white : palette.textSecondary),
            const SizedBox(width: 8),
            Flexible(
              // Shrink the label to fit one line instead of ellipsizing it —
              // long copy-style / expiry labels must never show trailing dots.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: AppText.subtitle.copyWith(
                    color: on ? Colors.white : palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return PressableScale(
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        child: content,
      ),
    );
  }
}

class _QrLinkButton extends StatelessWidget {
  const _QrLinkButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: AppSizes.button,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
                color: AppColors.primaryGreen.withValues(alpha: 0.4)),
          ),
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_2_rounded,
                    color: AppColors.darkGreen, size: 20),
                SizedBox(width: 8),
                Text('Create QR Code',
                    style: TextStyle(
                        color: AppColors.darkGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.busy,
    required this.onCancel,
    required this.onGenerate,
  });

  final bool busy;
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
                    onTap: busy ? null : onCancel,
                    child: SizedBox(
                      height: AppSizes.button,
                      width: 96,
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
                  child: GestureDetector(
                    onTap: busy ? null : onGenerate,
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
                      child: Center(
                        child: busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.ios_share_rounded,
                                      color: Colors.white, size: 19),
                                  const SizedBox(width: 8),
                                  Text('Generate & Share',
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
            ],
          ),
        ),
      ),
    );
  }
}
