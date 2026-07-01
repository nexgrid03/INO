import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

/// The ONLY place in the app that reads/writes the `public.users` table.
///
/// Screens never query Supabase directly — they go through this repository.
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
        .single(); // expect exactly one row back
    return UserProfile.fromMap(row);
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
        .single();
    return UserProfile.fromMap(row);
  }

  /// Fetches a profile by its auth user id, or `null` if none exists yet.
  Future<UserProfile?> getProfileByAuthId(String authUserId) async {
    final row = await _client
        .from(_table)
        .select()
        .eq('auth_user_id', authUserId)
        .maybeSingle(); // returns null instead of throwing when no row
    return row == null ? null : UserProfile.fromMap(row);
  }

  /// Returns the existing profile, or creates one if it's missing.
  /// Handy for "Continue with Google" (Step 9), where there is no explicit
  /// sign-up moment — we just ensure a profile exists.
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
