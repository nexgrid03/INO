import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';
import '../models/user_profile.dart';

/// The ONLY place in the app that reads/writes the `public.users` table.
///
/// Screens never query Supabase directly - they go through this repository.
/// That keeps database logic in one spot (easy to change, test, and reason
/// about) and is the pattern you'll copy for every future table.
class UserRepository {
  UserRepository._();
  static final UserRepository instance = UserRepository._();

  /// The Supabase client (created in main.dart at startup).
  SupabaseClient get _client => Supabase.instance.client;

  static const String _table = 'users';

  /// Inserts a new profile row and returns it.
  ///
  /// We only send the columns we own; the database fills the rest
  /// (`id`, `preferred_language`, `biometric_enabled`, timestamps) from the
  /// DEFAULTs we defined in the schema.
  ///
  /// RLS note: this only succeeds while the user is signed in, because the
  /// INSERT policy requires `auth.uid() = auth_user_id`.
  Future<UserProfile> createProfile({
    required String authUserId,
    required String fullName,
    required String email,
    String? phone,
  }) async {
    final row = await _client
        .from(_table)
        .insert({
          'auth_user_id': authUserId,
          'full_name': fullName,
          'email': email,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        })
        .select() // ask Supabase to return the inserted row
        .single() // expect exactly one row back
        .timeout(NetGuard.mutation);
    final profile = UserProfile.fromMap(row);
    await _cacheProfile(profile);
    return profile;
  }

  /// Updates the signed-in user's profile with the provided (non-null) fields
  /// and returns the fresh row. Used by the Complete Profile step to persist
  /// details Google sign-in can't supply (e.g. phone number).
  ///
  /// RLS note: succeeds only while signed in (UPDATE policy requires
  /// `auth.uid() = auth_user_id`).
  Future<UserProfile> updateProfile({
    required String authUserId,
    String? phone,
    String? fullName,
    String? preferredLanguage,
    String? profilePhoto,
    bool? biometricEnabled,
  }) async {
    final updates = <String, dynamic>{};
    if (phone != null) updates['phone'] = phone.trim();
    if (fullName != null) updates['full_name'] = fullName.trim();
    if (preferredLanguage != null) {
      updates['preferred_language'] = preferredLanguage;
    }
    if (profilePhoto != null) updates['profile_photo'] = profilePhoto;
    if (biometricEnabled != null) updates['biometric_enabled'] = biometricEnabled;
    final row = await _client
        .from(_table)
        .update(updates)
        .eq('auth_user_id', authUserId)
        .select()
        .single()
        .timeout(NetGuard.mutation);
    final profile = UserProfile.fromMap(row);
    await _cacheProfile(profile);
    return profile;
  }

  /// Fetches a profile by its auth user id, or `null` if none exists yet.
  Future<UserProfile?> getProfileByAuthId(String authUserId) async {
    final row = await _client
        .from(_table)
        .select()
        .eq('auth_user_id', authUserId)
        .maybeSingle() // returns null instead of throwing when no row
        .timeout(NetGuard.query);
    if (row == null) return null;
    final profile = UserProfile.fromMap(row);
    await _cacheProfile(profile);
    return profile;
  }

  // ---- On-device profile cache ---------------------------------------------
  //
  // Every successful fetch/create/update snapshots the profile locally, so a
  // signed-in user whose network is down can still boot into their shell (and
  // reach features that are deliberately offline, like Offline documents).

  static const String _cachePrefix = 'ino_profile_cache';
  UserProfile? _inMemoryProfile;

  Future<void> _cacheProfile(UserProfile profile) async {
    _inMemoryProfile = profile;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${_cachePrefix}_${profile.authUserId}',
        jsonEncode(profile.toMap()),
      );
    } catch (_) {
      // Best-effort: a failed cache write must never break a live fetch.
    }
  }

  /// The last profile this device fetched for [authUserId], or null when this
  /// account has never loaded here. Purely local - never touches the network.
  Future<UserProfile?> getCachedProfile(String authUserId) async {
    if (_inMemoryProfile != null && _inMemoryProfile!.authUserId == authUserId) {
      return _inMemoryProfile;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('${_cachePrefix}_$authUserId');
      if (raw == null) return null;
      final profile = UserProfile.fromMap(jsonDecode(raw) as Map<String, dynamic>);
      _inMemoryProfile = profile;
      return profile;
    } catch (_) {
      return null;
    }
  }

  /// Returns the existing profile, or creates one if it's missing.
  /// Handy for "Continue with Google" (Step 9), where there is no explicit
  /// sign-up moment - we just ensure a profile exists.
  Future<UserProfile> ensureProfile({
    required String authUserId,
    required String fullName,
    required String email,
  }) async {
    final existing = await getProfileByAuthId(authUserId);
    if (existing != null) return existing;
    return createProfile(
      authUserId: authUserId,
      fullName: fullName,
      email: email,
    );
  }
}
