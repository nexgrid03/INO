import 'package:flutter/material.dart';
import 'login_screen.dart';

/// Screen 4 - Signup / Create Account.
///
/// Wraps the unified [LoginScreen] in Create Account mode (`AuthMode.signUp`),
/// delivering the modern OTP-based registration flow (Name, Email, Mobile, Email/SMS OTP).
class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen(initialMode: AuthMode.signUp);
  }
}
