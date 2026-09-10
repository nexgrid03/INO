import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/services/account_security_service.dart';

void main() {
  group('Phone Normalization & Ownership Check Tests', () {
    final now = DateTime.now();

    group('Canonical Phone Normalization', () {
      test('CASE 1: 10-digit Indian number resolves to canonical E.164 (+91)', () {
        expect(
          AccountSecurityService.canonicalPhone('7702267621'),
          equals('+917702267621'),
        );
      });

      test('CASE 4: +91 prefixed number resolves to canonical E.164 (+91)', () {
        expect(
          AccountSecurityService.canonicalPhone('+917702267621'),
          equals('+917702267621'),
        );
      });

      test('CASE 5: 12-digit number starting with 91 resolves to canonical E.164 (+91)', () {
        expect(
          AccountSecurityService.canonicalPhone('917702267621'),
          equals('+917702267621'),
        );
      });

      test('Indian phone with spaces, dashes, and country code resolves to canonical', () {
        expect(
          AccountSecurityService.canonicalPhone('+91 77022-67621'),
          equals('+917702267621'),
        );
        expect(
          AccountSecurityService.canonicalPhone('+91 77022 67621'),
          equals('+917702267621'),
        );
      });

      test('Accidental double 91 prefix is safely normalized', () {
        expect(
          AccountSecurityService.canonicalPhone('+91917702267621'),
          equals('+917702267621'),
        );
      });

      test('International non-India numbers preserve valid E.164 format', () {
        expect(
          AccountSecurityService.canonicalPhone('+1 555 123 4567'),
          equals('+15551234567'),
        );
        expect(
          AccountSecurityService.canonicalPhone('+44 7911 123456'),
          equals('+447911123456'),
        );
      });

      test('Empty or blank input returns empty string', () {
        expect(AccountSecurityService.canonicalPhone(''), equals(''));
        expect(AccountSecurityService.canonicalPhone('   '), equals(''));
      });
    });

    group('Account-Aware Ownership Rules', () {
      test('CASE 3: Current account itself already owns +917702267621 on profile - recognized as own phone', () {
        final profile = UserProfile(
          id: 'usr_owner',
          authUserId: 'auth_owner',
          fullName: 'Owner User',
          email: 'owner@example.com',
          phone: '+917702267621',
          preferredLanguage: 'en',
          biometricEnabled: false,
          createdAt: now,
          updatedAt: now,
        );

        // Different formats of the same phone on the current profile must all match canonical
        final canonicalTarget = AccountSecurityService.canonicalPhone('7702267621');
        final profileCanonical = AccountSecurityService.canonicalPhone(profile.phone!);
        expect(canonicalTarget, equals(profileCanonical));
        expect(canonicalTarget, equals('+917702267621'));
      });

      test('CASE 3 (alternate format): Profile stores 10-digit number without +91 - recognized as own phone', () {
        final profile = UserProfile(
          id: 'usr_owner_raw',
          authUserId: 'auth_owner_raw',
          fullName: 'Owner Raw',
          email: 'owner_raw@example.com',
          phone: '7702267621',
          preferredLanguage: 'en',
          biometricEnabled: false,
          createdAt: now,
          updatedAt: now,
        );

        final canonicalTarget = AccountSecurityService.canonicalPhone('+917702267621');
        final profileCanonical = AccountSecurityService.canonicalPhone(profile.phone!);
        expect(canonicalTarget, equals(profileCanonical));
      });

      test('CASE 2: Profile belongs to another number - target is NOT recognized as own phone', () {
        final profile = UserProfile(
          id: 'usr_different',
          authUserId: 'auth_different',
          fullName: 'Different User',
          email: 'diff@example.com',
          phone: '+919999988888',
          preferredLanguage: 'en',
          biometricEnabled: false,
          createdAt: now,
          updatedAt: now,
        );

        final canonicalTarget = AccountSecurityService.canonicalPhone('7702267621');
        final profileCanonical = AccountSecurityService.canonicalPhone(profile.phone!);
        expect(canonicalTarget, isNot(equals(profileCanonical)));
      });

      test('CASE 1: Current account has null phone - target is not yet on profile', () {
        final profile = UserProfile(
          id: 'usr_no_phone',
          authUserId: 'auth_no_phone',
          fullName: 'No Phone User',
          email: 'nophone@example.com',
          phone: null,
          preferredLanguage: 'en',
          biometricEnabled: false,
          createdAt: now,
          updatedAt: now,
        );

        expect(profile.phone, isNull);
        final canonicalTarget = AccountSecurityService.canonicalPhone('7702267621');
        expect(canonicalTarget, equals('+917702267621'));
      });
    });
  });
}
