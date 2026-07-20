import 'package:flutter/material.dart';

import '../../models/document_share.dart';
import '../../repositories/share_repository.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/ino_card.dart';
import 'qr_share_screen.dart';

/// Manage Shares — every QR/link the user has created, so they can review
/// analytics (views / downloads) and revoke access at any time, long after the
/// original QR screen was closed.
class ManageSharesScreen extends StatefulWidget {
  const ManageSharesScreen({super.key});

  @override
  State<ManageSharesScreen> createState() => _ManageSharesScreenState();
}

class _ManageSharesScreenState extends State<ManageSharesScreen> {
  late Future<List<DocumentShare>> _future;

  @override
  void initState() {
    super.initState();
    _future = ShareRepository.instance.listMyShares();
    ShareRepository.revision.addListener(_reload);
  }

  @override
  void dispose() {
    ShareRepository.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = ShareRepository.instance.listMyShares());
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Text(
          'Shared Links',
          style: AppText.title.copyWith(color: palette.textPrimary),
        ),
      ),
      body: FutureBuilder<List<DocumentShare>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            );
          }
          final shares = snapshot.data ?? const <DocumentShare>[];
          if (shares.isEmpty) {
            return _EmptyState(palette: palette);
          }
          return RefreshIndicator(
            color: AppColors.primaryGreen,
            onRefresh: () async => _reload(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: shares.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _ShareTile(
                share: shares[i],
                onOpen: () => _open(shares[i]),
                onRevoke: () => _revoke(shares[i]),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _open(DocumentShare share) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => QrShareScreen(share: share)));
    _reload();
  }

  Future<void> _revoke(DocumentShare share) async {
    try {
      await ShareRepository.instance.revoke(share.shareId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Share revoked'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primaryGreen,
        ),
      );
    } on ShareException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.critical,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not revoke — please try again'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.critical,
        ),
      );
    }
  }
}

class _ShareTile extends StatelessWidget {
  const _ShareTile({
    required this.share,
    required this.onOpen,
    required this.onRevoke,
  });

  final DocumentShare share;
  final VoidCallback onOpen;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final status = share.effectiveStatus;
    final (statusColor, statusLabel) = switch (status) {
      ShareStatus.active => (AppColors.primaryGreen, 'Active'),
      ShareStatus.expired => (AppColors.warning, 'Expired'),
      ShareStatus.revoked => (AppColors.critical, 'Revoked'),
    };
    return InoCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: AppSizes.iconContainerSm,
            height: AppSizes.iconContainerSm,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: const Icon(
              Icons.qr_code_2_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${share.documentCount} document'
                      '${share.documentCount == 1 ? '' : 's'}',
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _StatusDot(color: statusColor, label: statusLabel),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${share.viewsCount} view${share.viewsCount == 1 ? '' : 's'} · '
                  '${share.downloadsCount} download'
                  '${share.downloadsCount == 1 ? '' : 's'}',
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          if (status == ShareStatus.active)
            IconButton(
              onPressed: onRevoke,
              tooltip: 'Revoke',
              icon: const Icon(
                Icons.link_off_rounded,
                color: AppColors.critical,
                size: 20,
              ),
            )
          else
            Icon(Icons.chevron_right_rounded, color: palette.textFaint),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.label.copyWith(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                size: 42,
                color: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No shared links yet',
              style: AppText.title.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Select documents in a wallet and tap “Share via QR” to create '
              'a secure, expiring link.',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
