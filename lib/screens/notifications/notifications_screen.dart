import 'package:flutter/material.dart';

import '../../data/reminder_store.dart';
import '../../data/wallet_detail_repository.dart';
import '../../data/wallet_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/reminder_models.dart';
import '../../models/wallet_detail_models.dart';
import '../../navigation/wallet_module_router.dart';
import '../../services/document_protection_store.dart';
import '../../services/notification_center.dart';
import '../../services/vault_guard.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatting.dart';
import '../../widgets/home/empty_state.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/reminders/reminder_detail_sheet.dart';
import '../cards/cards_wallet_screen.dart';
import '../family/family_vault_screen.dart';
import '../profile/two_factor_screen.dart';
import '../reminders/all_reminders_screen.dart';
import '../shell/shell_controller.dart';
import '../wallet/document_viewer_screen.dart';

/// Notifications - a real, categorised feed generated from app state (due
/// reminders, expiring documents, security posture, backup health) with unread
/// tracking, mark-as-read, mark-all-read and swipe-to-dismiss.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _center = NotificationCenter.instance;

  @override
  void initState() {
    super.initState();
    _center.refresh();
  }

  Future<void> _handleNotificationTap(AppNotification n) async {
    await _center.markRead(n.id);
    if (!mounted) return;

    switch (n.category) {
      case NotificationCategory.reminder:
        final reminderId = n.targetId ??
            (n.id.startsWith('rem-') ? n.id.substring(4) : null);
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AllRemindersScreen()),
        );
        if (reminderId != null && mounted) {
          try {
            await ReminderStore.instance.ensureLoaded();
            final match = ReminderStore.instance.active
                .cast<Reminder?>()
                .firstWhere((r) => r?.id == reminderId, orElse: () => null);
            if (match != null && mounted) {
              await showReminderDetail(context, match);
            }
          } catch (_) {}
        }
        break;

      case NotificationCategory.document:
        final docId = n.targetId ??
            (n.id.startsWith('doc-exp-') ? n.id.substring(8) : null);
        final walletName = n.targetWallet;
        final category = walletName != null
            ? SupabaseWalletRepository.categoryFor(walletName)
            : null;

        if (docId != null && walletName != null && category != null) {
          try {
            final data =
                await WalletDetailRepository.instance.load(category);
            final doc = data.records
                .cast<DocumentRecord?>()
                .firstWhere((r) => r?.id == docId, orElse: () => null);
            if (doc != null && mounted) {
              final isProtected =
                  DocumentProtectionStore.instance.isProtected(doc.id);
              if (isProtected) {
                final unlocked = await VaultGuard.instance.ensureUnlocked(
                  context,
                  reason: AppLocalizations.of(context)
                      .t('authProtectedDocReason'),
                  title: AppLocalizations.of(context).t('verifyIdentity'),
                );
                if (!unlocked || !mounted) return;
              }
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentViewerScreen(
                    record: doc,
                    walletName: walletName,
                    accent: category.gradient,
                    protected: isProtected,
                  ),
                ),
              );
              return;
            }
          } catch (_) {}
        }

        if (category != null && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => walletScreenFor(category)),
          );
        } else if (mounted) {
          ShellController.tab.value = 1;
          Navigator.of(context).popUntil((r) => r.isFirst);
        }
        break;

      case NotificationCategory.asset:
        // Both lookups can miss (a renamed or removed built-in), and a bare
        // firstWhere throws StateError rather than returning null — which
        // turned "tap an asset alert" into a dead tap with a swallowed error.
        final category =
            SupabaseWalletRepository.categoryFor('Banking Wallet') ??
                SupabaseWalletRepository.builtIns
                    .where((c) => c.name == 'Banking Wallet')
                    .firstOrNull;
        if (category == null) {
          // Nothing specific to open — fall back to the Vault tab.
          ShellController.tab.value = 1;
          Navigator.of(context).popUntil((r) => r.isFirst);
          break;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CardsWalletScreen(category: category),
          ),
        );
        break;

      case NotificationCategory.security:
        if (n.id == 'sec-2fa') {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TwoFactorScreen()),
          );
        } else {
          ShellController.tab.value = 4;
          Navigator.of(context).popUntil((r) => r.isFirst);
        }
        break;

      case NotificationCategory.backup:
        ShellController.tab.value = 4;
        Navigator.of(context).popUntil((r) => r.isFirst);
        break;

      case NotificationCategory.system:
        if (n.id.contains('vault')) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FamilyVaultScreen()),
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _center,
      builder: (context, _) {
        final allItems = _center.notifications;
        final unreadItems = allItems.where((n) => !n.read).toList();
        final readItems = allItems.where((n) => n.read).toList();

        return SettingsScaffold(
          title: l10n.t('notifications'),
          actions: [
            if (_center.unreadCount > 0)
              _MarkAllReadPill(
                label: l10n.t('markAllRead'),
                onTap: _center.markAllRead,
              ),
          ],
          child: _buildBody(
            context,
            l10n,
            unreadItems: unreadItems,
            readItems: readItems,
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n, {
    required List<AppNotification> unreadItems,
    required List<AppNotification> readItems,
  }) {
    final palette = AppPalette.of(context);
    final visibleItems = [...unreadItems, ...readItems];

    if (visibleItems.isEmpty) {
      return EmptyState(
        icon: Icons.notifications_off_rounded,
        title: l10n.t('allCaughtUp'),
        message: l10n.t('noNewNotifications'),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _center.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.sm,
          AppSpacing.screen,
          AppSpacing.xl,
        ),
        children: [
          if (unreadItems.isNotEmpty) ...[
            _SectionHeader(
              title: l10n.t('unread'),
              count: unreadItems.length,
              accent: AppColors.primaryGreen,
            ),
            for (final n in unreadItems) _dismissible(l10n, n),
          ],
          if (readItems.isNotEmpty) ...[
            SizedBox(height: unreadItems.isEmpty ? 0 : AppSpacing.lg),
            _SectionHeader(
              title: l10n.t('recentActivity'),
              count: readItems.length,
              accent: palette.textFaint,
            ),
            for (final n in readItems) _dismissible(l10n, n),
          ],
        ],
      ),
    );
  }

  Widget _dismissible(AppLocalizations l10n, AppNotification n) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Dismissible(
          key: ValueKey(n.id),
          direction: DismissDirection.endToStart,
          background: _dismissBg(l10n),
          onDismissed: (_) => _center.dismiss(n.id),
          child: _NotificationTile(
            notification: n,
            onTap: () => _handleNotificationTap(n),
          ),
        ),
      );

  /// What shows behind a card as it is swiped away.
  ///
  /// A bare icon on a faint wash read as an accident rather than an action, so
  /// this states the outcome: a tinted panel matching the card's own shape,
  /// with the word for it beside the glyph.
  Widget _dismissBg(AppLocalizations l10n) => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              AppColors.critical.withValues(alpha: 0.08),
              AppColors.critical.withValues(alpha: 0.24),
            ],
          ),
          border: Border.all(
            color: AppColors.critical.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.critical,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.t('delete'),
              style: const TextStyle(
                color: AppColors.critical,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
}

/// One notification.
///
/// The old card was a frosted pane over the screen's teal aurora, which left
/// the copy sitting on a moving, similarly-toned backdrop: legible in a mockup,
/// washed out on a phone. So the card carries its own opaque ground now, and
/// the theme shows through around it rather than behind the text.
///
/// Unread state is carried by three things at once, because one is easy to
/// miss: a colour rail down the leading edge, a brighter icon, and a brand dot
/// in the trailing corner. Read cards drop all three and mute their icon, so
/// the two states are separable at a glance rather than by hunting for a dot.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  /// Glyph and accent per category — the colour the rail and icon share, so
  /// each card reads as one accent rather than two competing ones.
  ({IconData icon, Color color}) get _style {
    switch (notification.category) {
      case NotificationCategory.reminder:
        return (icon: Icons.alarm_rounded, color: AppColors.warning);
      case NotificationCategory.security:
        return (icon: Icons.shield_rounded, color: AppColors.critical);
      case NotificationCategory.backup:
        return (icon: Icons.cloud_sync_rounded, color: AppColors.lightBlue);
      case NotificationCategory.asset:
        return (
          icon: Icons.account_balance_wallet_rounded,
          color: AppColors.primaryGreen
        );
      case NotificationCategory.document:
        return (
          icon: Icons.description_rounded,
          color: AppColors.secondaryGreen
        );
      case NotificationCategory.system:
        return (icon: Icons.info_rounded, color: AppColors.lightBlue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final style = _style;
    final dark = palette.isDark;
    final unread = !notification.read;

    // A read card recedes: same layout, less ink. Applied as one alpha on the
    // accent rather than a second set of colours to keep in step.
    final accent = unread ? style.color : style.color.withValues(alpha: 0.45);
    final radius = BorderRadius.circular(AppRadius.card);

    // The card's own ground stays NEUTRAL, and the category colour is confined
    // to the rail and the gem. Tinting the whole card by category turned the
    // list into a pastel rainbow — pink security cards, cream reminders — which
    // is a different app's palette, not INO's. Unread instead takes the
    // faintest brand wash, so the page reads teal the way every other screen
    // does and the accents stay accents.
    final base = dark ? palette.surface : Colors.white;
    // Unread sits solid and forward; read is let through to the aurora behind
    // it so it settles back. Doing it with alpha on the fill rather than an
    // [Opacity] around the card keeps it to one paint instead of a saveLayer
    // per row down a scrolling list.
    final surface = unread
        ? Color.alphaBlend(
            AppColors.primaryGreen.withValues(alpha: dark ? 0.07 : 0.03),
            base,
          )
        : base.withValues(alpha: dark ? 0.55 : 0.62);

    return Semantics(
      button: true,
      selected: unread,
      child: DecoratedBox(
        // Shadow on the OUTER box: the clip below would eat it.
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: unread
                  ? AppColors.primaryGreen.withValues(alpha: dark ? 0.22 : 0.14)
                  : Colors.black.withValues(alpha: dark ? 0.22 : 0.05),
              blurRadius: unread ? 18 : 10,
              spreadRadius: -4,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: radius,
            border: Border.all(
              color: unread
                  ? AppColors.primaryGreen.withValues(alpha: dark ? 0.30 : 0.18)
                  : palette.border,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              splashColor: style.color.withValues(alpha: 0.10),
              highlightColor: style.color.withValues(alpha: 0.05),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The unread rail. Read cards keep the same 4px so both
                    // states share one text baseline down the list.
                    SizedBox(
                      width: 4,
                      child: unread
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    style.color,
                                    style.color.withValues(alpha: 0.45),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(13, 14, 14, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CategoryGem(
                              icon: style.icon,
                              color: accent,
                              vivid: unread,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    notification.resolveTitle(l10n),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.subtitle.copyWith(
                                      color: palette.textPrimary,
                                      fontWeight:
                                          unread ? FontWeight.w800 : FontWeight.w600,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    notification.resolveBody(l10n),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.body.copyWith(
                                      color: palette.textSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Time and unread dot share one trailing stack, so
                            // the card's right edge stays a single column
                            // however many lines the title runs to.
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatRelativeDate(l10n, notification.at),
                                  style: AppText.caption.copyWith(
                                    color: palette.textFaint,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (unread) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryGreen,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primaryGreen
                                              .withValues(alpha: 0.45),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
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
    );
  }
}

/// The rounded category glyph.
///
/// [vivid] is the unread treatment: a stronger fill, a defined rim and a soft
/// halo. Read notifications get the same shape at a fraction of the ink, which
/// is what lets the eye skip them.
class _CategoryGem extends StatelessWidget {
  const _CategoryGem({
    required this.icon,
    required this.color,
    required this.vivid,
  });

  final IconData icon;
  final Color color;
  final bool vivid;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: vivid ? 0.26 : 0.12),
            color.withValues(alpha: vivid ? 0.13 : 0.06),
          ],
        ),
        border: Border.all(
          color: color.withValues(alpha: vivid ? 0.38 : 0.18),
        ),
        boxShadow: vivid
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.20),
                  blurRadius: 10,
                  spreadRadius: -2,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// A list section's title.
///
/// The hairline rule this used to stretch across the row read as clutter over
/// the screen's aurora, so the label carries itself: an accent dot, the title,
/// and the count in a tinted chip.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.accent,
  });

  final String title;
  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          // Shrinks rather than clips: the Hindi and Telugu section titles are
          // considerably longer than the English ones.
          Flexible(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Mark all read" action in the Notifications header.
///
/// This used to be a bare [TextButton] tinted `primaryGreen`, sitting on the
/// screen's teal header — brand text on a brand-tinted backdrop, which left it
/// barely distinguishable from the gradient behind it. A destructive-ish bulk
/// action that reads as decoration is one nobody finds.
///
/// So it is a filled pill instead, and deliberately in the same visual language
/// as the bottom dock's "+" gem: brand gradient, a white hairline rim, and a
/// tight brand glow. That reads as part of INO rather than a generic chip
/// dropped into the app bar, and white-on-brand clears contrast comfortably
/// where brand-on-brand never could.
///
/// The label is required to stay, so it has to survive translation: the Hindi
/// and Telugu strings are several times the width of "Mark all read". The pill
/// takes at most a little under half the screen and scales its contents down
/// inside that, so the text is always whole and never clipped to an ellipsis.
class _MarkAllReadPill extends StatelessWidget {
  const _MarkAllReadPill({required this.label, required this.onTap});

  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryGreen;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Center(
        child: PressableScale(
          pressedScale: 0.94,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.46,
            ),
            // Shadow on the OUTER box: the clip below would eat it.
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(19),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.36),
                    blurRadius: 14,
                    spreadRadius: -3,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(19),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, accent.withValues(alpha: 0.84)],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    splashColor: Colors.white.withValues(alpha: 0.24),
                    highlightColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.done_all_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                height: 1.1,
                                letterSpacing: 0.1,
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
        ),
      ),
    );
  }
}
