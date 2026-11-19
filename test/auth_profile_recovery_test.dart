import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/repositories/user_repository.dart';
import 'package:inoapp/screens/auth/auth_flow.dart';
import 'package:inoapp/screens/auth/complete_profile_screen.dart';
import 'package:inoapp/screens/splash/splash_screen.dart';
import 'package:inoapp/services/auth_service.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

UserProfile _profile(String authId, String email) {
  return UserProfile(
    id: 'row-$authId',
    authUserId: authId,
    fullName: 'Test',
    email: email,
    preferredLanguage: 'en',
    biometricEnabled: false,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  test('signed-in launch with a confirmed missing profile finishes setup', () {
    expect(
      signedInProfileRoute(
        hasSession: true,
        hasProfile: false,
        lookupFailed: false,
        confirmedMissing: true,
      ),
      SignedInProfileRoute.finishProfile,
    );
  });

  test('a failed profile lookup is a retry, not a missing profile', () {
    expect(
      signedInProfileRoute(
        hasSession: true,
        hasProfile: false,
        lookupFailed: true,
        confirmedMissing: false,
      ),
      SignedInProfileRoute.retry,
    );
    expect(
      signedInProfileRoute(
        hasSession: true,
        hasProfile: false,
        lookupFailed: true,
        confirmedMissing: true,
      ),
      SignedInProfileRoute.retry,
    );
  });

  test('no session and an existing profile keep their current routes', () {
    expect(
      signedInProfileRoute(
        hasSession: false,
        hasProfile: false,
        lookupFailed: false,
        confirmedMissing: false,
      ),
      SignedInProfileRoute.proceed,
    );
    expect(
      signedInProfileRoute(
        hasSession: true,
        hasProfile: true,
        lookupFailed: false,
        confirmedMissing: false,
      ),
      SignedInProfileRoute.proceed,
    );
  });

  test('23505 is the only unique-violation code treated as a duplicate row', () {
    expect(
      isUsersUniqueViolation(
        const PostgrestException(message: 'duplicate key', code: '23505'),
      ),
      isTrue,
    );
    expect(
      isUsersUniqueViolation(
        const PostgrestException(message: 'permission denied', code: '42501'),
      ),
      isFalse,
    );
    expect(isUsersUniqueViolation(Exception('23505')), isFalse);
  });

  test('a failed profile insert after both verifications does not finish signup', () {
    final login = File('lib/screens/auth/login_screen.dart').readAsStringSync();
    final flow = File('lib/services/signup_identity_flow.dart').readAsStringSync();

    final firstOtp = login.substring(
      login.indexOf('void _goToNewUserOtpScreen'),
      login.indexOf('DualSignupCoordinator _signupCoordinator'),
    );
    expect(firstOtp.contains('if (user == null) return false'), isTrue);
    expect(firstOtp.contains('_startSecondIdentifier('), isTrue);
    expect(firstOtp.contains('createProfile('), isFalse);
    expect(firstOtp.contains('goToShell'), isFalse);
    expect(firstOtp.contains('signOut'), isFalse);
    expect(firstOtp.contains('.signUp'), isFalse);
    expect(firstOtp.contains('signInWithOtp'), isFalse);

    final coordinator = login.substring(
      login.indexOf('DualSignupCoordinator _signupCoordinator'),
      login.indexOf('Future<void> _startSecondIdentifier'),
    );
    expect(coordinator.contains('linkPhone:'), isTrue);
    expect(coordinator.contains('linkEmail:'), isTrue);
    expect(coordinator.contains('_createSignupProfile('), isTrue);
    expect(coordinator.contains('.signUp'), isFalse);
    expect(coordinator.contains('signInWithOtp'), isFalse);
    expect(coordinator.contains('sendEmailOtp'), isFalse);
    expect(coordinator.contains('sendPhoneOtp'), isFalse);

    final second = login.substring(
      login.indexOf('Future<void> _startSecondIdentifier'),
      login.indexOf('static Future<void> _createSignupProfile'),
    );
    expect(second.contains('beginSecond('), isTrue);
    expect(second.contains('flow.resend('), isTrue);
    expect(second.contains('onSignOut: signOutPendingSignup'), isTrue);
    expect(second.contains('sendEmailOtp'), isFalse);
    expect(second.contains('sendPhoneOtp'), isFalse);
    expect(second.contains('.signUp'), isFalse);
    expect(second.contains('signInWithOtp'), isFalse);
    final verify = second.substring(
      second.indexOf('onVerify:'),
      second.indexOf('onVerified:'),
    );
    expect(verify.contains('confirmSecond('), isTrue);
    expect(verify.contains('if (!ok)'), isTrue);
    expect(verify.contains('getProfileByAuthId('), isTrue);
    expect(verify.contains('if (created == null)'), isTrue);
    expect(verify.contains("We couldn't save your profile"), isTrue);
    expect(verify.contains('signOut'), isFalse);
    expect(
      verify.indexOf('if (created == null)'),
      lessThan(verify.indexOf('return true')),
    );
    final verified = second.substring(second.indexOf('onVerified:'));
    expect(verified.contains('if (ready != null) goToShell'), isTrue);

    final profile = login.substring(
      login.indexOf('static Future<void> _createSignupProfile'),
      login.indexOf('Future<void> _handleExistingUserSignIn'),
    );
    expect(profile.contains('readFailed'), isTrue);
    expect(profile.contains('throw const AuthException(_profileSaveFailed)'), isTrue);
    expect(profile.contains('logAuthEvent('), isTrue);
    expect(profile.contains('error: e'), isFalse);
    expect(profile.contains('createProfile('), isTrue);
    expect(profile.contains('isUsersUniqueViolation'), isTrue);
    expect(profile.contains('getProfileByAuthId(authUserId)'), isTrue);
    expect(profile.contains('_recordSignupConsent()'), isTrue);
    expect(
      profile.indexOf('createProfile('),
      lessThan(profile.indexOf('_recordSignupConsent()')),
    );
    expect(profile.contains('signOut'), isFalse);
    expect(profile.contains('.signUp'), isFalse);
    expect(profile.contains('signInWithOtp'), isFalse);
    expect(profile.contains('sendEmailOtp'), isFalse);
    expect(profile.contains('sendPhoneOtp'), isFalse);
    expect(profile.contains('shouldCreateUser'), isFalse);

    final confirm = flow.substring(flow.indexOf('Future<bool> confirmSecond'));
    expect(
      confirm.contains('if (userId == null || userId != expectedUserId) return false'),
      isTrue,
    );
    expect(confirm.contains('catch'), isFalse);
    expect(
      confirm.indexOf('await createProfile('),
      lessThan(confirm.indexOf('return true')),
    );
    expect(flow.contains('.signUp'), isFalse);
    expect(flow.contains('signInWithOtp'), isFalse);
    expect(flow.contains('sendEmailOtp'), isFalse);
    expect(flow.contains('sendPhoneOtp'), isFalse);
  });

  test('existing login still refuses to create an account', () {
    final source = File('lib/screens/auth/login_screen.dart').readAsStringSync();
    final login = source.substring(source.indexOf('Future<void> _handleExistingUserSignIn'));
    expect(login.contains('shouldCreateUser: false'), isTrue);
    expect(login.contains('createProfile('), isFalse);
  });

  test('a lost insert response is success when the consent row is already there', () {
    expect(
      consentAuditAction(recorded: true, insertsAttempted: 1),
      ConsentAuditAction.done,
    );
    expect(
      consentAuditAction(recorded: true, insertsAttempted: 0),
      ConsentAuditAction.done,
    );
  });

  test('a failed consent lookup does not allow another insert', () {
    expect(
      consentAuditAction(recorded: null, insertsAttempted: 1),
      ConsentAuditAction.stop,
    );
    expect(
      consentAuditAction(recorded: null, insertsAttempted: 0),
      ConsentAuditAction.stop,
    );
  });

  test('a confirmed missing consent row allows one insert and one retry only', () {
    expect(
      consentAuditAction(recorded: false, insertsAttempted: 0),
      ConsentAuditAction.insert,
    );
    expect(
      consentAuditAction(recorded: false, insertsAttempted: 1),
      ConsentAuditAction.insert,
    );
    expect(
      consentAuditAction(recorded: false, insertsAttempted: 2),
      ConsentAuditAction.stop,
    );
  });

  test('auth logs keep an error code and drop an email or phone', () {
    expect(authEventLine('signup profile insert failed', code: '23505'),
        'signup profile insert failed code=23505');
    expect(
      authEventLine('signup profile insert failed', code: 'ada@example.com'),
      'signup profile insert failed',
    );
    expect(
      authEventLine('consent insert failed', code: '+919876543210'),
      'consent insert failed',
    );
    expect(authEventLine('terms consent not confirmed').contains('@'), isFalse);
  });

  test('recovery logs do not pass raw exception objects', () {
    final login = File('lib/screens/auth/login_screen.dart').readAsStringSync();
    final complete =
        File('lib/screens/auth/complete_profile_screen.dart').readAsStringSync();
    final splash = File('lib/screens/splash/splash_screen.dart').readAsStringSync();
    for (final source in [login, complete, splash]) {
      expect(source.contains('error: e'), isFalse);
      expect(source.contains('stackTrace:'), isFalse);
      expect(source.contains("developer.log('"), isFalse);
    }
  });

  test('a cached profile is not returned for a different account', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final repo = UserRepository.instance;
    repo.clearCache();
    final ada = _profile('auth-ada', 'ada@example.com');
    final grace = _profile('auth-grace', 'grace@example.com');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${UserRepository.profileCachePrefix}_auth-ada',
      jsonEncode(ada.toMap()),
    );
    await prefs.setString(
      '${UserRepository.profileCachePrefix}_auth-grace',
      jsonEncode(grace.toMap()),
    );

    final loadedAda = await repo.getCachedProfile('auth-ada');
    final loadedGrace = await repo.getCachedProfile('auth-grace');
    expect(loadedAda?.authUserId, 'auth-ada');
    expect(loadedAda?.email, 'ada@example.com');
    expect(loadedGrace?.authUserId, 'auth-grace');
    expect(loadedGrace?.email, 'grace@example.com');

    await repo.forgetCachedProfile('auth-ada');
    expect(await repo.getCachedProfile('auth-ada'), isNull);
    expect((await repo.getCachedProfile('auth-grace'))?.authUserId, 'auth-grace');
  });

  test('a cache entry whose id does not match its key is discarded', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final repo = UserRepository.instance;
    repo.clearCache();
    final ada = _profile('auth-ada', 'ada@example.com');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${UserRepository.profileCachePrefix}_auth-grace',
      jsonEncode(ada.toMap()),
    );
    expect(await repo.getCachedProfile('auth-grace'), isNull);
    expect(prefs.getString('${UserRepository.profileCachePrefix}_auth-grace'), isNull);
  });

  testWidgets('Complete Profile shows a friendly notice without raw database text',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const notice =
        "We couldn't save your profile. Your sign-in is saved. Please try again.";
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const CompleteProfileScreen(
        authUserId: 'auth-1',
        fullName: 'Ada Lovelace',
        email: 'ada@example.com',
        phone: '+919876543210',
        notice: notice,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(notice), findsOneWidget);
    expect(find.textContaining('23505'), findsNothing);
    expect(find.textContaining('Postgrest'), findsNothing);
  });
}
