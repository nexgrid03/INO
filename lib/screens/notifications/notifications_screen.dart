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
        final category =
            SupabaseWalletRepository.categoryFor('Banking Wallet') ??
                SupabaseWalletRepository.builtIns
                    .firstWhere((c) => c.name == 'Banking Wallet');
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
    return SettingsScaffold(
      title: l10n.t('notifications'),
      actions: [
        ListenableBuilder(
          listenable: _center,
          builder: (context, _) {
            if (_center.unreadCount == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: TextButton(
                  onPressed: _center.markAllRead,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.primaryGreen,
                  ),
                  child: Text(
                    l10n.t('markAllRead'),
                    style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
      child: ListenableBuilder(
        listenable: _center,
        builder: (context, _) {
          final items = _center.notifications;
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_off_rounded,
              title: l10n.t('allCaughtUp'),
              message: l10n.t('noNewNotifications'),
            );
          }
          return RefreshIndicator(
            color: AppColors.primaryGreen,
            onRefresh: _center.refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.sm,
                AppSpacing.screen,
                AppSpacing.xl,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final n = items[i];
                return Dismissible(
                  key: ValueKey(n.id),
                  direction: DismissDirection.endToStart,
                  background: _dismissBg(),
                  onDismissed: (_) => _center.dismiss(n.id),
                  child: _NotificationTile(
                    notification: n,
                    onTap: () => _handleNotificationTap(n),
                  ),
                );
              },
            ),
          );
        },
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
