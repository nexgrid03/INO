import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/storage/shared_prefs_cache.dart';
import '../data/family_vault_repository.dart';
import '../l10n/app_localizations.dart';
import '../models/family_vault_models.dart';

import '../data/reminder_store.dart';
import '../repositories/document_repository.dart';
import 'app_settings.dart';
import 'biometric_service.dart';
import 'card_store.dart';
import 'family_vault_store.dart';

/// The category a notification belongs to (drives its icon / colour / filter).
enum NotificationCategory { reminder, security, backup, asset, document, system }

/// One notification shown in the Notifications page and counted on the bell.
///
/// [title] / [body] hold the English text. Notifications generated from app
/// state also carry [titleKey] / [bodyKey] (plus any [params]) so they can be
/// rendered in the user's language — resolve them with [resolveTitle] /
/// [resolveBody] rather than reading the raw fields, and the text follows a
/// language switch instead of freezing in whatever language it was built in.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.at,
    this.read = false,
    this.titleKey,
    this.bodyKey,
    this.params,
    this.targetId,
    this.targetWallet,
  });

  final String id; // stable across refreshes so read/dismissed state persists
  final String title;
  final String body;
  final NotificationCategory category;
  final DateTime at;
  final bool read;

  /// Translation keys for [title] / [body]; null for externally-sourced
  /// notifications that only ever have literal text.
  final String? titleKey;
  final String? bodyKey;

  /// Placeholder substitutions, e.g. `{name}` → the document's name.
  final Map<String, String>? params;

  /// Specific entity ID related to this notification (e.g., reminder ID, document ID, card ID).
  final String? targetId;

  /// Specific wallet name related to this notification (e.g., "Personal Documents", "Banking Wallet").
  final String? targetWallet;

  String _resolve(AppLocalizations l10n, String? key, String fallback) {
    if (key == null) return fallback;
    var out = l10n.t(key);
    final p = params;
    if (p != null) {
      for (final e in p.entries) {
        out = out.replaceAll('{${e.key}}', e.value);
      }
    }
    return out;
  }

  /// The title in the active language, falling back to the English [title].
  String resolveTitle(AppLocalizations l10n) =>
      _resolve(l10n, titleKey, title);

  /// The body in the active language, falling back to the English [body].
  String resolveBody(AppLocalizations l10n) => _resolve(l10n, bodyKey, body);

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        body: body,
        category: category,
        at: at,
        read: read ?? this.read,
        titleKey: titleKey,
        bodyKey: bodyKey,
        params: params,
        targetId: targetId,
        targetWallet: targetWallet,
      );
}

/// Generates and manages notifications from **real app state** - due reminders,
/// expiring documents, security posture (biometric / 2FA) and cloud-backup
/// health - and persists which ones the user has read or dismissed.
///
/// Notifications are derived (not stored server-side), so [refresh] rebuilds
/// them from current state and re-applies the persisted read/dismissed sets by
/// their stable ids. Exposed as a [ChangeNotifier] so the bell badge and the
/// list stay in sync everywhere.
class NotificationCenter extends ChangeNotifier {
  NotificationCenter._();
  static final NotificationCenter instance = NotificationCenter._();

  static const _kRead = 'notif_read_ids';
  static const _kDismissed = 'notif_dismissed_ids';

  final Set<String> _read = {};
  final Set<String> _dismissed = {};
  List<AppNotification> _all = [];
  bool _loaded = false;

  /// Visible (non-dismissed) notifications, newest first.
  List<AppNotification> get notifications => _all
      .where((n) => !_dismissed.contains(n.id))
      .map((n) => n.copyWith(read: _read.contains(n.id)))
      .toList()
    ..sort((a, b) => b.at.compareTo(a.at));

  int get unreadCount => notifications.where((n) => !n.read).length;
  bool get isLoaded => _loaded;

  Future<void>? _inFlightRefresh;

