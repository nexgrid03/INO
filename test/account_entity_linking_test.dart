import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/services/account_security_service.dart';

void main() {
  group('Account Entity Linking & Verification Status Tests', () {
    final now = DateTime.now();

    test('Identifies onlyPhoneVerified status when phone is present but email is empty/placeholder', () {
      final profile = UserProfile(
        id: 'usr_1',
        authUserId: 'auth_1',
        fullName: 'Test User',
        email: '',
        phone: '+919876543210',
        preferredLanguage: 'en',
        biometricEnabled: false,
        createdAt: now,
        updatedAt: now,
      );

      final status = AccountSecurityService.instance.getStatus(profile);
      expect(status, equals(AccountVerificationStatus.onlyPhoneVerified));
      expect(status.needsEmailVerification, isTrue);
      expect(status.needsPhoneVerification, isFalse);
      expect(status.isFullyVerified, isFalse);
    });

    test('Identifies onlyEmailVerified status when email is present but phone is missing', () {
      final profile = UserProfile(
        id: 'usr_2',
        authUserId: 'auth_2',
        fullName: 'Test User',
        email: 'test@example.com',
        phone: null,
        preferredLanguage: 'en',
        biometricEnabled: false,
        createdAt: now,
        updatedAt: now,
      );

      final status = AccountSecurityService.instance.getStatus(profile);
      expect(status, equals(AccountVerificationStatus.onlyEmailVerified));
      expect(status.needsEmailVerification, isFalse);
      expect(status.needsPhoneVerification, isTrue);
      expect(status.isFullyVerified, isFalse);
    });

    test('Identifies fullyVerified status when both email and phone are present', () {
      final profile = UserProfile(
        id: 'usr_3',
        authUserId: 'auth_3',
        fullName: 'Test User',
        email: 'test@example.com',
        phone: '+919876543210',
        preferredLanguage: 'en',
        biometricEnabled: false,
        createdAt: now,
        updatedAt: now,
      );

      final status = AccountSecurityService.instance.getStatus(profile);
      expect(status, equals(AccountVerificationStatus.fullyVerified));
      expect(status.needsEmailVerification, isFalse);
      expect(status.needsPhoneVerification, isFalse);
      expect(status.isFullyVerified, isTrue);
    });
  });
}
