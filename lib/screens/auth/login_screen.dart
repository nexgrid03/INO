import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ino_logo.dart';
import '../home/home_screen.dart';

/// Login / sign-up screen.
///
/// Options:
///   1. Email + password — toggle between Sign In and Create Account
///   2. Continue with Google (native account picker)
///
/// Phone-number + OTP is planned as the primary method later.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUp = false; // false = Sign In, true = Create Account
  bool _obscurePassword = true;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Please enter your email';
    final emailRegex = RegExp(r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$');
    if (!emailRegex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Please enter a password';
    if (password.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _submitEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    try {
      if (_isSignUp) {
        final res = await AuthService.instance.signUpWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
        // If email confirmation is on, there's no session yet.
        if (res.session == null) {
          _showMessage(
            'Account created! Check your email to confirm, then sign in.',
            isError: false,
          );
          setState(() => _isSignUp = false);
        } else {
          _goToHome();
        }
      } else {
        await AuthService.instance.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
        _goToHome();
      }
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _busy = true);
    try {
      final res = await AuthService.instance.signInWithGoogle();
      if (res == null) return; // user cancelled the picker
      _goToHome();
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              const Center(child: InoLogo(size: 88)),
              const SizedBox(height: 28),
              Text(
                _isSignUp ? 'Create your account' : 'Welcome to INO',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isSignUp
                    ? 'Sign up to start your secure digital vault'
                    : 'Sign in to access your secure digital vault',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 40),

              // Email + password form.
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: _validateEmail,
                      decoration: _fieldDecoration(
                        label: 'Email address',
                        hint: 'you@example.com',
                        icon: Icons.mail_outline_rounded,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      validator: _validatePassword,
                      onFieldSubmitted: (_) => _submitEmail(),
                      decoration: _fieldDecoration(
                        label: 'Password',
                        hint: '••••••••',
                        icon: Icons.lock_outline_rounded,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.textMuted,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Primary action.
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submitEmail,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isSignUp ? 'Create Account' : 'Sign In',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),
              const _OrDivider(),
              const SizedBox(height: 24),

              // Continue with Google.
              SizedBox(
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _continueWithGoogle,
                  icon: const _GoogleGlyph(),
                  label: const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    side: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Toggle between Sign In and Sign Up.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSignUp
                        ? 'Already have an account?'
                        : "Don't have an account?",
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp ? 'Sign in' : 'Sign up',
                      style: const TextStyle(
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Phone number login coming soon',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.6),
      ),
    );
  }
}

/// A horizontal "or" divider used between login methods.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final lineColor = Colors.grey.withValues(alpha: 0.3);
    return Row(
      children: [
        Expanded(child: Divider(color: lineColor)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
        Expanded(child: Divider(color: lineColor)),
      ],
    );
  }
}

/// A lightweight, asset-free Google "G" glyph for the sign-in button.
/// Replace with the official multicolour Google logo asset when available.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4285F4), // Google blue
        ),
      ),
    );
  }
}
