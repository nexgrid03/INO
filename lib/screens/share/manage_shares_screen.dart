import 'package:flutter/material.dart';

import '../../models/document_share.dart';
import '../../repositories/share_repository.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/pressable_scale.dart';
import 'qr_share_screen.dart';

/// Manage Shares — every QR/link the user has created, so they can review
/// analytics (views / downloads) and revoke access at any time, long after the
/// original QR screen was closed.
///
/// Layout: custom header → 3-up analytics summary → "Active links" section →
/// "History" section. Active cards carry the brand-gradient QR chip and an
/// inline revoke action (with confirmation); past cards are dimmed so live
/// links pop first.
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
      body: InoBackground(
        child: SafeArea(
          child: Column(
            children: [
              _Header(onBack: () => Navigator.of(context).maybePop()),
              Expanded(
                child: FutureBuilder<List<DocumentShare>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: AppColors.primaryGreen,
                        ),
                      );
                      
                    }
                    final shares = snapshot.data ?? const <DocumentShare>[];
                    if (shares.isEmpty) return _EmptyState(palette: palette);
                    return RefreshIndicator(
                      color: AppColors.primaryGreen,
                      onRefresh: () async => _reload(),
                      child: _SharesList(
                        shares: shares,
                        onOpen: _open,
                        onRevoke: _revoke,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke this link?'),
        content: const Text(
          'Anyone holding this link or QR code will immediately lose access. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.critical,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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

// ---------------------------------------------------------------------------
// Header

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.sm,
        AppSpacing.screen,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          _CircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shared Links',
                  style: AppText.headline.copyWith(
                    color: palette.textPrimary,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Review activity & revoke access anytime',
                  style: AppText.caption.copyWith(
                    color: palette.textSecondary,
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

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: Material(
        color: palette.surface,
        shape: CircleBorder(side: BorderSide(color: palette.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: AppSizes.iconContainerSm,
            height: AppSizes.iconContainerSm,
            child: Icon(icon, size: 20, color: palette.textPrimary),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List body

class _SharesList extends StatelessWidget {
  const _SharesList({
    required this.shares,
    required this.onOpen,
    required this.onRevoke,
  });

  final List<DocumentShare> shares;
  final void Function(DocumentShare) onOpen;
  final void Function(DocumentShare) onRevoke;

  @override
  Widget build(BuildContext context) {
    final active = [
      for (final s in shares)
        if (s.effectiveStatus == ShareStatus.active) s,
    ];
    final history = [
      for (final s in shares)
        if (s.effectiveStatus != ShareStatus.active) s,
    ];
    final totalViews = shares.fold<int>(0, (sum, s) => sum + s.viewsCount);
    final totalDownloads = shares.fold<int>(
      0,
      (sum, s) => sum + s.downloadsCount,
    );

    final sections = <Widget>[
      _StatsRow(
        activeCount: active.length,
        views: totalViews,
        downloads: totalDownloads,
      ),
      if (active.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(label: 'ACTIVE LINKS', count: active.length),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < active.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _ShareCard(
            share: active[i],
            onOpen: () => onOpen(active[i]),
            onRevoke: () => onRevoke(active[i]),
          ),
        ],
      ],
      if (history.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(label: 'HISTORY', count: history.length, muted: true),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < history.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _ShareCard(
            share: history[i],
            onOpen: () => onOpen(history[i]),
            onRevoke: () => onRevoke(history[i]),
          ),
        ],
      ],
      const SizedBox(height: 40),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        0,
      ),
      children: [
        for (var i = 0; i < sections.length; i++)
          FadeSlideIn(
            delay: Duration(milliseconds: (i * 45).clamp(0, 320)),
            child: sections[i],
          ),
      ],
    );
  }
}

/// Overline section header — matches the "AGENDA ·" pattern used on Reminders.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.count,
    this.muted = false,
  });

  final String label;
  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = muted ? palette.textFaint : AppColors.primaryGreen;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Row(
        children: [
          Text(
            label,
            style: AppText.label.copyWith(
              color: color,
              fontSize: 11,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '$count',
              style: AppText.label.copyWith(color: color, fontSize: 11),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Container(height: 1, color: palette.border)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats summary

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.activeCount,
    required this.views,
    required this.downloads,
  });

  final int activeCount;
  final int views;
  final int downloads;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.qr_code_2_rounded,
            color: AppColors.primaryGreen,
            value: activeCount,
            label: 'Active',
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _StatCard(
            icon: Icons.visibility_rounded,
            color: AppColors.lightBlue,
            value: views,
            label: 'Views',
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _StatCard(
            icon: Icons.download_rounded,
            color: AppColors.warning,
            value: downloads,
            label: 'Downloads',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip - 2),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$value',
            style: AppText.headline.copyWith(
              color: palette.textPrimary,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: palette.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Share card

class _ShareCard extends StatelessWidget {
  const _ShareCard({
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
    final isActive = status == ShareStatus.active;
    final (statusColor, statusLabel) = switch (status) {
      ShareStatus.active => (AppColors.primaryGreen, 'Active'),
      ShareStatus.expired => (AppColors.warning, 'Expired'),
      ShareStatus.revoked => (AppColors.critical, 'Revoked'),
    };

    return InoCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity row: QR chip · title + timing · status pill.
          Row(
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  gradient: isActive ? AppGradients.primary : null,
                  color: isActive ? null : palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  boxShadow: isActive
                      ? AppShadows.glow(AppColors.primaryGreen, opacity: 0.25)
                      : null,
                ),
                child: Icon(
                  Icons.qr_code_2_rounded,
                  color: isActive ? Colors.white : palette.textFaint,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${share.documentCount} '
                      'Document${share.documentCount == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _timingLine(status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _StatusPill(color: statusColor, label: statusLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(height: 1, color: palette.border),
          const SizedBox(height: AppSpacing.sm),
          // Analytics footer: views · downloads · action.
          Row(
            children: [
              _MetaStat(
                icon: Icons.visibility_outlined,
                label:
                    '${share.viewsCount} view${share.viewsCount == 1 ? '' : 's'}',
              ),
              const SizedBox(width: AppSpacing.md),
              _MetaStat(
                icon: Icons.download_outlined,
                label:
                    '${share.downloadsCount} download'
                    '${share.downloadsCount == 1 ? '' : 's'}',
              ),
              const Spacer(),
              if (isActive)
                _RevokeButton(onTap: onRevoke)
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Details',
                      style: AppText.label.copyWith(
                        color: palette.textFaint,
                        fontSize: 12,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: palette.textFaint,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _timingLine(ShareStatus status) {
    final created = 'Created ${_monthDay(share.createdAt)}';
    switch (status) {
      case ShareStatus.active:
        return '$created · ${_expiresIn(share.expiresAt)}';
      case ShareStatus.expired:
        return '$created · Expired ${_monthDay(share.expiresAt)}';
      case ShareStatus.revoked:
        return '$created · Access revoked';
    }
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _monthDay(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  static String _expiresIn(DateTime expiresAt) {
    final left = expiresAt.difference(DateTime.now());
    if (left.inDays >= 1) return 'Expires in ${left.inDays}d';
    if (left.inHours >= 1) return 'Expires in ${left.inHours}h';
    if (left.inMinutes >= 1) return 'Expires in ${left.inMinutes}m';
    return 'Expiring now';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
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

class _MetaStat extends StatelessWidget {
  const _MetaStat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: palette.textFaint),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppText.caption.copyWith(
            color: palette.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _RevokeButton extends StatelessWidget {
  const _RevokeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.92,
      child: Material(
        color: AppColors.critical.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.link_off_rounded,
                  size: 15,
                  color: AppColors.critical,
                ),
                const SizedBox(width: 5),
                Text(
                  'Revoke',
                  style: AppText.label.copyWith(
                    color: AppColors.critical,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: FadeSlideIn(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Layered brand mark: soft halo behind a gradient QR chip.
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const DecorBlob(size: 120, opacity: 0.30),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: AppGradients.primary,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        boxShadow: AppShadows.glow(
                          AppColors.primaryGreen,
                          opacity: 0.30,
                        ),
                      ),
                      child: const Icon(
                        Icons.qr_code_2_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'No shared links yet',
                style: AppText.headline.copyWith(
                  color: palette.textPrimary,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Select documents in a wallet and tap “Share via QR” to '
                'create a secure, expiring link.',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(
                  color: palette.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
