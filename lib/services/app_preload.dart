import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data' show ByteData;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/dashboard_repository.dart';
import '../data/reminder_store.dart';
import '../data/wallet_repository.dart';
import '../models/document.dart';
import '../repositories/document_repository.dart';
import '../widgets/common/ino_svg_icon.dart';
import 'card_store.dart';
import 'category_store.dart';
import 'document_protection_store.dart';
import 'expense_store.dart';
import 'family_vault_store.dart';
import 'investment_store.dart';
import 'market_rates_service.dart';
import 'net_worth_service.dart';
import 'notes_store.dart';
import 'notification_center.dart';
import 'offline_document_store.dart';
import 'password_store.dart';
import 'property_store.dart';
import 'wallet_store.dart';

/// Loads the signed-in user's whole working set **while the splash is still
/// playing**, so the app is fully hydrated by the time the first screen
/// appears.
///
/// The problem this solves: every tab used to fetch its own data in
/// `initState`. The splash animated for ~1.7s doing nothing, the shell then
/// mounted, and only *then* did Home start asking Supabase for documents —
/// so the first thing after the brand intro was a skeleton, and the first
/// scroll of Home fought a run of image decodes. Wallet, Reminders and Profile
/// each repeated the pattern the first time you opened them.
///
/// Everything here happens in a window that was already being spent on an
/// animation, which is why it is effectively free:
///
///  * **Data.** Documents (the one real network round-trip), reminders, the
///    four device-local record stores, expenses, notes, family vaults,
///    categories and notification state — all warmed into the same singletons
///    the screens read from. Screens are unchanged: their `ensureLoaded()` /
///    `listAll()` calls simply return an already-warm cache.
///  * **Derived read models.** [walletHub] and [dashboard] are computed once
///    here so Home and the Wallet hub can paint fully-formed on their first
///    frame instead of showing a skeleton (see [seedWalletHub]).
///  * **Art.** The Home hero photos, the 3D tile icons and the launcher SVGs
///    are decoded up front. A PNG decoded on demand as its tile scrolls into
///    view is a dropped frame; decoded here it is already in the image cache.
///
/// Nothing here writes, nothing here throws, and nothing here is required:
/// [warmUp] is a best-effort accelerator. If it fails, or the splash gives up
/// waiting on it, every screen still loads exactly the way it always did.
class AppPreload {
  AppPreload._();
  static final AppPreload instance = AppPreload._();

  /// The longest the splash will hold for the warm-up.
  ///
  /// Balanced against a deliberately quick brand intro (800ms + a 180ms exit):
  /// a warm-up on a normal connection lands well inside this, so the shell
  /// opens populated at no visible cost. Past the cap we show the app anyway —
  /// a slow network must never turn into a stuck splash, and the work already
  /// in flight carries on and still lands in the caches, so the screens fill
  /// in behind their skeletons a moment later.
  static const Duration splashBudget = Duration(milliseconds: 2500);

  Future<void>? _inFlight;
  bool _done = false;

  /// True once a warm-up has finished (successfully or not). Screens use this
  /// only to decide whether a cached read model is trustworthy.
  bool get isReady => _done;

  // ── Cached read models ─────────────────────────────────────────────────────
  // null means "never warmed", which is what tells a screen to fall back to
  // its own load rather than paint an empty state.

  List<Document>? _documents;

  /// Every document the user owns, as of the warm-up.
  List<Document>? get documents => _documents;

  WalletHubData? _walletHub;

  /// The Wallet hub read model, ready to paint. Consumed once by
  /// [seedWalletHub] so a stale snapshot can never outlive the first frame.
  WalletHubData? get walletHub => _walletHub;

  DashboardData? _dashboard;
  DashboardData? get dashboard => _dashboard;

  /// Hands the warmed hub to the first screen that asks, then forgets it.
  ///
  /// Deliberately one-shot. The snapshot is only correct until the user adds
  /// or deletes something; letting a second mount re-seed from it would show
  /// stale wallet counts after an edit. Later mounts load normally.
  WalletHubData? seedWalletHub() {
    final hub = _walletHub;
    _walletHub = null;
    return hub;
  }

  /// Same one-shot contract as [seedWalletHub], for the document list.
  List<Document>? seedDocuments() {
    final docs = _documents;
    _documents = null;
    return docs;
  }