  /// Loads persisted read/dismissed state, then generates from current state.
  Future<void> load() async {
    if (_loaded && _inFlightRefresh == null) return;
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      _read
        ..clear()
        ..addAll(p.getStringList(_kRead) ?? const []);
      _dismissed
        ..clear()
        ..addAll(p.getStringList(_kDismissed) ?? const []);
    } catch (_) {
      // No plugin (tests) - start empty.
    }
    await refresh();
  }

  /// Rebuilds the notification list from live app state.
  Future<void> refresh() async {
    if (_inFlightRefresh != null) return _inFlightRefresh!;

    final future = _executeRefresh();
    _inFlightRefresh = future;
    try {
      await future;
    } finally {
      _inFlightRefresh = null;
    }
  }

  /// Translation key (and params) for a reminder due in [days] days.
  ///
  /// Mirrors `Reminder.localizedDueLabel` so the notification list and the
  /// reminder cards word the same due state identically. Returns `null` past
  /// two weeks, where the label is an absolute date rather than a phrase.
  static (String?, Map<String, String>?) _dueLabelKey(int days) {
    if (days < 0) {
      return days == -1
          ? ('overdueByOneDay', null)
          : ('overdueByDays', {'n': '${-days}'});
    }
    if (days == 0) return ('dueToday', null);
    if (days == 1) return ('dueTomorrow', null);
    if (days <= 6) return ('inDays', {'n': '$days'});
    if (days <= 13) return ('nextWeek', null);
    return (null, null);
  }

  Future<void> _executeRefresh() async {
    final items = <AppNotification>[];
    final now = DateTime.now();

    // Reminders due soon / overdue.
    try {
      await ReminderStore.instance.ensureLoaded();
      final today = ReminderStore.instance.today;
      for (final r in ReminderStore.instance.active) {
        final days = r.daysFrom(today);
        if (days <= 7) {
          // `title` is the user's own reminder text, so it is never
          // translated; only the derived due label is, reusing the same keys
          // as Reminder.localizedDueLabel.
          final (dueKey, dueParams) = _dueLabelKey(days);
          items.add(AppNotification(
            id: 'rem-${r.id}',
            title: r.title,
            body: r.dueLabel(today),
            category: NotificationCategory.reminder,
            at: days < 0 ? now : r.date,
            bodyKey: dueKey,
            params: dueParams,
            targetId: r.id,
          ));
        }
      }
    } catch (e) {
      developer.log('notif: reminders unavailable: $e', name: 'notif');
    }

    // Documents: expiring within 30 days.
    try {
      final docs = await DocumentRepository.instance.listAll();
      for (final d in docs) {
        final exp = d.expiresAt;
        if (exp == null) continue;
        final days = exp.difference(now).inDays;
        if (days >= 0 && days <= 30) {
          items.add(AppNotification(
            id: 'doc-exp-${d.id}',
            title: '${d.name} expires soon',
            body: days == 0 ? 'Expires today' : 'Expires in $days days',
            category: NotificationCategory.document,
            at: now,
            titleKey: 'notifDocExpiresSoon',
            bodyKey: days == 0 ? 'notifExpiresToday' : 'notifExpiresInDays',
            params: {'name': d.name, 'days': '$days'},
            targetId: d.id,
            targetWallet: d.wallet,
          ));
        }
      }
    } catch (e) {
      developer.log('notif: documents unavailable: $e', name: 'notif');
    }

    // Cards at or near their expiry month. Mirrors the `card.expiry` push from
    // the send-push Edge Function, so the in-app list and the notification tray
    // agree instead of each knowing about different things.
    try {
      await CardStore.instance.ensureLoaded();
      for (final c in CardStore.instance.needingAttention) {
        items.add(AppNotification(
          id: 'card-exp-${c.id}',
          title: c.isExpired
              ? '${c.bank} card ending ${c.last4} has expired'
              : '${c.bank} card ending ${c.last4} expires soon',
          body: c.isExpired
              ? 'Replace it to keep this card usable.'
              : 'Valid through ${c.expiryLabel}. Order a replacement in time.',
          category: NotificationCategory.asset,
          at: now,
          titleKey:
              c.isExpired ? 'notifCardExpired' : 'notifCardExpiresSoon',
          bodyKey: c.isExpired
              ? 'notifCardExpiredBody'
              : 'notifCardExpiresSoonBody',
          params: {
            'bank': c.bank,
            'last4': c.last4,
            'expiry': c.expiryLabel,
          },
          targetId: c.id,
          targetWallet: 'Banking Wallet',
        ));
      }
    } catch (e) {
      developer.log('notif: cards unavailable: $e', name: 'notif');
    }

    // Security posture.
    if (!BiometricService.instance.lockEnabled.value) {
      items.add(AppNotification(
        id: 'sec-biometric',
        title: 'Add a biometric lock',
        body: 'Protect your vault with Face ID or fingerprint.',
        category: NotificationCategory.security,
        at: now.subtract(const Duration(minutes: 30)),
        titleKey: 'notifAddBiometricLock',
        bodyKey: 'notifAddBiometricLockBody',
      ));
    }
    if (!AppSettings.instance.twoFactor.value) {
      items.add(AppNotification(
        id: 'sec-2fa',
        title: 'Enable two-factor authentication',
        body: 'Add a second layer of security to your account.',
        category: NotificationCategory.security,
        at: now.subtract(const Duration(hours: 1)),
        titleKey: 'notifEnable2fa',
        bodyKey: 'notifEnable2faBody',
      ));
    }

    // Backup health.
    final lastBackup = AppSettings.instance.lastBackupAt.value;
    if (lastBackup == null) {
      items.add(AppNotification(
        id: 'backup-none',
        title: 'Set up cloud backup',
        body: 'Back up your documents so you never lose them.',
        category: NotificationCategory.backup,
        at: now.subtract(const Duration(hours: 2)),
        titleKey: 'notifSetUpBackup',
        bodyKey: 'notifSetUpBackupBody',
      ));
    } else if (now.difference(lastBackup).inDays >= 7) {
      items.add(AppNotification(
        id: 'backup-stale',
        title: 'Backup is out of date',
        body: 'Your last backup was ${now.difference(lastBackup).inDays} days ago.',
        category: NotificationCategory.backup,
        at: now.subtract(const Duration(hours: 2)),
        titleKey: 'notifBackupStale',
        bodyKey: 'notifBackupStaleBody',
        params: {'days': '${now.difference(lastBackup).inDays}'},
      ));
    }

    await _appendFamilyVaultNotifications(items, now);

    _all = items;
    _loaded = true;
    notifyListeners();
  }

  /// Appends pending Family Vault invitations and recently shared Family Vault
  /// documents for the signed-in user from [notification_outbox] and
  /// [FamilyVaultStore].
  Future<void> _appendFamilyVaultNotifications(
      List<AppNotification> items, DateTime now) async {
    SupabaseClient? client;
    String? uid;
    try {
      client = Supabase.instance.client;
      uid = client.auth.currentUser?.id;
    } catch (_) {
      return;
    }
    if (uid == null) return;

    final seenIds = <String>{};
    var invitesLoaded = false;
    final pendingInvites = <VaultInvitation>[];
    try {
      await FamilyVaultStore.instance.refreshPendingInvitations();
      pendingInvites.addAll(FamilyVaultStore.instance.pendingInvites);
      invitesLoaded = true;
    } catch (e) {
      developer.log('vault invites refresh failed: $e', name: 'notifications');
    }
    final pendingById = {for (final i in pendingInvites) i.id: i};

    try {
      final rows = await client
          .from('notification_outbox')
          .select('id, kind, title, body, data, created_at')
          .eq('auth_user_id', uid)
          .inFilter('kind', ['vault.invite', 'vault.document_shared'])
          .order('created_at', ascending: false)
          .limit(50);

      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final kind = row['kind']?.toString() ?? '';
        final outboxId = row['id']?.toString() ?? '';
        final data = row['data'] is Map
            ? Map<String, dynamic>.from(row['data'] as Map)
            : const <String, dynamic>{};
        final createdAt =
            DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
                now;
        final title = row['title']?.toString() ?? '';
        final body = row['body']?.toString() ?? '';

        if (kind == 'vault.invite') {
          final invId = data['invitation_id']?.toString() ?? '';
          if (invitesLoaded &&
              invId.isNotEmpty &&
              !pendingById.containsKey(invId)) {
            continue;
          }
          final notifId =
              invId.isNotEmpty ? 'vault-invite-$invId' : 'vault-outbox-$outboxId';
          if (!seenIds.add(notifId)) continue;
          items.add(AppNotification(
            id: notifId,
            title: title.isNotEmpty ? title : 'Family Vault Invitation',
            body: body.isNotEmpty
                ? body
                : 'You have been invited to join a Family Vault.',
            category: NotificationCategory.system,
            at: createdAt,
            targetId: data['vault_id']?.toString(),
          ));
        } else if (kind == 'vault.document_shared') {
          final docId = data['vault_doc_id']?.toString() ?? '';
          final notifId =
              docId.isNotEmpty ? 'vault-doc-$docId' : 'vault-outbox-$outboxId';
          if (!seenIds.add(notifId)) continue;
          items.add(AppNotification(
            id: notifId,
            title: title.isNotEmpty ? title : 'New Family Document',
            body: body.isNotEmpty
                ? body
                : 'A document was shared in your Family Vault.',
            category: NotificationCategory.system,
            at: createdAt,
            targetId: data['vault_id']?.toString(),
          ));
        }
      }
    } catch (e) {
      developer.log('outbox vault fetch failed: $e', name: 'notifications');
    }

    for (final inv in pendingInvites) {
      final notifId = 'vault-invite-${inv.id}';
      if (!seenIds.add(notifId)) continue;
      final inviter = (inv.invitedByName ?? '').trim();
      final vaultName = (inv.vaultName ?? '').trim();
      final fromText = inviter.isNotEmpty
          ? '$inviter has invited you to their family'
          : 'You have been invited to join a family';
      final vaultSuffix = vaultName.isNotEmpty ? ' ($vaultName)' : '';
      items.add(AppNotification(
        id: notifId,
        title: 'Family Vault Invitation',
        body: '$fromText$vaultSuffix. Accept the invite to enter the family.',
        category: NotificationCategory.system,
        at: inv.createdAt ?? now,
        targetId: inv.vaultId,
      ));
    }

    // Fallback: guarantee any recently shared Family Vault document from
    // another member appears in the Bell feed even if outbox rows predate the
    // trigger or a re-share updated the row in place.
    try {
      await FamilyVaultStore.instance.ensureLoaded();
      final vaults = FamilyVaultStore.instance.vaults;
      if (vaults.isNotEmpty) {
        final cutoff = now.subtract(const Duration(days: 30));
        final perVaultDocs = await Future.wait([
          for (final summary in vaults.take(5))
            FamilyVaultRepository.instance
                .documents(summary.vault.id)
                .timeout(const Duration(seconds: 4))
                .then<List<VaultDocument>>((docs) => docs,
                    onError: (_) => const <VaultDocument>[]),
        ]);
        for (var i = 0; i < perVaultDocs.length; i++) {
          final summary = vaults[i];
          final vaultName = summary.vault.name.trim().isNotEmpty
              ? summary.vault.name.trim()
              : 'Family Vault';
          for (final doc in perVaultDocs[i]) {
            if (doc.sharedBy == uid || !doc.isVisibleToMembers) continue;
            if (doc.createdAt.isBefore(cutoff)) continue;
            final notifId = 'vault-doc-${doc.id}';
            if (!seenIds.add(notifId)) continue;
            items.add(AppNotification(
              id: notifId,
              title: 'New Document in $vaultName',
              body: 'A family member shared "${doc.name}" in $vaultName.',
              category: NotificationCategory.system,
              at: doc.createdAt.toLocal(),
              targetId: summary.vault.id,
            ));
          }
        }
      }
    } catch (e) {
      developer.log('vault docs fallback fetch failed: $e',
          name: 'notifications');
    }
  }

  Future<void> markRead(String id) async {
    if (_read.add(id)) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> markAllRead() async {
    _read.addAll(_all.map((n) => n.id));
    notifyListeners();
    await _persist();
  }

  Future<void> dismiss(String id) async {
    if (_dismissed.add(id)) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.setStringList(_kRead, _read.toList());
      await p.setStringList(_kDismissed, _dismissed.toList());
    } catch (_) {
      // Best-effort.
    }
  }

  /// Wipes the notification feed and its persisted read/dismissed state so a new
  /// account never inherits the previous user's notifications. The read/dismissed
  /// ids are stored under GLOBAL keys (not per-user), so they MUST be cleared on
  /// sign-out - otherwise the next user's notifications would show up pre-read.
  /// Called from [SessionReset].
  Future<void> clear() async {
    _all = [];
    _read.clear();
    _dismissed.clear();
    _loaded = false;
    notifyListeners();
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.remove(_kRead);
      await p.remove(_kDismissed);
    } catch (_) {
      // Best-effort.
    }
  }
}
