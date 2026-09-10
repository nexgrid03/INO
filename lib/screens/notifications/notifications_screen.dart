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
import '../../widgets/divine_glass/divine_glass.dart';
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
            if (readItems.isNotEmpty)
              _SectionHeader(
                title: 'UNREAD NOTIFICATIONS',
                count: unreadItems.length,
                color: AppColors.primaryGreen,
              ),
            for (final n in unreadItems) ...[
              const SizedBox(height: 8),
              Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                background: _dismissBg(),
                onDismissed: (_) => _center.dismiss(n.id),
                child: _NotificationTile(
                  notification: n,
                  onTap: () => _handleNotificationTap(n),
                ),
              ),
            ],
          ],
          if (readItems.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionHeader(
              title: 'RECENT ACTIVITY',
              count: readItems.length,
              color: palette.textFaint,
            ),
            for (final n in readItems) ...[
              const SizedBox(height: 8),
              Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                background: _dismissBg(),
                onDismissed: (_) => _center.dismiss(n.id),
                child: _NotificationTile(
                  notification: n,
                  onTap: () => _handleNotificationTap(n),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _dismissBg() => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.critical.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.critical,
        ),
      );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

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
    final glass = divineGlassEnabled(context);

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: style.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: style.color.withValues(alpha: 0.22),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(style.icon, color: style.color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      notification.resolveTitle(l10n),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (!notification.read) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                notification.resolveBody(l10n),
                style: AppText.body.copyWith(
                  color: palette.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatRelativeDate(l10n, notification.at),
                style: AppText.caption.copyWith(color: palette.textFaint),
              ),
            ],
          ),
        ),
      ],
    );

    final card = glass
        ? AdaptiveGlassCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            radius: AppRadius.card,
            child: body,
          )
        : Material(
            color: notification.read
                ? palette.surface
                : Color.alphaBlend(
                    style.color.withValues(alpha: 0.05),
                    palette.surface,
                  ),
            borderRadius: BorderRadius.circular(AppRadius.card),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: palette.border),
              ),
              padding: const EdgeInsets.all(14),
              child: body,
            ),
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: card,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: palette.border)),
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