  // ── Warm-up ────────────────────────────────────────────────────────────────

  /// Fills every cache the shell reads from. Safe to call repeatedly — the
  /// first call owns the work and later callers await the same future.
  ///
  /// [context] is optional and used only to precache art; without one the data
  /// half still runs. Never throws.
  Future<void> warmUp({BuildContext? context}) async {
    if (_done) return;
    // A warm-up is already running (the splash started it, and the shell asked
    // again): join that one rather than starting a second.
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    // Captured before the first await: `context` belongs to the splash, which
    // may well be disposed by the time this resumes.
    final imageConfig =
        context == null ? null : createLocalImageConfiguration(context);
    final run = _run(imageConfig);
    _inFlight = run;
    try {
      await run;
    } finally {
      // Never keep a *completed* future here. `_done` is what later callers
      // read, and a future created in one zone never resolves for a caller in
      // another (which is exactly what each widget test is).
      _inFlight = null;
    }
  }

  Future<void> _run(ImageConfiguration? imageConfig) async {
    final watch = Stopwatch()..start();

    // Art doesn't depend on the session, so it starts immediately and runs
    // alongside the network work rather than after it.
    final art = imageConfig == null
        ? Future<void>.value()
        : _guard('art', () => _precacheArt(imageConfig));

    // Signed out (or a guest): there is no user data to warm. The art is still
    // worth waiting for — the login and onboarding screens paint faster too.
    if (_session == null) {
      await art;
      _done = true;
      return;
    }

    // Round 1 — everything that is independent of everything else. Documents
    // are the only real network call; the rest are shared_preferences reads
    // and RLS-scoped table fetches that can all fly at once.
    final docsFuture = _guard<List<Document>>(
      'documents',
      () => DocumentRepository.instance.listAll(),
      fallback: const <Document>[],
    );

    await Future.wait([
      docsFuture,
      _guard('reminders', () => ReminderStore.instance.ensureLoaded()),
      _guard('properties', () => PropertyStore.instance.ensureLoaded()),
      _guard('investments', () => InvestmentStore.instance.ensureLoaded()),
      _guard('cards', () => CardStore.instance.ensureLoaded()),
      _guard('passwords', () => PasswordStore.instance.ensureLoaded()),
      _guard('expenses', () => ExpenseStore.instance.ensureLoaded()),
      _guard('notes', () => NotesStore.instance.ensureLoaded()),
      _guard('familyVaults', () => FamilyVaultStore.instance.ensureLoaded()),
      _guard('offlineDocs', () => OfflineDocumentStore.instance.ensureLoaded()),
      _guard('categories', () => CategoryStore.instance.load()),
      _guard('customWallets', () => CustomWalletStore.instance.load()),
      _guard('protection', () => DocumentProtectionStore.instance.load()),
      _guard('notifications', () => NotificationCenter.instance.load()),
    ]);

    final docs = await docsFuture ?? const <Document>[];
    _documents = docs;

    // Round 2 — the derived read models, which need round 1 to have landed.
    // Net worth reads the investment + property stores; the wallet hub counts
    // documents per wallet and asks each data store for its record count.
    await Future.wait([
      _guard('netWorth', () => NetWorthService.instance.ensureReady()),
      _guard('walletHub', () async {
        _walletHub = await WalletRepository.instance.load(documents: docs);
      }),
      _guard('dashboard', () async {
        _dashboard = await DashboardRepository.instance.load();
      }),
      art,
    ]);

    // Market quotes are decorative on Home, go through a cache that already
    // has a fallback, and hit a third-party rates API. Fired and forgotten so
    // a slow provider can never hold the splash; Home picks the result up on
    // its own once it lands.
    unawaited(
      _guard('marketRates', () => MarketRatesService.instance.fetchLive()),
    );

    _done = true;
    developer.log(
      'warm-up finished in ${watch.elapsedMilliseconds}ms '
      '(${docs.length} documents)',
      name: 'preload',
    );
  }

