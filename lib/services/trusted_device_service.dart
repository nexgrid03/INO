import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/storage/shared_prefs_cache.dart';
import 'auth_service.dart';

/// A device session tracked on server and locally.
class TrustedDevice {
  const TrustedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.firstSeen,
    required this.lastActive,
    required this.isCurrent,
    this.sessionId,
    this.revoked = false,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime firstSeen;
  final DateTime lastActive;
  final bool isCurrent;
  final String? sessionId;
  final bool revoked;

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
        firstSeen: DateTime.fromMillisecondsSinceEpoch(
            (j['first_seen'] as num).toInt()),
        lastActive: DateTime.fromMillisecondsSinceEpoch(
            (j['last_active'] as num).toInt()),
        isCurrent: j['id'] == currentId,
      );

  factory TrustedDevice.fromSupabase(
          Map<String, dynamic> row, String currentId) =>
      TrustedDevice(
        id: row['device_id'] as String? ?? '',
        sessionId: row['id']?.toString(),
        name: row['device_name'] as String? ?? 'Unknown device',
        platform: row['platform'] as String? ?? '',
        firstSeen: row['created_at'] != null
            ? DateTime.parse(row['created_at'] as String).toLocal()
            : DateTime.now(),
        lastActive: row['last_seen'] != null
            ? DateTime.parse(row['last_seen'] as String).toLocal()
            : DateTime.now(),
        isCurrent: (row['device_id'] as String?) == currentId,
        revoked: row['revoked'] as bool? ?? false,
      );

  TrustedDevice copyWith({DateTime? lastActive, bool? revoked}) =>
      TrustedDevice(
        id: id,
        name: name,
        platform: platform,
        firstSeen: firstSeen,
        lastActive: lastActive ?? this.lastActive,
        isCurrent: isCurrent,
        sessionId: sessionId,
        revoked: revoked ?? this.revoked,
      );
}

/// Manages real server-backed device sessions and local persistence fallback.
class TrustedDeviceService {
  TrustedDeviceService._();
  static final TrustedDeviceService instance = TrustedDeviceService._();

  static const _kDevices = 'trusted_devices';
  static const _kCurrentId = 'trusted_device_current_id';
  static const _table = 'user_sessions';

  SupabaseClient get _client => Supabase.instance.client;

  /// Ensures the current device is registered and its `lastActive` is now.
  /// If the current device session was revoked on the server, triggers sign out.
  Future<void> registerCurrent() async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
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

      // Register session on Supabase backend if signed in
      final uid = _client.auth.currentUser?.id;
      if (uid != null) {
        final existing = await _client
            .from(_table)
            .select()
            .eq('user_id', uid)
            .eq('device_id', currentId)
            .maybeSingle();

        if (existing != null && (existing['revoked'] as bool? ?? false)) {
          developer.log('Current session was revoked remotely. Signing out.',
              name: 'devices');
          await AuthService.instance.signOut();
          return;
        }

        await _client.from(_table).upsert(
          {
            'user_id': uid,
            'device_id': currentId,
            'device_name': _deviceName(),
            'platform': _platform(),
            'last_seen': now.toUtc().toIso8601String(),
            'revoked': false,
          },
          onConflict: 'user_id,device_id',
        );
      }

      developer.log('registered current device $currentId', name: 'devices');
    } catch (e) {
      developer.log('registerCurrent failed: $e', name: 'devices');
    }
  }

  /// The active sessions from server, current one first.
  /// Falls back to local SharedPreferences if offline or signed out.
  Future<List<TrustedDevice>> list() async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final currentId = p.getString(_kCurrentId) ?? '';
      final uid = _client.auth.currentUser?.id;

      if (uid != null) {
        final rows = await _client
            .from(_table)
            .select()
            .eq('user_id', uid)
            .eq('revoked', false)
            .order('last_seen', ascending: false);

        if (rows.isNotEmpty) {
          final serverDevices = [
            for (final r in rows) TrustedDevice.fromSupabase(r, currentId)
          ];
          serverDevices.sort((a, b) {
            if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
            return b.lastActive.compareTo(a.lastActive);
          });
          return serverDevices;
        }
      }

      final devices = _decode(p.getString(_kDevices), currentId);
      devices.sort((a, b) {
        if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
        return b.lastActive.compareTo(a.lastActive);
      });
      return devices;
    } catch (e) {
      developer.log('list failed: $e', name: 'devices');
      final p = await SharedPrefsCache.instance.prefsAsync;
      final currentId = p.getString(_kCurrentId) ?? '';
      return _decode(p.getString(_kDevices), currentId);
    }
  }

  /// Revokes a device session on the server and local list.
  /// If [id] is current device, signs out.
  Future<bool> remove(String id) async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final currentId = p.getString(_kCurrentId) ?? '';
      final uid = _client.auth.currentUser?.id;

      if (uid != null) {
        await _client
            .from(_table)
            .update({'revoked': true})
            .eq('user_id', uid)
            .eq('device_id', id);
      }

      final devices = _decode(p.getString(_kDevices), currentId)
        ..removeWhere((d) => d.id == id);
      await _save(p, devices);

      if (id == currentId) {
        await AuthService.instance.signOut();
      }

      developer.log('revoked device session $id', name: 'devices');
      return true;
    } catch (e) {
      developer.log('remove session failed: $e', name: 'devices');
      return false;
    }
  }

  /// Revokes all sessions for current user except the current device.
  Future<bool> signOutOtherDevices() async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final currentId = await _ensureCurrentId(p);
      final uid = _client.auth.currentUser?.id;

      if (uid != null) {
        await _client
            .from(_table)
            .update({'revoked': true})
            .eq('user_id', uid)
            .neq('device_id', currentId);
      }

      final devices = _decode(p.getString(_kDevices), currentId)
        ..removeWhere((d) => d.id != currentId);
      await _save(p, devices);

      developer.log('signed out all other devices for user $uid', name: 'devices');
      return true;
    } catch (e) {
      developer.log('signOutOtherDevices failed: $e', name: 'devices');
      return false;
    }
  }

  Future<String> _ensureCurrentId(SharedPreferences p) async {
    var id = p.getString(_kCurrentId);
    if (id == null || id.isEmpty) {
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
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Device';
  }

  String _deviceName() {
    if (kIsWeb) return 'Web browser';
    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty) return '${_platform()} · $host';
    } catch (_) {}
    return '${_platform()} device';
  }
}
