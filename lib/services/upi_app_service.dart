import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show Uint8List, debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// One installed payment app the user can pay a scanned QR with.
class UpiApp {
  const UpiApp({required this.id, required this.name, this.icon});

  /// Android: the package name (`com.phonepe.app`). iOS: the URL scheme
  /// (`phonepe`). Opaque to the UI - it is only ever handed back to
  /// [UpiAppService.pay].
  final String id;

  /// The app's own display label, as the OS reports it.
  final String name;

  /// The app's launcher icon as PNG bytes. Android only - iOS does not expose
  /// another app's icon, so the picker falls back to a lettered avatar.
  final Uint8List? icon;

  @override
  String toString() => 'UpiApp($id, $name)';
}

/// Finds the UPI apps installed on this device and hands a scanned payment QR
/// to whichever one the user picks.
///
/// **Android** is the real path. The OS is asked which activities can handle a
/// `upi://pay` VIEW intent, so the list is exactly the user's installed UPI
/// apps - Google Pay, PhonePe, Paytm, BHIM, Amazon Pay, CRED, whatever they
/// have - with their genuine labels and icons. Nothing is hard-coded, so an app
/// this code has never heard of still shows up. Launching sets the target
/// package explicitly, which is what makes "pay with *this* app" mean anything.
/// Android 11+ package visibility requires the matching `<queries>` entry in
/// AndroidManifest.xml.
///
/// **iOS** cannot enumerate installed apps. The best the platform allows is
/// probing a fixed list of URL schemes declared in `LSApplicationQueriesSchemes`,
/// so on iOS the list is limited to the apps named in Info.plist and carries no
/// icons.
///
/// If discovery returns nothing - an unsupported platform, a missing native
/// handler, no UPI app installed - [payWithSystemChooser] still hands the URI
/// to the OS, which shows its own chooser. The feature degrades, it never dead-ends.
class UpiAppService {
  UpiAppService._();
  static final UpiAppService instance = UpiAppService._();

  static const MethodChannel _channel = MethodChannel('ino/upi_apps');

  /// Cached across a session: the installed set does not change while the user
  /// is looking at a QR, and re-querying costs an icon decode per app.
  List<UpiApp>? _cache;

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The apps to float to the top of the picker when they are installed. Purely
  /// cosmetic ordering - everything installed is always listed, and anything not
  /// named here follows in the OS's own order.
  static const List<String> _preferred = [
    'com.google.android.apps.nbu.paisa.user', // Google Pay
    'com.phonepe.app', // PhonePe
    'net.one97.paytm', // Paytm
    'in.org.npci.upiapp', // BHIM
    'in.amazon.mShop.android.shopping', // Amazon Pay
    'com.dreamplug.androidapp', // CRED
    'com.whatsapp', // WhatsApp Pay
    // iOS scheme ids, same intent.
    'gpay', 'tez', 'phonepe', 'paytmmp', 'bhim',
  ];

  /// The UPI apps installed on this device, preferred ones first.
  ///
  /// Never throws: any platform failure yields an empty list, and the caller
  /// falls back to [payWithSystemChooser].
  Future<List<UpiApp>> installedApps({bool refresh = false}) async {
    if (!refresh && _cache != null) return _cache!;
    if (!_supported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('list');
      final apps = <UpiApp>[];
      for (final entry in raw ?? const []) {
        if (entry is! Map) continue;
        final id = entry['id']?.toString() ?? '';
        final name = entry['name']?.toString() ?? '';
        if (id.isEmpty || name.isEmpty) continue;
        final icon = entry['icon'];
        apps.add(UpiApp(
          id: id,
          name: name,
          icon: icon is Uint8List ? icon : null,
        ));
      }
      apps.sort((a, b) {
        final ia = _preferred.indexOf(a.id);
        final ib = _preferred.indexOf(b.id);
        // Unlisted apps (-1) sort after listed ones, then alphabetically.
        if (ia != ib) {
          if (ia == -1) return 1;
          if (ib == -1) return -1;
          return ia.compareTo(ib);
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (kDebugMode) {
        debugPrint('[QR] found ${apps.length} UPI app(s): '
            '${apps.map((a) => a.id).join(", ")}');
      }
      _cache = apps;
      return apps;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[QR] list failed: ${e.message}');
      return const [];
    } on MissingPluginException {
      // No native handler (e.g. a widget test) - not an error.
      return const [];
    }
  }

  /// Opens [upiUri] in [app] specifically. Returns false if that app could not
  /// be started, so the caller can fall back rather than fail silently.
  Future<bool> pay(UpiApp app, String upiUri) async {
    if (!_supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('launch', {
        'id': app.id,
        'uri': upiUri,
      });
      if (kDebugMode) debugPrint('[QR] launch ${app.id} → $ok');
      return ok ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[QR] launch failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Hands [upiUri] to the OS without naming an app, letting the system show its
  /// own chooser. The fallback when discovery found nothing or a targeted
  /// launch failed.
  Future<bool> payWithSystemChooser(String upiUri) async {
    final uri = Uri.tryParse(upiUri);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (kDebugMode) debugPrint('[QR] system chooser failed: $e');
      return false;
    }
  }

  /// Forgets the cached app list (used when the user returns from installing
  /// one).
  void invalidate() => _cache = null;
}