  /// The signed-in session, or null.
  ///
  /// Guarded because `Supabase.instance` *asserts* when the client was never
  /// initialised — which is exactly the case in a widget test that pumps the
  /// app root without going through `main()`. A warm-up must degrade to
  /// "nothing to warm" there, not bring the whole first frame down.
  Session? get _session {
    try {
      return Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  /// Drops every cached read model. Called from [SessionReset] so the next
  /// account never inherits the previous one's warmed snapshot.
  void reset() {
    _inFlight = null;
    _done = false;
    _documents = null;
    _walletHub = null;
    _dashboard = null;
  }

  // ── Art ────────────────────────────────────────────────────────────────────

  /// Home's PNG art and launcher SVGs, decoded into their caches before the
  /// first tile is painted.
  Future<void> _precacheArt(ImageConfiguration config) async {
    const pngs = <String>[
      // Hero cards.
      'assets/home/hero_vault_clay.png',
      'assets/home/hero_digital_id.png',
      // Quick actions.
      InoHomeIcons3d.scan,
      InoHomeIcons3d.documents,
      InoHomeIcons3d.reminder,
      InoHomeIcons3d.voice,
      // My Vaults.
      InoHomeIcons3d.identity,
      InoHomeIcons3d.property,
      InoHomeIcons3d.investments,
      InoHomeIcons3d.cards,
      // Needs-attention strip.
      InoHomeIcons3d.attnExpiring,
      InoHomeIcons3d.attnEmi,
      InoHomeIcons3d.attnPending,
      InoHomeIcons3d.attnInsurance,
      // Finance tools.
      InoHomeIcons3d.finArea,
      InoHomeIcons3d.finEmi,
      InoHomeIcons3d.finSip,
      InoHomeIcons3d.finStamp,
      InoHomeIcons3d.finUnit,
      InoHomeIcons3d.finTax,
      // The brand mark, used by the splash and by every InoLoader.
      'assets/splash/splash_shield_blank.png',
    ];

    const svgs = <String>[
      InoHomeIcons.documents,
      InoHomeIcons.notes,
      InoHomeIcons.expenses,
      InoHomeIcons.scan,
      InoHomeIcons.offline,
      InoHomeIcons.reminder,
      InoHomeIcons.voice,
      InoHomeIcons.netWorth,
      InoHomeIcons.identity,
      InoHomeIcons.property,
      InoHomeIcons.investments,
      InoHomeIcons.cards,
      InoHomeIcons.area,
      InoHomeIcons.emi,
      InoHomeIcons.sip,
      InoHomeIcons.stamp,
      InoHomeIcons.unit,
      InoHomeIcons.tax,
    ];

    await Future.wait([
      for (final asset in pngs) _decodeOne(AssetImage(asset), config),
      // `loadBytes` populates flutter_svg's own cache, which is what
      // SvgPicture.asset consults on its first build.
      for (final asset in svgs)
        SvgAssetLoader(asset).loadBytes(null).catchError((Object _) {
          return ByteData(0);
        }),
    ]);
  }

  /// `precacheImage` without a [BuildContext] — the same mechanics, but usable
  /// from a service that outlives the widget that started it.
  ///
  /// Always completes: a missing or corrupt asset resolves normally, so one
  /// bad file cannot stall the rest of the warm-up.
  Future<void> _decodeOne(ImageProvider provider, ImageConfiguration config) {
    final completer = Completer<void>();
    final stream = provider.resolve(config);
    late final ImageStreamListener listener;

    void finish({bool deferRemoval = false}) {
      if (!completer.isCompleted) completer.complete();
      // On the success path the listener can fire synchronously from inside
      // addListener (the image was already decoded), so detach after the frame
      // — the same dance Flutter's own precacheImage does.
      if (deferRemoval) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => stream.removeListener(listener));
      } else {
        stream.removeListener(listener);
      }
    }

    listener = ImageStreamListener(
      // The image cache keeps its own reference; this listener only waits for
      // the decode to land.
      (_, _) => finish(deferRemoval: true),
      onError: (_, _) => finish(),
    );
    stream.addListener(listener);
    return completer.future;
  }

  // ── Plumbing ───────────────────────────────────────────────────────────────

  /// Runs [body], swallowing and logging any failure.
  ///
  /// One store failing (offline, a permissions hiccup, a corrupt cache) must
  /// never take the whole warm-up down with it — that would turn a degraded
  /// start into a cold one for every other screen.
  Future<T?> _guard<T>(
    String label,
    Future<T> Function() body, {
    T? fallback,
  }) async {
    try {
      return await body();
    } catch (e) {
      developer.log('warm-up step "$label" failed: $e', name: 'preload');
      return fallback;
    }
  }
}
