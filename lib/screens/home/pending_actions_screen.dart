import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../data/reminder_store.dart';
import '../../data/wallet_repository.dart';
import '../../models/document.dart';
import '../../models/reminder_models.dart';
import '../../repositories/document_repository.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/home/empty_state.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/common/liquid_glass.dart';
import '../../widgets/pressable_scale.dart';
import '../../navigation/wallet_module_router.dart';
import '../shell/shell_controller.dart';
import '../../widgets/common/ino_loader.dart';

/// A pending item - either a due reminder or an expiring document.
class _Pending {
  const _Pending({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.urgencyColor,
    required this.urgency,
    this.wallet,
  });
  final String title;
  final String subtitle;
  final IconData icon;

  /// Icon badge colour (category / vault accent — never urgency sky-blue).
  final Color accent;

  /// Due-chip colour (critical / warning / brand teal).
  final Color urgencyColor;
  final String urgency;
  final String? wallet; // set for documents → opens that wallet
}

/// Pending Actions - everything that needs the user's attention: overdue / due
/// reminders and documents expiring within 30 days, from real data.
class PendingActionsScreen extends StatefulWidget {
  const PendingActionsScreen({super.key});

  @override
  State<PendingActionsScreen> createState() => _PendingActionsScreenState();
}

class _PendingActionsScreenState extends State<PendingActionsScreen> {
  List<_Pending>? _items;
  bool _error = false;

  /// The locale the loaded items were built for - re-running the load when it
  /// changes is what makes the due/expiry copy follow a language switch.
  Locale? _loadedLocale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_loadedLocale != locale) {
      _loadedLocale = locale;
      _load();
    }
  }

  Future<void> _load() async {
    final l10n = AppLocalizations.of(context);
    try {
      final items = <_Pending>[];

      // Reminders due within a week or overdue.
      await ReminderStore.instance.ensureLoaded();
      final today = ReminderStore.instance.today;
      for (final r in ReminderStore.instance.active) {
        if (r.daysFrom(today) <= 7) {
          items.add(_Pending(
            title: r.title,
            subtitle: r.subtitle.isEmpty
                ? r.category.localizedLabel(l10n)
                : r.subtitle,
            icon: r.category.icon,
            accent: r.category.color,
            urgencyColor: reminderUrgencyColor(r, today),
            urgency: r.localizedDueLabel(today, l10n),
          ));
        }
      }

      // Documents expiring within 30 days.
      try {
        final docs = await DocumentRepository.instance.listAll();
        for (final d in docs) {
          final exp = d.expiresAt;
          if (exp == null) continue;
          final days = exp.difference(DateTime.now()).inDays;
          if (days >= 0 && days <= 30) {
            items.add(_pendingFromDoc(d, days, l10n));
          }
        }
      } catch (_) {
        // Offline / signed out - reminders alone still populate the page.
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = true);
    }
  }

  _Pending _pendingFromDoc(Document d, int days, AppLocalizations l10n) =>
      _Pending(
        title: l10n.t('notifDocExpiresSoon').replaceAll('{name}', d.name),
        subtitle: '${d.category ?? l10n.t('document')} · ${d.wallet}',
        icon: Icons.event_busy_rounded,
        accent: AppColors.primaryGreen,
        urgencyColor: days <= 7 ? AppColors.critical : AppColors.warning,
        urgency: days == 0
            ? l10n.t('notifExpiresToday')
            : l10n.t('inDays').replaceAll('{n}', '$days'),
        wallet: d.wallet,
      );

  void _open(_Pending p) {
    if (p.wallet != null) {
      final category = SupabaseWalletRepository.categoryFor(p.wallet!);
      if (category != null) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => walletScreenFor(category)));
        return;
      }
    }
    // Reminders live on the Reminders tab.
    Navigator.of(context).popUntil((r) => r.isFirst);
    ShellController.tab.value = 3;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = _items;
    return SettingsScaffold(
      title: l10n.t('pendingActions'),
      child: _error
          ? ErrorRetry(onRetry: _load)
          : items == null
              ? const Center(child: InoLoader())
              : items.isEmpty
                  ? EmptyState(
                      icon: Icons.task_alt_rounded,
                      title: l10n.t('nothingPending'),
                      message: l10n.t('nothingPendingSubtitle'),
                    )
                  : RefreshIndicator(
                      color: AppColors.primaryGreen,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                            AppSpacing.md, AppSpacing.screen, AppSpacing.xl),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) =>
                            _PendingTile(item: items[i], onTap: () => _open(items[i])),
                      ),
                    ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.item, required this.onTap});

  final _Pending item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(AppRadius.card),
          blur: 16,
          frost: palette.isDark ? 1.05 : 0.72,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: item.urgencyColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  item.urgency,
                  style: AppText.label.copyWith(
                    color: item.urgencyColor,
                    fontSize: 11,
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
