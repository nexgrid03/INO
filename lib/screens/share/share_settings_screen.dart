import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/document_share.dart';
import '../../models/share_settings.dart';
import '../../models/wallet_detail_models.dart';
import '../../repositories/share_repository.dart';
import '../../repositories/view_once_repository.dart';
import '../../services/document_file_service.dart';
import '../../services/document_processor.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_origin.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import 'qr_share_screen.dart';
import 'view_once_share_screen.dart';

/// How the selected documents are handed over.
enum ShareMode {
  /// The existing behaviour, unchanged: a link/QR the recipient can open as
  /// often as they like until it expires or is revoked.
  normal,

  /// A one-time link: the recipient can open the document exactly once, after
  /// which it is permanently dead. Single document only.
  viewOnce,
}

/// Share options - shown BEFORE a share is generated. The user picks a copy
/// style (Original / Black & White / Grayscale / Compressed PDF) and a link
/// expiry; a processed temporary copy is produced and shared (via a QR code or
/// directly), while the original stored file is never modified. PDFs can't be
/// pixel-processed, so the copy-style options are disabled for them.
///
/// A second mode, **View Once**, mints a one-time link instead. It reuses the
/// document already in storage (nothing is copied) and leaves every normal-share
/// path below untouched.
class ShareSettingsScreen extends StatefulWidget {
  const ShareSettingsScreen({super.key, required this.documents});

  final List<DocumentRecord> documents;

  @override
  State<ShareSettingsScreen> createState() => _ShareSettingsScreenState();
}

class _ShareSettingsScreenState extends State<ShareSettingsScreen> {
  ShareColorMode _color = ShareColorMode.original;
  ShareDuration _duration = ShareDuration.twentyFourHours;
  ShareMode _mode = ShareMode.normal;
  bool _busy = false;

  /// A one-time link grants a single view of a SINGLE document (that is what
  /// "viewed" can mean unambiguously), so the option is only offered when
  /// exactly one document is selected.
  bool get _canViewOnce => widget.documents.length == 1;

