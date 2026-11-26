import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/reminder_store.dart';
import '../data/wallet_repository.dart';
import '../firebase_options.dart';
import '../models/reminder_models.dart';
import '../screens/family/family_vault_screen.dart';
import '../screens/family/vault_detail_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/trusted_devices_screen.dart';
import '../screens/reminders/all_reminders_screen.dart';
import '../screens/wallet/wallet_detail_screen.dart';
import '../widgets/reminders/reminder_detail_sheet.dart';
import 'app_settings.dart';
import 'auth_service.dart';
import 'family_vault_store.dart';
import 'notification_center.dart';
import 'security_alert_service.dart';

/// Reminder push notifications, delivered over Firebase Cloud Messaging.
///
/// **Firebase is only the transport.** The reminders themselves live in
/// Supabase (`public.reminders`, see [ReminderStore] / `ReminderRepository`),
/// and the decision of *who is due today* is made by the `send-reminder-push`
/// Edge Function on a cron. This class does three things and nothing else:
///
///   1. **Registers the device.** Gets the FCM token and upserts it into
///      `public.device_tokens` so the Edge Function knows where to send. The
///      token is per-install, not per-user, so it is re-stamped with the
///      current `auth_user_id` on every sign-in and **deleted on sign-out** -
///      without that, the next account to use this phone would receive the
///      previous account's reminders (see [unregisterToken]).
///   2. **Displays messages.** Android delivers a `notification` payload to the
///      system tray only while the app is backgrounded/killed; when the app is
///      FOREGROUNDED the payload is handed to Dart and shown nowhere. So a
///      foreground message is re-displayed here via `flutter_local_notifications`
///      on a channel whose id matches `default_notification_channel_id` in
///      AndroidManifest.xml.
///   3. **Routes taps.** `data.reminder_id` opens that reminder's detail sheet;
///      anything else falls back to the full reminders list.
///
/// Every step logs under `push`, and no call ever throws: push is an enhancement
/// and must never be able to break sign-in or app start.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  /// Must match `com.google.firebase.messaging.default_notification_channel_id`
  /// in AndroidManifest.xml. Android 8+ silently DROPS a notification posted to
  /// a channel that does not exist, so the two must never drift apart.
  static const String channelId = 'ino_reminders';

  /// A SEPARATE channel for security alerts (new sign-in, password change, 2FA).
  ///
  /// Deliberately its own channel so a user who mutes renewal reminders does not
  /// also silence "your password was changed" — Android lets people disable
  /// channels individually, and bundling these together would mean the least
  /// important notification could switch off the most important one.
  static const String securityChannelId = 'ino_security';

  static const String _table = 'device_tokens';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// Completes once the local-notification plugin is initialised and the
  /// channels exist. [ReminderScheduler] awaits this before scheduling, since
  /// [init] is deferred past the first frame and a reminder can be created (or
  /// the store hydrated) before it has run.
  final Completer<void> _localReady = Completer<void>();
  Future<void> get localReady => _localReady.future;

  /// How a reminder notification looks, shared by the foreground bridge, the
  /// exact-time local schedule and the background data-message handler so the
  /// three are indistinguishable to the user.
  /// Configured with [NotificationVisibility.private] and a generic public
  /// notification to prevent data leakage on lock screens.
  static const NotificationDetails reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      'Reminders',
      channelDescription: 'Alerts for documents, renewals and due dates.',
      importance: Importance.max,
      priority: Priority.max,
      visibility: NotificationVisibility.private,
      icon: 'ic_notification',
      playSound: true,
      enableVibration: true,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  GlobalKey<NavigatorState>? _navigatorKey;
  GlobalKey<ScaffoldMessengerState>? _messengerKey;
  bool _initialised = false;
  bool _vaultPermPrompted = false;
  String? _token;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  RealtimeChannel? _outboxChannel;
  String? _outboxUid;
  final Set<String> _shownOutboxIds = <String>{};
  final Set<String> _notifiedDocIds = <String>{};

  /// The current FCM registration token, once [init] has run.
  String? get token => _token;

  // ---------------------------------------------------------------------------
  // Start-up
  // ---------------------------------------------------------------------------

  /// Initialises Firebase, local notifications and message handlers.
  /// PRIVACY COMPLIANCE: Does NOT raise permission prompt automatically on cold start.
  /// Call once from `main()`, before `runApp`. Idempotent and never throws.
  Future<void> init(
    GlobalKey<NavigatorState> navigatorKey, {
    GlobalKey<ScaffoldMessengerState>? messengerKey,
  }) async {
    _navigatorKey = navigatorKey;
    _messengerKey = messengerKey ?? _messengerKey;
    if (_initialised) return;

    try {
      // Local notifications first: the exact-time reminder schedule depends
      // only on this, so a Firebase failure (missing google-services, no Play
      // services) must not take local reminders down with it.
      await _initLocalNotifications();

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Registered before anything else: when a message arrives with the app
      // killed, Flutter spins up a SEPARATE isolate and calls this. It must be
      // a top-level function and cannot touch any state from this isolate.
      FirebaseMessaging.onBackgroundMessage(inoFirebaseBackgroundHandler);

      _listenForSignIn();
      unawaited(_checkExistingPermissionAndInitToken());
      _subscribeOutboxRealtime();

      // Foreground messages: Android hands them to Dart instead of the tray.
      _foregroundSub = FirebaseMessaging.onMessage
          .listen(_onForegroundMessage);

      // Tap on a notification that was shown while the app was BACKGROUNDED.
      _openedAppSub = FirebaseMessaging.onMessageOpenedApp
          .listen(_onNotificationTapped);

      // Tap on a notification that COLD-LAUNCHED the app. Delivered once.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        developer.log('cold start from notification', name: 'push');
        _onNotificationTapped(initial);
      }

      _initialised = true;
      developer.log('push initialised (permission prompt deferred)', name: 'push');
    } catch (e, st) {
      developer.log('init failed: $e', name: 'push', error: e, stackTrace: st);
    } finally {
      // Unblock anyone waiting on the local plugin even if Firebase failed:
      // exact-time local reminders do not need Firebase at all.
      if (!_localReady.isCompleted) _localReady.complete();
    }
  }

  /// Creates the Android channel and wires the local-notification tap handler.
  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('ic_notification');
    // `requestAlertPermission: false` - the iOS prompt is raised once by
    // [requestPermission] via firebase_messaging instead, so the user is not
    // asked twice by two different plugins.
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      settings:
          const InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = (jsonDecode(payload) as Map).cast<String, dynamic>();
          _route(data);
        } catch (e) {
          developer.log('bad local payload: $e', name: 'push');
        }
      },
    );

    // Create the channel explicitly. Android derives a channel's importance at
    // CREATION time and ignores later changes, so it must be born as `high` -
    // otherwise reminders never produce a heads-up banner.
    const channel = AndroidNotificationChannel(
      channelId,
      'Reminders',
      description: 'Alerts for documents, renewals and due dates.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    // Security alerts get `max` importance: these are the ones worth
    // interrupting for, and a channel's importance is fixed at creation.
    const securityChannel = AndroidNotificationChannel(
      securityChannelId,
      'Security alerts',
      description:
          'Sign-ins, password changes and two-factor updates on your account.',
      importance: Importance.max,
    );

    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(channel);
    await android?.createNotificationChannel(securityChannel);
    if (!_localReady.isCompleted) _localReady.complete();
  }

  /// Raises the OS permission prompt (Android 13+ / iOS) on demand (when user turns on notifications or uses a reminder feature).
  /// Returns `true` if permission is granted.
  Future<bool> requestPermission() async {
    try {
      bool granted = false;

      if (!kIsWeb && Platform.isAndroid) {
        // Native Android 13+ runtime permission prompt
        final status = await Permission.notification.request();
        granted = status.isGranted || status.isLimited;
        if (!granted) {
          final android = _local.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
          granted = await android?.requestNotificationsPermission() ?? false;
        }
      } else {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        granted =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      }

      developer.log('notification permission granted: $granted', name: 'push');

      if (!AppSettings.instance.notifications.value) {
        developer.log(
          'requestPermission: notifications setting is disabled; skipping consent record',
          name: 'push',
        );
        return false;
      }

      if (!kIsWeb && Platform.isIOS) {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // Always initialize and register the device token
      await _initToken();
      if (granted) {
        await AuthService.instance.recordPushNotificationConsent();
      }
      return granted;
    } catch (e) {
      developer.log('requestPermission error: $e', name: 'push');
      return false;
    }
  }

  /// Prompts for OS notification permission once per session if notifications
  /// are enabled in INO settings and OS permission has not been granted yet.
  Future<void> requestPermissionIfNeeded() async {
    if (_vaultPermPrompted || !AppSettings.instance.notifications.value) return;
    _vaultPermPrompted = true;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final status = await Permission.notification.status;
        if (status.isGranted || status.isLimited) {
          await _checkExistingPermissionAndInitToken();
          return;
        }
      } else if (!kIsWeb && Platform.isIOS) {
        final settings =
            await FirebaseMessaging.instance.getNotificationSettings();
        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          await _checkExistingPermissionAndInitToken();
          return;
        }
      }
      await requestPermission();
    } catch (e) {
      developer.log('requestPermissionIfNeeded error: $e', name: 'push');
    }
  }

  /// Fetches the token and keeps it fresh. FCM rotates tokens (app restore,
  /// data clear, long idle), and a stale token silently stops receiving - so
  /// the refresh stream must be persisted too, not just the first value.
  Future<void> _initToken() async {
    // On iOS the FCM token is only available AFTER APNs has handed over its
    // device token; asking too early returns null rather than throwing.
    _token = await FirebaseMessaging.instance.getToken();
    developer.log('token → ${_describeToken(_token)}', name: 'push');
    await registerToken();

    _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (fresh) {
        developer.log('token refreshed → ${_describeToken(fresh)}',
            name: 'push');
        _token = fresh;
        unawaited(registerToken());
      },
      onError: (Object e) => developer.log('token refresh error: $e',
          name: 'push'),
    );
  }

  // ---------------------------------------------------------------------------
  // Token ↔ account binding
  // ---------------------------------------------------------------------------

  /// Re-stamps the token with whoever is signed in now.
  ///
  /// Bound to the auth stream rather than to each sign-in method on purpose:
  /// there are five ways into a session (email, Google, phone OTP, sign-up OTP,
  /// and a restored session on cold start) and a token registered on only some
  /// of them fails invisibly - the user simply never gets a notification. One
  /// listener covers all of them and cannot drift as auth paths are added.
  ///
  /// The counterpart is NOT here: sign-out is handled explicitly in
  /// `AuthService.signOut` because the delete has to happen *before* the
  /// session is torn down, which a `signedOut` event is too late for.
  void _listenForSignIn() {
    _authSub ??= Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.initialSession ||
            state.event == AuthChangeEvent.tokenRefreshed) {
          unawaited(_checkExistingPermissionAndInitToken());
          _subscribeOutboxRealtime();
        }
        // Only a REAL sign-in raises the security alert. `initialSession` fires
        // on every cold start with a restored session — alerting on that would
        // tell users "your account was signed in" every time they opened the
        // app, which trains them to ignore the one alert that matters.
        if (state.event == AuthChangeEvent.signedIn) {
          unawaited(SecurityAlertService.instance.signedIn());
        }
        if (state.event == AuthChangeEvent.signedOut) {
          _stopOutboxRealtime();
          _shownOutboxIds.clear();
        }
      },
      onError: (Object e) =>
          developer.log('auth stream error: $e', name: 'push'),
    );
  }

  /// Re-arms the Realtime listener when resuming from background if needed.
  void ensureRealtimeActive() => _subscribeOutboxRealtime();

  /// Listens to new [notification_outbox] rows for the signed-in user so
  /// Family Vault invites and shared-doc events surface immediately in-app even
  /// before an FCM banner arrives or on devices without FCM permission yet.
  void _subscribeOutboxRealtime() {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) {
        _stopOutboxRealtime();
        return;
      }
      if (_outboxUid == uid && _outboxChannel != null) return;
      _stopOutboxRealtime();
      _outboxUid = uid;
      final ch = client.channel('push_outbox_$uid');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notification_outbox',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'auth_user_id',
          value: uid,
        ),
        callback: (payload) {
          unawaited(_onOutboxInsert(payload.newRecord));
        },
      );
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'vault_documents',
        callback: (payload) {
          if (payload.eventType == PostgresChangeEvent.delete) return;
          unawaited(_onVaultDocChange(payload.newRecord));
        },
      );
      ch.subscribe();
      _outboxChannel = ch;
    } catch (e) {
      developer.log('outbox realtime subscribe error: $e', name: 'push');
    }
  }

  void _stopOutboxRealtime() {
    final ch = _outboxChannel;
    _outboxChannel = null;
    _outboxUid = null;
    if (ch != null) {
      try {
        Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
  }

  Future<void> _onOutboxInsert(Map<String, dynamic> row) async {
    final kind = (row['kind'] as String?) ?? '';
    if (!kind.startsWith('vault.')) return;
    final outboxId = row['id']?.toString() ?? '';
    final rawData = row['data'];
    final data = <String, dynamic>{
      if (rawData is Map)
        for (final e in rawData.entries) e.key.toString(): e.value,
      'kind': kind,
      if (outboxId.isNotEmpty) 'outbox_id': outboxId,
    };
    final vaultDocId = data['vault_doc_id']?.toString() ?? '';
    if (vaultDocId.isNotEmpty) _notifiedDocIds.add(vaultDocId);

    final title = (row['title'] as String?) ?? '';
    final body = (row['body'] as String?) ?? '';
    if (title.isNotEmpty &&
        outboxId.isNotEmpty &&
        _shownOutboxIds.add(outboxId) &&
        AppSettings.instance.notifications.value) {
      _showInAppVaultBanner(title: title, body: body, data: data);
      try {
        await localReady;
        await _local.show(
          id: reminderNotificationId(data, outboxId),
          title: title,
          body: body,
          notificationDetails: reminderDetails,
          payload: jsonEncode(data),
        );
      } catch (e) {
        developer.log('outbox local notify error: $e', name: 'push');
      }
    }
    if (kind == 'vault.invite') {
      unawaited(FamilyVaultStore.instance.refreshPendingInvitations());
    } else if (kind == 'vault.document_shared') {
      unawaited(FamilyVaultStore.instance.reload());
    }
    await refreshFeed();
  }

  Future<void> _onVaultDocChange(Map<String, dynamic> row) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    if (row['shared_by']?.toString() == uid) return;
    if (row['is_hidden'] == true) return;

    final docId = row['id']?.toString() ?? '';
    final vaultId = row['vault_id']?.toString() ?? '';
    final docName = row['name']?.toString().trim() ?? 'a document';

    unawaited(FamilyVaultStore.instance.reload());
    await refreshFeed();

    // Give notification_outbox Realtime a brief head start so we do not stack
    // a duplicate banner if the outbox trigger already fired.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (docId.isEmpty ||
        !_notifiedDocIds.add(docId) ||
        !AppSettings.instance.notifications.value) {
      return;
    }

    final data = <String, dynamic>{
      'kind': 'vault.document_shared',
      'vault_id': vaultId,
      'vault_doc_id': docId,
      'outbox_id': 'doc:$docId',
    };
    const title = 'New Document in Family Vault';
    final body = 'A family member shared "$docName" in your Family Vault.';
    _showInAppVaultBanner(title: title, body: body, data: data);
    try {
      await localReady;
      await _local.show(
        id: reminderNotificationId(data, docId),
        title: title,
        body: body,
        notificationDetails: reminderDetails,
        payload: jsonEncode(data),
      );
    } catch (e) {
      developer.log('vault doc local notify error: $e', name: 'push');
    }
  }

  void _showInAppVaultBanner({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    final messenger = _messengerKey?.currentState;
    if (messenger == null) return;
    final text = body.isNotEmpty ? '$title: $body' : title;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => _route(data),
        ),
      ),
    );
  }

  /// Automatically fetches and registers the FCM token so the device is reachable by the server push.
  Future<void> _checkExistingPermissionAndInitToken() async {
    if (!AppSettings.instance.notifications.value) return;
    try {
      await _initToken();
    } catch (e) {
      developer.log('checkExistingPermission error: $e', name: 'push');
    }
  }

  /// Upserts this device's token against the signed-in user.
  ///
  /// Safe to call at any time: a no-op when signed out or when the token isn't
  /// available yet, and it re-runs on the next sign-in.
  Future<void> registerToken() async {
    if (_token == null) {
      try {
        _token = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        developer.log('fetch FCM token failed in registerToken: $e', name: 'push');
      }
    }
    final token = _token;
    if (token == null) {
      developer.log('register skipped: no token', name: 'push');
      return;
    }

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      developer.log('register skipped: signed out', name: 'push');
      return;
    }

    try {
      await Supabase.instance.client.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': _platformName,
      });
      developer.log('token registered for user=$uid', name: 'push');
    } catch (e) {
      developer.log('rpc failed, trying direct upsert: $e', name: 'push');
      try {
        await Supabase.instance.client.from('device_tokens').upsert({
          'token': token,
          'auth_user_id': uid,
          'platform': _platformName,
          'updated_at': DateTime.now().toIso8601String(),
        });
        developer.log('token registered via direct upsert for user=$uid', name: 'push');
      } catch (directErr) {
        developer.log('direct upsert failed: $directErr', name: 'push');
      }
    }
  }

  /// Deletes this device's token.
  ///
  /// MUST be awaited **before** `supabase.auth.signOut()`, not after: the
  /// delete is gated by an RLS policy on `auth.uid()`, so once the session is
  /// gone the row can no longer be removed and this device would keep receiving
  /// the previous account's reminders.
  Future<void> unregisterToken() async {
    final token = _token;
    if (token == null) return;
    try {
      await Supabase.instance.client
          .from(_table)
          .delete()
          .eq('token', token)
          .timeout(const Duration(seconds: 3));
      developer.log('token unregistered', name: 'push');
    } catch (e) {
      developer.log('unregister failed: $e', name: 'push');
    }
  }

  // ---------------------------------------------------------------------------
  // Incoming messages
  // ---------------------------------------------------------------------------

  /// A message that arrived while the app is on screen. Android shows nothing
  /// for these, so it is re-displayed locally and the in-app feed refreshed.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    developer.log('foreground message ${message.messageId}', name: 'push');

    final outboxId = message.data['outbox_id'] as String?;
    final alreadyShown = outboxId != null &&
        outboxId.isNotEmpty &&
        !_shownOutboxIds.add(outboxId);

    final notification = message.notification;
    if (notification != null && !alreadyShown) {
      await _local.show(
        // A stable id per reminder, so a re-send REPLACES the banner instead of
        // stacking a second identical one.
        id: reminderNotificationId(message.data, message.messageId),
        title: notification.title,
        body: notification.body,
        notificationDetails: reminderDetails,
        payload: jsonEncode(message.data),
      );
    } else if (isDueReminderMessage(message.data)) {
      // Data-only "reminder is due now" push. Shown under the SAME id the local
      // exact-time schedule used, so a device that already rang gets the banner
      // refreshed, never a second copy.
      await showDueReminder(_local, message.data);
    }

    final kind = (message.data['kind'] as String?) ?? '';
    final vaultDocId = message.data['vault_doc_id']?.toString() ?? '';
    if (vaultDocId.isNotEmpty) _notifiedDocIds.add(vaultDocId);
    if (kind.startsWith('vault.') &&
        notification != null &&
        !alreadyShown &&
        AppSettings.instance.notifications.value) {
      _showInAppVaultBanner(
        title: notification.title ?? 'Family Vault',
        body: notification.body ?? '',
        data: message.data,
      );
    }
    if (kind == 'vault.invite') {
      unawaited(FamilyVaultStore.instance.refreshPendingInvitations());
    } else if (kind == 'vault.document_shared') {
      unawaited(FamilyVaultStore.instance.reload());
    }

    await refreshFeed();
  }

  /// True for the per-minute server push that says "this reminder is due".
  static bool isDueReminderMessage(Map<String, dynamic> data) =>
      data['kind'] == 'reminder.due' &&
      ((data['reminder_id'] as String?) ?? '').isNotEmpty;

  /// The notification id for a reminder message - the same value
  /// `ReminderScheduler.idFor` produces for the local schedule.
  static int reminderNotificationId(
      Map<String, dynamic> data, String? fallback) {
    final rid = data['reminder_id'] as String?;
    if (rid != null && rid.isNotEmpty) return rid.hashCode & 0x7fffffff;
    final oid = data['outbox_id'] as String?;
    if (oid != null && oid.isNotEmpty) return oid.hashCode & 0x7fffffff;
    return (fallback ?? '').hashCode & 0x7fffffff;
  }

  /// Displays a data-only due-reminder message through [plugin]. Static so the
  /// background isolate (which has none of this singleton's state) can reuse it.
  static Future<void> showDueReminder(
    FlutterLocalNotificationsPlugin plugin,
    Map<String, dynamic> data,
  ) async {
    await plugin.show(
      id: reminderNotificationId(data, null),
      title: (data['title'] as String?) ?? 'Reminder',
      body: (data['body'] as String?) ?? '',
      notificationDetails: reminderDetails,
      payload: jsonEncode(data),
    );
  }

  /// Immediately presents a reminder notification on this device.
  Future<void> showReminderNow(Reminder r) async {
    try {
      await localReady;
      final when = reminderDateTimeLabel(r.date);
      final body = r.subtitle.isEmpty ? when : '$when · ${r.subtitle}';
      await _local.show(
        id: reminderNotificationId({'reminder_id': r.id}, r.id),
        title: r.title,
        body: body,
        notificationDetails: reminderDetails,
        payload: jsonEncode({'reminder_id': r.id}),
      );
      developer.log('showReminderNow displayed ${r.id}', name: 'push');
    } catch (e) {
      developer.log('showReminderNow error: $e', name: 'push');
    }
  }

  /// Re-hydrates reminders and the in-app notification feed so the bell badge
  /// agrees with what the OS just showed.
  ///
  /// [NotificationCenter] is *derived* from live state rather than stored, so
  /// the reminders have to be reloaded first - refreshing the feed alone would
  /// regenerate it from the same stale [ReminderStore] cache.
  Future<void> refreshFeed() async {
    try {
      await ReminderStore.instance.reload();
      await NotificationCenter.instance.refresh();
    } catch (e) {
      developer.log('feed refresh failed: $e', name: 'push');
    }
  }

  void _onNotificationTapped(RemoteMessage message) {
    developer.log('tapped ${message.messageId} data=${message.data}',
        name: 'push');
    _route(message.data);
  }

  /// Sends a tapped notification to the screen it is about.
  ///
  /// Keyed on `data.kind`, which every sender sets (see the `send-push` Edge
  /// Function and `notification_outbox.kind`). Reminders predate `kind` and
  /// carry `reminder_id` instead, so their absence of a kind is the fallback
  /// rather than an error — an old notification sitting in the tray from before
  /// this shipped still routes correctly.
  void _route(Map<String, dynamic> data) {
    final kind = (data['kind'] as String?) ?? '';

    if (kind.startsWith('security.')) {
      _routeToScreen(const TrustedDevicesScreen());
      return;
    }
    if (kind == 'vault.document_shared') {
      final vaultId = data['vault_id'] as String?;
      if (vaultId != null && vaultId.isNotEmpty) {
        unawaited(_routeToVault(vaultId));
        return;
      }
    }
    // Every other family-vault event (invite, join request, approval, role
    // change) lands on the Family Vault home, which surfaces the pending cards.
    if (kind.startsWith('vault.')) {
      _routeToScreen(const FamilyVaultScreen());
      return;
    }
    if (kind == 'card.expiry') {
      _routeToWallet('Cards Wallet');
      return;
    }
    if (kind == 'doc.expiry') {
      _routeToWallet(data['wallet'] as String?);
      return;
    }
    _routeToReminder(data['reminder_id'] as String?);
  }

  /// Opens a Family Vault detail screen when the vault summary is available,
  /// otherwise opens the Family Vault hub.
  Future<void> _routeToVault(String vaultId) async {
    try {
      if (FamilyVaultStore.instance.vaults.isEmpty) {
        await FamilyVaultStore.instance.ensureLoaded();
      }
      for (final v in FamilyVaultStore.instance.vaults) {
        if (v.vault.id == vaultId) {
          await _routeToScreen(VaultDetailScreen(summary: v));
          return;
        }
      }
    } catch (e) {
      developer.log('routeToVault error: $e', name: 'push');
    }
    await _routeToScreen(const FamilyVaultScreen());
  }

  /// Opens a wallet by its canonical name, falling back to the notifications
  /// list when the name is unknown (a wallet renamed or deleted since the
  /// notification was sent).
  void _routeToWallet(String? walletName) {
    final category = walletName == null
        ? null
        : SupabaseWalletRepository.categoryFor(walletName);
    _routeToScreen(category == null
        ? const NotificationsScreen()
        : WalletDetailScreen(category: category));
  }

  /// Pushes [screen] once the navigator exists. Cold start hands us a tap
  /// before the tree is attached, so this waits the same bounded way
  /// [_routeToReminder] does rather than dropping the tap.
  Future<void> _routeToScreen(Widget screen, {int attempt = 0}) async {
    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      if (attempt >= 20) {
        developer.log('route: navigator never became ready', name: 'push');
        return;
      }
      Future.delayed(
        const Duration(milliseconds: 100),
        () => _routeToScreen(screen, attempt: attempt + 1),
      );
      return;
    }
    await nav.push(MaterialPageRoute(builder: (_) => screen));
  }

  // ---------------------------------------------------------------------------
  // Routing
  // ---------------------------------------------------------------------------

  /// Opens [reminderId]'s detail sheet, falling back to the full list when the
  /// id is absent or the reminder is no longer around (deleted, or completed on
  /// another device between the send and the tap).
  Future<void> _routeToReminder(String? reminderId, {int attempt = 0}) async {
    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      // Cold start: the navigator isn't attached for the first few frames.
      // Same bounded retry as DeepLinkService.
      if (attempt >= 20) {
        developer.log('route: navigator never became ready', name: 'push');
        return;
      }
      Future.delayed(
        const Duration(milliseconds: 100),
        () => _routeToReminder(reminderId, attempt: attempt + 1),
      );
      return;
    }

    await nav.push(
      MaterialPageRoute(builder: (_) => const AllRemindersScreen()),
    );

    if (reminderId == null) return;
    try {
      await ReminderStore.instance.ensureLoaded();
      final match = ReminderStore.instance.active
          .cast<Reminder?>()
          .firstWhere((r) => r?.id == reminderId, orElse: () => null);
      final context = nav.context;
      if (match != null && context.mounted) {
        await showReminderDetail(context, match);
      }
    } catch (e) {
      developer.log('route detail failed: $e', name: 'push');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String get _platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  /// Tokens are credentials - log only enough to correlate, never the value.
  static String _describeToken(String? t) =>
      t == null ? '(none)' : '${t.substring(0, 12)}…(${t.length})';

  @visibleForTesting
  void dispose() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _authSub?.cancel();
    _authSub = null;
    _foregroundSub?.cancel();
    _foregroundSub = null;
    _openedAppSub?.cancel();
    _openedAppSub = null;
    _stopOutboxRealtime();
    _shownOutboxIds.clear();
    _notifiedDocIds.clear();
    _vaultPermPrompted = false;
    _initialised = false;
  }
}

/// Handles a message that arrives while the app is **killed or backgrounded**.
///
/// Flutter runs this in a brand-new background isolate with none of the app's
/// state, so it must be a top-level (or static) function and must not reference
/// singletons from the UI isolate. `@pragma('vm:entry-point')` keeps it from
/// being tree-shaken out of release builds - without it, push works in debug
/// and mysteriously dies in release.
///
/// For a message with a `notification` payload there is nothing to do: the
/// system has already drawn the tray entry. A data-only "reminder.due" push is
/// the exception - the system draws nothing for those, so it is displayed here
/// through a plugin instance initialised inside this isolate. The in-app feed
/// is refreshed when the app next comes to the foreground.
@pragma('vm:entry-point')
Future<void> inoFirebaseBackgroundHandler(RemoteMessage message) async {
  developer.log('background message ${message.messageId}', name: 'push');
  if (message.notification != null ||
      !PushService.isDueReminderMessage(message.data)) {
    return;
  }
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    await PushService.showDueReminder(plugin, message.data);
  } catch (e) {
    developer.log('background reminder display failed: $e', name: 'push');
  }
}
