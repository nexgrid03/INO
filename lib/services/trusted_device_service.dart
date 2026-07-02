import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// A device that has signed in on this install.
class TrustedDevice {
  const TrustedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.firstSeen,
    required this.lastActive,
    required this.isCurrent,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime firstSeen;
  final DateTime lastActive;
  final bool isCurrent;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'first_seen': firstSeen.millisecondsSinceEpoch,
        'last_active': lastActive.millisecondsSinceEpoch,
      };

  factory TrustedDevice.fromJson(Map<String, dynamic> j, String currentId) =>
      TrustedDevice(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Unknown device',
        platform: j['platform'] as String? ?? '',
        firstSeen:
            DateTime.fromMillisecondsSinceEpoch((j['first_seen'] as num).toInt()),
        lastActive: DateTime.fromMillisecondsSinceEpoch(
            (j['last_active'] as num).toInt()),
        isCurrent: j['id'] == currentId,
      );

  TrustedDevice copyWith({DateTime? lastActive}) => TrustedDevice(
        id: id,
        name: name,
        platform: platform,
        firstSeen: firstSeen,
        lastActive: lastActive ?? this.lastActive,
        isCurrent: isCurrent,
      );
}

/// Tracks the devices that have used this app, persisted locally.
///
/// On each launch [registerCurrent] records/refreshes *this* device (a stable
/// generated id + a human name derived from the OS). Without a backend sessions
/// table this is necessarily local — so it faithfully lists the devices this
/// install knows about, marks the current one, and lets the user forget the
/// others. The current device can't be removed from here (that's what Logout is
/// for).
class TrustedDeviceService {
  TrustedDeviceService._();
  static final TrustedDeviceService instance = TrustedDeviceService._();

  static const _kDevices = 'trusted_devices';
  static const _kCurrentId = 'trusted_device_current_id';

  /// Ensures the current device is registered and its `lastActive` is now.
  Future<void> registerCurrent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final currentId = await _ensureCurrentId(p);
      final devices = _decode(p.getString(_kDevices), currentId);
      final now = DateTime.now();

      final idx = devices.indexWhere((d) => d.id == currentId);
      if (idx == -1) {
        devices.add(TrustedDevice(
          id: currentId,
          name: _deviceName(),
          platform: _platform(),
          firstSeen: now,
          lastActive: now,
          isCurrent: true,
        ));
      } else {
        devices[idx] = devices[idx].copyWith(lastActive: now);
      }
      await _save(p, devices);
      developer.log('registered current device $currentId', name: 'devices');
    } catch (e) {
      developer.log('registerCurrent failed: $e', name: 'devices');
    }
  }

  /// The known devices, current one first, then most-recently-active.
  Future<List<TrustedDevice>> list() async {
    try {
      final p = await SharedPreferences.getInstance();
      final currentId = p.getString(_kCurrentId) ?? '';
      final devices = _decode(p.getString(_kDevices), currentId);
      devices.sort((a, b) {
        if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
        return b.lastActive.compareTo(a.lastActive);
      });
      return devices;
    } catch (e) {
      developer.log('list failed: $e', name: 'devices');
      return const [];
    }
  }

  /// Forgets a non-current device. Returns false if the id is the current one.
  Future<bool> remove(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final currentId = p.getString(_kCurrentId) ?? '';
      if (id == currentId) return false;
      final devices = _decode(p.getString(_kDevices), currentId)
        ..removeWhere((d) => d.id == id);
      await _save(p, devices);
      developer.log('removed device $id', name: 'devices');
      return true;
    } catch (e) {
      developer.log('remove failed: $e', name: 'devices');
      return false;
    }
  }

  Future<String> _ensureCurrentId(SharedPreferences p) async {
    var id = p.getString(_kCurrentId);
    if (id == null || id.isEmpty) {
      // Stable per-install id (no randomness dependency): time + host hash.
      final seed = '${DateTime.now().microsecondsSinceEpoch}'
          '-${Platform.localHostname.hashCode & 0xffff}';
      id = 'dev_${seed.hashCode.toUnsigned(32).toRadixString(16)}';
      await p.setString(_kCurrentId, id);
    }
    return id;
  }

  List<TrustedDevice> _decode(String? raw, String currentId) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          TrustedDevice.fromJson(e as Map<String, dynamic>, currentId),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(SharedPreferences p, List<TrustedDevice> devices) =>
      p.setString(_kDevices, jsonEncode([for (final d in devices) d.toJson()]));

  String _platform() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Device';
  }

  String _deviceName() {
    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty) return '${_platform()} · $host';
    } catch (_) {}
    return '${_platform()} device';
  }
}
