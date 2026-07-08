import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/public_share.dart';
import '../../repositories/share_repository.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';

/// The recipient-facing viewer for a shared link/QR.
///
/// Fetches the share's public metadata from the `share` Edge Function (JSON,
/// anonymous — no Supabase session) and renders the shared documents with View
/// and Download actions. Files are streamed **through** the Edge Function, so
/// the storage path / signed URL are never exposed. Shows clear terminal states
/// for expired / revoked / missing links.
class SharedDocumentsScreen extends StatefulWidget {
  const SharedDocumentsScreen({super.key, required this.token});

  /// The short public share token (from the `/s/<token>` link). The Edge
  /// Function also accepts the internal share_id, so either resolves.
  final String token;

  @override
  State<SharedDocumentsScreen> createState() => _SharedDocumentsScreenState();
}

class _SharedDocumentsScreenState extends State<SharedDocumentsScreen> {
  PublicShare? _share;
  bool _loading = true;
  String? _busyDocId; // the document currently opening/downloading
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh the countdown once a second; cancelled in dispose().
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final share = await ShareRepository.instance.fetchPublicShare(widget.token);
    if (!mounted) return;
    setState(() {
      _share = share;
      _loading = false;
    });
  }

  /// Effective status honouring the wall clock (an active share whose expiry has
  /// just lapsed shows as expired without a refetch).
  PublicShareStatus get _status {
    final s = _share;
    if (s == null) return PublicShareStatus.error;
    if (s.status == PublicShareStatus.active &&
        s.expiresAt != null &&
        s.expiresAt!.isBefore(DateTime.now())) {
      return PublicShareStatus.expired;
    }
    return s.status;
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
      ),
    );
  }

  Future<void> _open(SharedDoc doc, {required bool download}) async {
    if (_busyDocId != null) return;
    setState(() => _busyDocId = doc.id);
    try {
      final file = await ShareRepository.instance
          .fetchSharedFile(widget.token, doc, download: download);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${file.filename}';
      await File(path).writeAsBytes(file.bytes, flush: true);
      if (!mounted) return;
      if (download) {
        await Share.shareXFiles(
          [XFile(path, mimeType: file.mimeType, name: file.filename)],
          subject: doc.name,
          text: 'Shared with you via INO',
        );
      } else {
        final result = await OpenFilex.open(path, type: file.mimeType);
        if (result.type != ResultType.done) {
          _toast('No app available to open this file.', error: true);
        }
      }
    } on ShareException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Could not ${download ? 'download' : 'open'} this document.',
          error: true);
    } finally {
      if (mounted) setState(() => _busyDocId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Brand(),
            Expanded(child: _body(palette)),
            const _Footer(),
          ],
        ),
      ),
    );
  }

  Widget _body(AppPalette palette) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }
    switch (_status) {
      case PublicShareStatus.active:
        return _activeBody(palette);
      case PublicShareStatus.expired:
        return _TerminalState(
          icon: Icons.timer_off_rounded,
          color: AppColors.warning,
          title: 'This share link has expired',
          subtitle: 'The documents are no longer available.',
        );
      case PublicShareStatus.revoked:
        return _TerminalState(
          icon: Icons.link_off_rounded,
          color: AppColors.critical,
          title: 'This share link has been revoked',
          subtitle: 'The owner has turned off access to these documents.',
        );
      case PublicShareStatus.notFound:
        return _TerminalState(
          icon: Icons.help_outline_rounded,
          color: palette.textFaint,
          title: 'Link not found',
          subtitle: 'This shared link doesn’t exist.',
        );
      case PublicShareStatus.error:
        return _TerminalState(
          icon: Icons.wifi_off_rounded,
          color: palette.textFaint,
          title: 'Couldn’t load this share',
          subtitle: 'Check your connection and try again.',
          onRetry: _load,
        );
    }
  }

  Widget _activeBody(AppPalette palette) {
    final share = _share!;
    final docs = share.documents;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, AppSpacing.xs, AppSpacing.screen, AppSpacing.lg),
      children: [
        Text('Shared Documents',
            style: AppText.headline.copyWith(color: palette.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Text(
              '${share.count} document${share.count == 1 ? '' : 's'}',
              style: AppText.subtitle.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (share.expiresAt != null) _ExpiryPill(expiresAt: share.expiresAt!),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final d in docs) ...[
          _DocCard(
            doc: d,
            busy: _busyDocId == d.id,
            disabled: _busyDocId != null && _busyDocId != d.id,
            onView: () => _open(d, download: false),
            onDownload: () => _open(d, download: true),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            alignment: Alignment.center,
            child: const Text('I',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('INO',
                  style: AppText.title.copyWith(
                      color: palette.textPrimary, fontWeight: FontWeight.w900)),
              Text('Secure document share',
                  style:
                      AppText.caption.copyWith(color: palette.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_rounded, size: 13, color: palette.textFaint),
          const SizedBox(width: 6),
          Text('Shared via INO · you can only view these documents',
              style: AppText.caption.copyWith(color: palette.textFaint)),
        ],
      ),
    );
  }
}

class _ExpiryPill extends StatelessWidget {
  const _ExpiryPill({required this.expiresAt});

  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    final d = expiresAt.difference(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded,
              size: 14, color: AppColors.primaryGreen),
          const SizedBox(width: 5),
          Text(
            _label(d),
            style: AppText.caption.copyWith(
                color: AppColors.darkGreen, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _label(Duration d) {
    if (d.isNegative) return 'Expired';
    if (d.inHours >= 24) {
      final days = d.inDays;
      return 'Expires in $days day${days == 1 ? '' : 's'}';
    }
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return 'Expires in ${h}h ${m}m';
    if (m > 0) return 'Expires in ${m}m ${s}s';
    return 'Expires in ${s}s';
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.doc,
    required this.busy,
    required this.disabled,
    required this.onView,
    required this.onDownload,
  });

  final SharedDoc doc;
  final bool busy;
  final bool disabled;
  final VoidCallback onView;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: const Icon(Icons.description_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text(doc.type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.xs),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.primaryGreen),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.visibility_rounded,
                  label: 'View',
                  filled: true,
                  onTap: (busy || disabled) ? null : onView,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActionButton(
                  icon: Icons.download_rounded,
                  label: 'Download',
                  filled: false,
                  onTap: (busy || disabled) ? null : onDownload,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon,
            size: 18, color: filled ? Colors.white : AppColors.primaryGreen),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppText.subtitle.copyWith(
            color: filled ? Colors.white : palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    return PressableScale(
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: filled
            ? Container(
                height: AppSizes.button,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    child: Center(child: content),
                  ),
                ),
              )
            : Material(
                color: palette.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  side: BorderSide(color: palette.border),
                ),
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox(
                    height: AppSizes.button,
                    child: Center(child: content),
                  ),
                ),
              ),
      ),
    );
  }
}

class _TerminalState extends StatelessWidget {
  const _TerminalState({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: color),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title,
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: palette.textSecondary)),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PressableScale(
                child: Material(
                  color: AppColors.primaryGreen,
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  child: InkWell(
                    onTap: onRetry,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
                      child: Text('Try again',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
