import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/document_share.dart';
import '../../repositories/share_repository.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/divine_glass/divine_glass.dart';
import '../../widgets/pressable_scale.dart';
import 'qr_share_screen.dart';

/// Manage Shares - every QR/link the user has created, so they can review
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
    // Block body: an arrow hands setState the assigned Future, which it rejects.
    setState(() {
      _future = ShareRepository.instance.listMyShares();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final glass = divineGlassEnabled(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        sky: glass,
        child: SafeArea(
          top: !glass,
          child: Column(
            children: [
              DivineGlassAppBar(
                title: l10n.t('sharedLinksTitle'),
                onBack: () => Navigator.of(context).maybePop(),
                centerTitle: false,
                includeStatusBar: true,
              ),
              Expanded(
                child: FutureBuilder<List<DocumentShare>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('revokeThisLinkTitle')),
        content: Text(l10n.t('revokeThisLinkBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.critical,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('revoke')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ShareRepository.instance.revoke(share.shareId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('shareRevoked')),
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
        SnackBar(
          content: Text(l10n.t('couldNotRevoke')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.critical,
        ),
      );
    }
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
    final l10n = AppLocalizations.of(context);
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
        const SizedBox(height: AppSpacing.lg + 4),
        _SectionLabel(
          label: l10n.t('activeLinksSection'),
          count: active.length,
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < active.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ShareCard(
            share: active[i],
            onOpen: () => onOpen(active[i]),
            onRevoke: () => onRevoke(active[i]),
          ),
        ],
      ],
      if (history.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg + 4),
        _SectionLabel(
          label: l10n.t('historySection'),
          count: history.length,
          muted: true,
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < history.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ShareCard(
            share: history[i],
            onOpen: () => onOpen(history[i]),
            onRevoke: () => onRevoke(history[i]),
          ),
        ],
      ],
      const SizedBox(height: 24),
    ];

    // Lazy: only visible rows get elements/render objects, so a long share
    // history costs nothing until scrolled to. No FadeSlideIn — recycled rows
    // replay the entrance every time they scroll back into view.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      // Clear gap under the frosted app bar so stats never kiss the header.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md + 4,
        AppSpacing.screen,
        AppSpacing.xl,
      ),
      itemCount: sections.length,
      itemBuilder: (context, i) => sections[i],
    );
  }
}

/// Overline section header - matches the "AGENDA ·" pattern used on Reminders.
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
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.qr_code_2_rounded,
            color: AppColors.primaryGreen,
            value: activeCount,
            label: l10n.t('active'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.visibility_rounded,
            color: AppColors.lightBlue,
            value: views,
            label: l10n.t('views'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.download_rounded,
            color: AppColors.warning,
            value: downloads,
            label: l10n.t('downloads'),
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
    final child = Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.22),
                color.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '$value',
          style: AppText.headline.copyWith(
            color: palette.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.caption.copyWith(
            color: palette.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    if (divineGlassEnabled(context)) {
      return AdaptiveGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        radius: 20,
        child: child,
      );
    }
    return InoCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: child,
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
    final l10n = AppLocalizations.of(context);
    final status = share.effectiveStatus;
    final isActive = status == ShareStatus.active;
    final (statusColor, statusLabel) = switch (status) {
      ShareStatus.active => (AppColors.primaryGreen, l10n.t('active')),
      ShareStatus.expired => (AppColors.warning, l10n.t('expired')),
      ShareStatus.revoked => (AppColors.critical, l10n.t('revoked')),
    };

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: isActive
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primaryGreen.withValues(alpha: 0.22),
                          AppColors.primaryGreen.withValues(alpha: 0.08),
                        ],
                      )
                    : null,
                color: isActive ? null : palette.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? AppColors.primaryGreen.withValues(alpha: 0.30)
                      : palette.border,
                ),
              ),
              child: Icon(
                Icons.qr_code_2_rounded,
                color: isActive ? AppColors.primaryGreen : palette.textFaint,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n
                        .t(
                          share.documentCount == 1
                              ? 'docCountOne'
                              : 'docCountMany',
                        )
                        .replaceFirst('{n}', '${share.documentCount}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(
                      color: palette.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timingLine(l10n, status),
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
        const SizedBox(height: AppSpacing.md),
        Container(height: 1, color: palette.border.withValues(alpha: 0.7)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _MetaStat(
              icon: Icons.visibility_outlined,
              label: l10n
                  .t(share.viewsCount == 1 ? 'viewCountOne' : 'viewCountMany')
                  .replaceFirst('{n}', '${share.viewsCount}'),
            ),
            const SizedBox(width: AppSpacing.md),
            _MetaStat(
              icon: Icons.download_outlined,
              label: l10n
                  .t(
                    share.downloadsCount == 1
                        ? 'downloadCountOne'
                        : 'downloadCountMany',
                  )
                  .replaceFirst('{n}', '${share.downloadsCount}'),
            ),
            const Spacer(),
            if (isActive)
              _RevokeButton(onTap: onRevoke)
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.t('details'),
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
    );

    // Same frosted glass language as wallet / home cards.
    return PressableScale(
      pressedScale: 0.985,
      child: GestureDetector(
        onTap: onOpen,
        behavior: HitTestBehavior.opaque,
        child: divineGlassEnabled(context)
            ? AdaptiveGlassCard(
                padding: const EdgeInsets.all(16),
                radius: 22,
                child: body,
              )
            : InoCard(
                padding: const EdgeInsets.all(16),
                radius: 22,
                child: body,
              ),
      ),
    );
  }

  String _timingLine(AppLocalizations l10n, ShareStatus status) {
    final created = l10n
        .t('createdOn')
        .replaceFirst('{date}', _monthDay(l10n, share.createdAt));
    switch (status) {
      case ShareStatus.active:
        return '$created · ${_expiresIn(l10n, share.expiresAt)}';
      case ShareStatus.expired:
        final on = l10n
            .t('expiredOn')
            .replaceFirst('{date}', _monthDay(l10n, share.expiresAt));
        return '$created · $on';
      case ShareStatus.revoked:
        return '$created · ${l10n.t('accessRevoked')}';
    }
  }

  static String _monthDay(AppLocalizations l10n, DateTime d) =>
      '${l10n.monthShort(d.month)} ${d.day}';

  static String _expiresIn(AppLocalizations l10n, DateTime expiresAt) {
    final left = expiresAt.difference(DateTime.now());
    String at(String key, int n) => l10n.t(key).replaceFirst('{n}', '$n');
    if (left.inDays >= 1) return at('expiresInDaysShort', left.inDays);
    if (left.inHours >= 1) return at('expiresInHoursShort', left.inHours);
    if (left.inMinutes >= 1) return at('expiresInMinutesShort', left.inMinutes);
    return l10n.t('expiringNow');
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
                  AppLocalizations.of(context).t('revoke'),
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
                    DecorBlob(size: 120, opacity: 0.30),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.tealMist,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.tealPale),
                        boxShadow: AppShadows.card,
                      ),
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        size: 36,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppLocalizations.of(context).t('noSharedLinksYet'),
                style: AppText.headline.copyWith(
                  color: palette.textPrimary,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppLocalizations.of(context).t('noSharedLinksSubtitle'),
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
