/// A Dart representation of one row in the `public.users` table.
///
/// This is a "model" (a.k.a. entity/DTO): a type-safe object that mirrors the
/// database columns so the rest of the app works with `profile.fullName`
/// instead of untyped `map['full_name']`. Every future table (documents,
/// property, …) will get its own model just like this.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.authUserId,
    required this.fullName,
    required this.email,
    this.phone,
    this.profilePhoto,
    required this.preferredLanguage,
    required this.biometricEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id; // users.id (our own UUID)
  final String authUserId; // users.auth_user_id (links to auth.users.id)
  final String fullName;
  final String email;
  final String? phone;
  final String? profilePhoto;
  final String preferredLanguage;
  final bool biometricEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Builds a [UserProfile] from a row returned by Supabase (a `Map`).
  /// The keys are the exact column names from the database.
  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      authUserId: map['auth_user_id'] as String,
      fullName: map['full_name'] as String,
      email: map['email'] as String,
      phone: map['phone'] as String?,
      profilePhoto: map['profile_photo'] as String?,
      preferredLanguage: (map['preferred_language'] as String?) ?? 'en',
      biometricEnabled: (map['biometric_enabled'] as bool?) ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