  bool get _isViewOnce => _mode == ShareMode.viewOnce && _canViewOnce;

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
    final l10n = AppLocalizations.of(context);
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
      _toast(l10n.t('couldNotGenerateShareCopy'), error: true);
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
  ///     copy, uploads it as a hidden document, and shares THAT - so the QR
  ///     opens the selected copy style in the existing viewer.
  Future<void> _generateQr() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
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
      _toast(l10n.t('couldNotCreateQr'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Mints a ONE-TIME link for the single selected document.
  ///
  /// Reuses the document already in Storage - no copy, no re-upload, and the
  /// original is never touched. The token is generated by Postgres inside the
  /// `create_view_once_share` RPC, which also verifies ownership, so the client
  /// can neither forge a token nor share a document it doesn't own.
  Future<void> _generateViewOnce() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final doc = widget.documents.first;
    setState(() => _busy = true);
    try {
      final share = await ViewOnceRepository.instance.create(
        documentId: doc.id,
        duration: _duration,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              ViewOnceShareScreen(share: share, documentName: doc.name),
        ),
      );
      return; // the screen is being replaced - don't touch state below
    } on ShareBackendNotConfiguredException {
      if (mounted) _showBackendNotConfigured();
    } on ShareException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(l10n.t('viewOnceCouldNotCreate'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showBackendNotConfigured() {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
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
              child: Text(l10n.t('sharingNotSetUp'),
                  style: AppText.title
                      .copyWith(color: palette.textPrimary, fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          l10n.t('sharingNotSetUpBody'),
          style: AppText.body.copyWith(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('ok'),
                style:  TextStyle(
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
    final l10n = AppLocalizations.of(context);
    final docs = widget.documents;
    final primary = docs.first;
    final meta = [
      if (docs.length > 1) '${docs.length} files',
      'Uploaded ${inoFormatDate(primary.uploadedAt)}',
    ].join(' · ');

    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        sky: true,
        child: SafeArea(
          top: !divineGlassEnabled(context),
          child: Column(
            children: [
              DivineGlassAppBar(
                title: l10n.t('secureShare'),
                onBack: () => Navigator.of(context).pop(),
                centerTitle: false,
                includeStatusBar: true,
              ),
              Expanded(
                child: ListView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen, 4, AppSpacing.screen, AppSpacing.lg),
                  children: [
                    // File summary card
                    _FileCard(
                      name: docs.length == 1
                          ? primary.name
                          : '${primary.name} (+${docs.length - 1})',
                      meta: meta,
                      icon: primary.icon,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    _sectionLabel(l10n.t('accessType'), palette),
                    const SizedBox(height: AppSpacing.sm),
                    _AccessTypeCards(
                      selected: _mode,
                      viewOnceEnabled: _canViewOnce,
                      onSelected: _selectMode,
                    ),
                    if (!_canViewOnce) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.t('viewOnceSingleDocOnly'),
                        style:
                            AppText.caption.copyWith(color: palette.textFaint),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),

                    if (_isViewOnce) ...[
                      _ViewOnceWarning(text: l10n.t('viewOnceSenderWarning')),
                      const SizedBox(height: AppSpacing.lg),
                    ] else ...[
                      if (!_allImages) ...[
                        _InfoBanner(
                          icon: Icons.picture_as_pdf_rounded,
                          text: l10n.t('copyStylesPdfNote'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _sectionLabel(l10n.t('formatQuality'), palette),
                      const SizedBox(height: AppSpacing.sm),
                      _FormatQualityRow(
                        selected: _color,
                        enabled: _allImages,
                        onSelected: (c) => setState(() => _color = c),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    _sectionLabel(l10n.t('linkExpiration'), palette),
                    const SizedBox(height: AppSpacing.sm),
                    _ExpiryPill(
                      selected: _duration,
                      options: _isViewOnce
                          ? _ExpiryPill.viewOnceOptions
                          : _ExpiryPill.normalOptions,
                      onSelected: (d) => setState(() => _duration = d),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.t(
                          _isViewOnce ? 'viewOnceExpiryHint' : 'linkExpiryHint'),
                      style:
                          AppText.caption.copyWith(color: palette.textFaint),
                    ),
                  ],
                ),
              ),
              _ActionBar(
                busy: _busy,
                viewOnce: _isViewOnce,
                onGenerate:
                    _isViewOnce ? _generateViewOnce : _generateAndShare,
                onQr: _isViewOnce || _busy ? null : _generateQr,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectMode(ShareMode mode) {
    final options = mode == ShareMode.viewOnce
        ? _ExpiryPill.viewOnceOptions
        : _ExpiryPill.normalOptions;
    setState(() {
      _mode = mode;
      if (!options.contains(_duration)) {
        _duration = ShareDuration.twentyFourHours;
      }
    });
  }

  Widget _sectionLabel(String text, AppPalette palette) => Text(
        text.toUpperCase(),
        style: AppText.label.copyWith(
          color: palette.textFaint,
          letterSpacing: 1.0,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      );
}

// ---------------------------------------------------------------------------

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.name,
    required this.meta,
    required this.icon,
  });

  final String name;
  final String meta;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.tealMist,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primaryGreen, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: palette.textFaint),
                ),
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

class _AccessTypeCards extends StatelessWidget {
  const _AccessTypeCards({
    required this.selected,
    required this.viewOnceEnabled,
    required this.onSelected,
  });

  final ShareMode selected;
  final bool viewOnceEnabled;
  final ValueChanged<ShareMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _AccessCard(
          icon: Icons.link_rounded,
          title: l10n.t('standardShare'),
          subtitle: l10n.t('standardShareHint'),
          active: selected == ShareMode.normal || !viewOnceEnabled,
          enabled: true,
          onTap: () => onSelected(ShareMode.normal),
        ),
        const SizedBox(height: AppSpacing.sm),
        _AccessCard(
          icon: Icons.visibility_rounded,
          title: l10n.t('shareViewOnce'),
          subtitle: l10n.t('viewOnceShareHint'),
          active: selected == ShareMode.viewOnce && viewOnceEnabled,
          enabled: viewOnceEnabled,
          onTap: () => onSelected(ShareMode.viewOnce),
        ),
      ],
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: PressableScale(
        child: GestureDetector(
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap();
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: active ? AppColors.tealMist : palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: active ? AppColors.primaryGreen : palette.border,
                width: active ? 1.6 : 1,
              ),
              boxShadow: active ? null : AppShadows.card,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primaryGreen.withValues(alpha: 0.14)
                        : palette.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon,
                      color: active
                          ? AppColors.primaryGreen
                          : palette.textSecondary,
                      size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppText.subtitle.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppText.caption
                            .copyWith(color: palette.textFaint, height: 1.35),
                      ),
                    ],
                  ),
                ),
                Icon(
                  active
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: active
                      ? AppColors.primaryGreen
                      : palette.textFaint,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatQualityRow extends StatelessWidget {
  const _FormatQualityRow({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final ShareColorMode selected;
  final bool enabled;
  final ValueChanged<ShareColorMode> onSelected;

  bool get _compressed =>
      selected == ShareColorMode.compressedPdf ||
      selected == ShareColorMode.blackWhite ||
      selected == ShareColorMode.grayscale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Row(
        children: [
          Expanded(
            child: _FormatTile(
              icon: Icons.high_quality_rounded,
              label: l10n.t('formatOriginal'),
              active: !_compressed,
              onTap: enabled
                  ? () => onSelected(ShareColorMode.original)
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _FormatTile(
              icon: Icons.compress_rounded,
              label: l10n.t('formatCompressed'),
              active: _compressed,
              onTap: enabled
                  ? () => onSelected(ShareColorMode.compressedPdf)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: active ? AppColors.tealMist : palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: active ? AppColors.primaryGreen : palette.border,
              width: active ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 22,
                  color: active
                      ? AppColors.primaryGreen
                      : palette.textSecondary),
              const SizedBox(height: 8),
              Text(
                label,
                style: AppText.subtitle.copyWith(
                  color: active
                      ? AppColors.primaryGreen
                      : palette.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewOnceWarning extends StatelessWidget {
  const _ViewOnceWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 20),
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

class _ExpiryPill extends StatelessWidget {
  const _ExpiryPill({
    required this.selected,
    required this.onSelected,
    this.options = normalOptions,
  });

  final ShareDuration selected;
  final ValueChanged<ShareDuration> onSelected;
  final List<ShareDuration> options;

  static const List<ShareDuration> normalOptions = [
    ShareDuration.oneHour,
    ShareDuration.twentyFourHours,
    ShareDuration.sevenDays,
  ];

  static const List<ShareDuration> viewOnceOptions = [
    ShareDuration.tenMinutes,
    ShareDuration.oneHour,
    ShareDuration.twentyFourHours,
    ShareDuration.sevenDays,
  ];

  String _shortLabel(ShareDuration d, AppLocalizations l10n) {
    switch (d) {
      case ShareDuration.tenMinutes:
        return l10n.t('dur10Minutes');
      case ShareDuration.oneHour:
        return l10n.t('dur1Hour');
      case ShareDuration.twentyFourHours:
        return l10n.t('dur1Day');
      case ShareDuration.sevenDays:
        return l10n.t('dur7Days');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final d in options)
            Expanded(
              child: PressableScale(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelected(d);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d == selected
                          ? AppColors.primaryGreen
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      _shortLabel(d, l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: d == selected
                            ? Colors.white
                            : palette.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
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
    required this.busy,
    required this.onGenerate,
    this.onQr,
    this.viewOnce = false,
  });

  final bool busy;
  final VoidCallback onGenerate;
  final VoidCallback? onQr;
  final bool viewOnce;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PressableScale(
                child: GestureDetector(
                  onTap: busy ? null : onGenerate,
                  child: Container(
                    height: AppSizes.button,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.primaryGreen.withValues(alpha: 0.32),
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  viewOnce
                                      ? Icons.visibility_rounded
                                      : Icons.link_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.t(viewOnce
                                      ? 'createViewOnceLink'
                                      : 'generateSecureLink'),
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
              if (onQr != null) ...[
                const SizedBox(height: AppSpacing.sm),
                PressableScale(
                  child: GestureDetector(
                    onTap: onQr,
                    child: Text(
                      l10n.t('createQrCode'),
                      style: AppText.subtitle.copyWith(
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
