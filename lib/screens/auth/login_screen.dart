import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/floating_particles.dart';
import '../../widgets/ino_logo.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/soft_glow.dart';
import '../home/home_screen.dart';

/// Premium login / sign-up screen.
///
/// Email + password only (Google removed). Toggling "Create account" reveals a
/// name field and switches the primary action to sign-up.
///
/// All motion is driven by ONE entrance [AnimationController] (staggered via
/// Intervals) plus one perpetual controller for the logo float + background
/// shapes — keeping it lightweight and smooth.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _busy = false;

  // --- Animation ------------------------------------------------------------
  late final AnimationController _entrance; // staggered page entry
  late final AnimationController _float; // perpetual logo bob + bg shapes

  late final Animation<double> _bgFade;
  late final Animation<Offset> _cardSlide;
  late final Animation<double> _cardFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _glow;
  late final Animation<double> _headingFade;
  late final Animation<Offset> _headingSlide;
  late final Animation<double> _subtitleFade;
  late final Animation<Offset> _subtitleSlide;
  late final Animation<double> _field1Fade;
  late final Animation<Offset> _field1Slide;
  late final Animation<double> _field2Fade;
  late final Animation<Offset> _field2Slide;
  late final Animation<double> _forgotFade;
  late final Animation<double> _buttonFade;
  late final Animation<Offset> _buttonSlide;
  late final Animation<double> _linkFade;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _bgFade = _fade(0.0, 0.20);
    _cardSlide = _slideUp(0.05, 0.35, 0.10);
    _cardFade = _fade(0.05, 0.30);
    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.08, 0.40, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = _fade(0.08, 0.30);
    // One gentle pulse that settles to a soft, steady glow.
    _glow = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.45)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 55,
      ),
    ]).animate(
      CurvedAnimation(parent: _entrance, curve: const Interval(0.15, 0.5)),
    );
    _headingFade = _fade(0.35, 0.52);
    _headingSlide = _slideUp(0.35, 0.52);
    _subtitleFade = _fade(0.45, 0.62);
    _subtitleSlide = _slideUp(0.45, 0.62);
    _field1Fade = _fade(0.55, 0.72);
    _field1Slide = _slideUp(0.55, 0.72);
    _field2Fade = _fade(0.63, 0.80);
    _field2Slide = _slideUp(0.63, 0.80);
    _forgotFade = _fade(0.78, 0.88);
    _buttonFade = _fade(0.80, 0.93);
    _buttonSlide = _slideUp(0.80, 0.93);
    _linkFade = _fade(0.90, 1.0);

    _entrance.forward();
  }

  Animation<double> _fade(double begin, double end,
      [Curve curve = Curves.easeIn]) {
    return CurvedAnimation(
      parent: _entrance,
      curve: Interval(begin, end, curve: curve),
    );
  }

  Animation<Offset> _slideUp(double begin, double end, [double dy = 0.25]) {
    return Tween<Offset>(begin: Offset(0, dy), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    _float.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Validation -----------------------------------------------------------
  String? _validateName(String? value) {
    if (!_isSignUp) return null;
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Please enter your name';
    if (name.length < 2) return 'Name is too short';
    return null;
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

  // --- Actions --------------------------------------------------------------
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

  void _goToHome(UserProfile profile) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
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
          fullName: _nameController.text.trim(),
        );
        final user = res.user;
        if (res.session != null && user != null) {
          final profile = await UserRepository.instance.createProfile(
            authUserId: user.id,
            fullName: _nameController.text.trim(),
            email: _emailController.text.trim(),
          );
          _goToHome(profile);
        } else {
          _showMessage(
            'Account created! Check your email to confirm, then sign in.',
            isError: false,
          );
          setState(() => _isSignUp = false);
        }
      } else {
        final res = await AuthService.instance.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
        final user = res.user;
        if (user == null) {
          _showMessage('Sign in failed. Please try again.');
          return;
        }
        final profile = await UserRepository.instance.ensureProfile(
          authUserId: user.id,
          fullName: (user.userMetadata?['full_name'] as String?) ?? 'INO User',
          email: user.email ?? _emailController.text.trim(),
        );
        _goToHome(profile);
      }
    } on AuthException catch (e) {
      _showMessage(e.message);
    } on PostgrestException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (_validateEmail(email) != null) {
      _showMessage('Enter your email above first, then tap Forgot password.');
      return;
    }
    try {
      await AuthService.instance.sendPasswordReset(email);
      _showMessage('Password reset link sent to $email.', isError: false);
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Could not send reset email. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Soft gradient background + floating shapes, both fading in.
          Positioned.fill(
            child: FadeTransition(
              opacity: _bgFade,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFE9F5FB), // faint blue tint
                      Color(0xFFEAF7F2), // faint green tint
                      AppColors.background,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: FadeTransition(
              opacity: _bgFade,
              child: FloatingParticles(animation: _float),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 56),
                  _buildLogo(),
                  const SizedBox(height: 40), // logo ↔ card
                  _buildCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    // Scale + fade in, soft glow behind, then a gentle perpetual float.
    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) {
        final bob = math.sin(2 * math.pi * _float.value) * 4;
        return Transform.translate(offset: Offset(0, bob), child: child);
      },
      child: FadeTransition(
        opacity: _logoFade,
        child: ScaleTransition(
          scale: _logoScale,
          child: SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Center(
                  child: OverflowBox(
                    maxWidth: 190,
                    maxHeight: 190,
                    child: SoftGlow(animation: _glow, size: 190),
                  ),
                ),
                const InoLogo(size: 88),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return SlideTransition(
      position: _cardSlide,
      child: FadeTransition(
        opacity: _cardFade,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome heading.
              SlideTransition(
                position: _headingSlide,
                child: FadeTransition(
                  opacity: _headingFade,
                  child: Text(
                    _isSignUp ? 'Create your account' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Subtitle.
              SlideTransition(
                position: _subtitleSlide,
                child: FadeTransition(
                  opacity: _subtitleFade,
                  child: Text(
                    _isSignUp
                        ? 'Sign up to start your secure digital vault'
                        : 'Sign in to access your secure digital vault',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32), // welcome ↔ fields

              // Inputs.
              Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: Column(
                    children: [
                      if (_isSignUp) ...[
                        _AuthField(
                          controller: _nameController,
                          label: 'Full name',
                          hint: 'Tanishq Sharma',
                          icon: Icons.person_outline_rounded,
                          keyboardType: TextInputType.name,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          validator: _validateName,
                        ),
                        const SizedBox(height: 16),
                      ],
                      FadeTransition(
                        opacity: _field1Fade,
                        child: SlideTransition(
                          position: _field1Slide,
                          child: _AuthField(
                            controller: _emailController,
                            label: 'Email address',
                            hint: 'you@example.com',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: _validateEmail,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FadeTransition(
                        opacity: _field2Fade,
                        child: SlideTransition(
                          position: _field2Slide,
                          child: _AuthField(
                            controller: _passwordController,
                            label: 'Password',
                            hint: '••••••••',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            validator: _validatePassword,
                            onSubmitted: (_) => _submitEmail(),
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
                      ),
                    ],
                  ),
                ),
              ),

              // Forgot password (sign-in only).
              if (!_isSignUp)
                FadeTransition(
                  opacity: _forgotFade,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : _forgotPassword,
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              SizedBox(height: _isSignUp ? 28 : 12), // fields ↔ button

              // Sign In button.
              SlideTransition(
                position: _buttonSlide,
                child: FadeTransition(
                  opacity: _buttonFade,
                  child: PressableScale(
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submitEmail,
                        style: ElevatedButton.styleFrom(
                          elevation: 6,
                          shadowColor:
                              AppColors.primaryGreen.withValues(alpha: 0.4),
                        ),
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
                  ),
                ),
              ),
              const SizedBox(height: 28), // button ↔ create account

              // Create account / sign in toggle.
              FadeTransition(
                opacity: _linkFade,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        _isSignUp
                            ? 'Already have an account?'
                            : "Don't have an account?",
                        style: const TextStyle(color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _isSignUp = !_isSignUp),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _isSignUp ? 'Sign in' : 'Create account',
                        style: const TextStyle(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A text field with a smooth focus glow (premium "active" feel) on top of the
/// theme's standard rounded, filled decoration.
class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;
  final Widget? suffix;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (_node.hasFocus != _focused) {
        setState(() => _focused = _node.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        // Subtle glow that appears while the field is focused/typing.
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.18),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _node,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        validator: widget.validator,
        onFieldSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: Icon(widget.icon),
          suffixIcon: widget.suffix,
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
            borderSide:
                const BorderSide(color: AppColors.primaryGreen, width: 1.6),
          ),
        ),
      ),
    );
  }
}
