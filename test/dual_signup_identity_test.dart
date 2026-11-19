import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/screens/auth/otp_verification_screen.dart';
import 'package:inoapp/services/signup_identity_flow.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('email-first signup links the phone and saves one profile', () async {
    final harness = _Harness();
    final flow = harness.flow();
    final started = await flow.beginSecond(
      firstWasEmail: true,
      email: 'user@gmail.com',
      phone: '9876543210',
    );
    expect(started.blocked, isFalse);
    expect(started.target, '+919876543210');
    expect(harness.phoneLinks, ['+919876543210']);
    expect(harness.emailLinks, isEmpty);

    final ok = await flow.confirmSecond(
      expectedUserId: 'user-a',
      firstWasEmail: true,
      target: started.target!,
      code: '123456',
      fullName: 'User',
      email: 'user@gmail.com',
      phone: '9876543210',
    );
    expect(ok, isTrue);
    expect(harness.phoneVerifications, [('+919876543210', '123456')]);
    expect(harness.profiles.single.authUserId, 'user-a');
    expect(harness.profiles.single.phone, '+919876543210');
  });

  test('phone-first signup links the email on the same user', () async {
    final harness = _Harness();
    final flow = harness.flow();
    final started = await flow.beginSecond(
      firstWasEmail: false,
      email: 'user@gmail.com',
      phone: '+91 98765 43210',
    );
    expect(started.target, 'user@gmail.com');
    expect(harness.emailLinks, ['user@gmail.com']);
    expect(harness.phoneLinks, isEmpty);

    final ok = await flow.confirmSecond(
      expectedUserId: 'user-a',
      firstWasEmail: false,
      target: started.target!,
      code: '654321',
      fullName: 'User',
      email: 'user@gmail.com',
      phone: '+91 98765 43210',
    );
    expect(ok, isTrue);
    expect(harness.profiles.single.authUserId, 'user-a');
    expect(harness.profiles.single.email, 'user@gmail.com');
  });

  test('a different user id from the second code does not create a profile',
      () async {
    final harness = _Harness()..verifiedUserId = 'user-b';
    final flow = harness.flow();
    final ok = await flow.confirmSecond(
      expectedUserId: 'user-a',
      firstWasEmail: true,
      target: '+919876543210',
      code: '123456',
      fullName: 'User',
      email: 'user@gmail.com',
      phone: '9876543210',
    );
    expect(ok, isFalse);
    expect(harness.profiles, isEmpty);
  });

  test('a confirmed duplicate blocks linking', () async {
    final harness = _Harness()..taken = true;
    final started = await harness.flow().beginSecond(
          firstWasEmail: true,
          email: 'user@gmail.com',
          phone: '9876543210',
        );
    expect(started.blocked, isTrue);
    expect(harness.phoneLinks, isEmpty);
    expect(harness.emailLinks, isEmpty);
    expect(harness.profiles, isEmpty);
  });

  test('resend uses the link call and does not sign anyone else up', () async {
    final harness = _Harness();
    await harness.flow().resend(
          firstWasEmail: true,
          target: '+919876543210',
        );
    expect(harness.phoneLinks, ['+919876543210']);
    expect(harness.signUpCalls, 0);
  });

  test('duplicate resend shows the existing-account error and does not link',
      () async {
    final harness = _Harness()..taken = true;
    await expectLater(
      harness.flow().resend(
            firstWasEmail: true,
            target: '+919876543210',
          ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          contains('already on another INO account'),
        ),
      ),
    );
    expect(harness.phoneLinks, isEmpty);
    expect(harness.signUpCalls, 0);
  });

  test('a confirmed phone cannot be replaced by a different number', () {
    expect(
      profilePhoneToSave(
        confirmedPhone: '+919876543210',
        typedPhone: '+919876543210',
      ),
      '+919876543210',
    );
    expect(
      profilePhoneToSave(
        confirmedPhone: '+919876543210',
        typedPhone: '9999999999',
      ),
      isNull,
    );
  });

  test('a finished or single-identifier session does not resume signup', () {
    expect(
      secondFactorStillNeeded(
        emailConfirmed: true,
        phoneConfirmed: false,
        email: 'user@gmail.com',
        phone: '+919876543210',
      ),
      isTrue,
    );
    expect(
      secondFactorStillNeeded(
        emailConfirmed: true,
        phoneConfirmed: true,
        email: 'user@gmail.com',
        phone: '+919876543210',
      ),
      isFalse,
    );
    expect(
      secondFactorStillNeeded(
        emailConfirmed: true,
        phoneConfirmed: false,
        email: 'user@gmail.com',
        phone: '',
      ),
      isFalse,
    );
  });

  testWidgets('pending second verification cannot navigate back and can sign out',
      (tester) async {
    var signedOut = false;
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          return TextButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OtpVerificationScreen(
                  destination: '+919876543210',
                  showBack: false,
                  onSignOut: (otpContext) async {
                    signedOut = true;
                    Navigator.of(otpContext).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const Text('signed-out'),
                      ),
                      (route) => false,
                    );
                  },
                  onVerify: (_) async => false,
                  onVerified: (_) {},
                ),
              ));
            },
            child: const Text('open'),
          );
        },
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Change Mobile Number'), findsNothing);
    final route = ModalRoute.of(tester.element(find.text('Sign out')));
    expect(route?.popDisposition, RoutePopDisposition.doNotPop);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(route?.isCurrent, isTrue);
    expect(find.text('open').hitTestable(), findsNothing);
    expect(find.text('Sign out').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(signedOut, isTrue);
    expect(find.text('signed-out'), findsOneWidget);
  });

  test('resume uses the link API and does not start another signup', () {
    final source = File('lib/screens/auth/login_screen.dart').readAsStringSync();
    final pending = source.substring(
      source.indexOf('class PendingSecondVerificationScreen'),
      source.indexOf('class LoginScreen'),
    );
    expect(pending.contains('beginSecond('), isTrue);
    expect(pending.contains('showBack: false'), isTrue);
    expect(pending.contains('signInWithOtp'), isFalse);
    expect(pending.contains('.signUp'), isFalse);
  });

  test('profile recovery keeps the confirmed email and phone', () {
    final source =
        File('lib/screens/auth/complete_profile_screen.dart').readAsStringSync();
    expect(source.contains('profilePhoneToSave'), isTrue);
    expect(source.contains('confirmedEmail'), isTrue);
    expect(source.contains('_phoneLocked'), isTrue);
    final updateStart = source.indexOf('instance.updateProfile(');
    final update = source.substring(
      updateStart,
      source.indexOf(');', updateStart),
    );
    expect(update.contains('phone'), isFalse);
  });

  test('existing login still refuses to create an account', () {
    final source = File('lib/screens/auth/login_screen.dart').readAsStringSync();
    final login = source.substring(
      source.indexOf('Future<void> _handleExistingUserSignIn'),
    );
    expect(login.contains('shouldCreateUser: false'), isTrue);
    expect(login.contains('createProfile('), isFalse);
    expect(login.contains('linkPhone'), isFalse);
    expect(login.contains('linkEmail'), isFalse);
  });
}

class _SavedProfile {
  _SavedProfile(this.authUserId, this.email, this.phone);
  final String authUserId;
  final String email;
  final String phone;
}

class _Harness {
  String verifiedUserId = 'user-a';
  bool taken = false;
  int signUpCalls = 0;
  final phoneLinks = <String>[];
  final emailLinks = <String>[];
  final phoneVerifications = <(String, String)>[];
  final emailVerifications = <(String, String)>[];
  final profiles = <_SavedProfile>[];

  DualSignupCoordinator flow() {
    return DualSignupCoordinator(
      identifierTaken: (id) async => taken,
      linkPhone: (phone) async => phoneLinks.add(phone),
      linkEmail: (email) async => emailLinks.add(email),
      verifyPhoneUserId: (phone, code) async {
        phoneVerifications.add((phone, code));
        return verifiedUserId;
      },
      verifyEmailUserId: (email, code) async {
        emailVerifications.add((email, code));
        return verifiedUserId;
      },
      createProfile: ({
        required String authUserId,
        required String fullName,
        required String email,
        required String phone,
      }) async {
        profiles.add(_SavedProfile(authUserId, email, phone));
      },
    );
  }
}
