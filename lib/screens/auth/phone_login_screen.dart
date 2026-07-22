import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, User;

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import 'auth_flow.dart';
import 'otp_verification_screen.dart';

/// A country dialling code option for the phone-login picker.
class _Country {
  const _Country(this.name, this.dialCode, this.flag);
  final String name;
  final String dialCode; // e.g. "+91"
  final String flag; // emoji
}

/// A compact list of common dialling codes (India first / default). Extend as
/// needed — the picker searches by name or code.
const List<_Country> _countries = [
  _Country('India', '+91', '🇮🇳'),
  _Country('United States', '+1', '🇺🇸'),
  _Country('United Kingdom', '+44', '🇬🇧'),
  _Country('United Arab Emirates', '+971', '🇦🇪'),
  _Country('Singapore', '+65', '🇸🇬'),
  _Country('Australia', '+61', '🇦🇺'),
  _Country('Canada', '+1', '🇨🇦'),
  _Country('Germany', '+49', '🇩🇪'),
  _Country('France', '+33', '🇫🇷'),
  _Country('Saudi Arabia', '+966', '🇸🇦'),
  _Country('Qatar', '+974', '🇶🇦'),
  _Country('Nepal', '+977', '🇳🇵'),
  _Country('Sri Lanka', '+94', '🇱🇰'),
  _Country('Bangladesh', '+880', '🇧🇩'),
  _Country('Malaysia', '+60', '🇲🇾'),
  _Country('South Africa', '+27', '🇿🇦'),
  _Country('New Zealand', '+64', '🇳🇿'),
  _Country('Japan', '+81', '🇯🇵'),
];

/// "Continue with Phone Number" — collects a country code + mobile number,
/// sends a Supabase SMS OTP, then hands off to the shared [OtpVerificationScreen].
///
/// This lives ALONGSIDE the untouched Google flow: on a successful verify it
/// routes through [routeAfterAuth], so a phone user enters the exact same
/// account/session/onboarding pipeline as every other sign-in method.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  _Country _country = _countries.first;
  bool _busy = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  /// National number digits only (strips spaces/dashes and any leading 0 / code).
  String get _nationalNumber =>
      _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');

  String get _e164 => '${_country.dialCode}$_nationalNumber';

  String? _validatePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Please enter your mobile number';
    if (digits.length < 6 || digits.length > 14) {
      return 'Enter a valid mobile number';
    }
    return null;
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.critical : AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _sendOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final phone = _e164;
    setState(() => _busy = true);
    try {
      await AuthService.instance.sendPhoneOtp(phone);
      if (!mounted) return;
      _goToOtp(phone);
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Could not send the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToOtp(String phone) {
    User? verifiedUser;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          title: 'Verify Your Number',
          destination: phone,
          onResend: () => AuthService.instance.sendPhoneOtp(phone),
          onVerify: (code) async {
            final res = await AuthService.instance
                .verifyPhoneOtp(phone: phone, token: code);
            verifiedUser = res.user;
            return verifiedUser != null;
          },
          onVerified: (ctx) {
            final user = verifiedUser;
            if (user == null) return;
            // Same landing as Google/email: profile lookup → Complete Profile
            // (first time) or Home.
            routeAfterAuth(
              authUserId: user.id,
              fullName: (user.userMetadata?['full_name'] as String?) ??
                  (user.userMetadata?['name'] as String?) ??
                  'INO User',
              email: user.email ?? '',
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<_Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CountryPickerSheet(),
    );
    if (picked != null) setState(() => _country = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBack: true,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            FadeSlideIn(child: const _PhoneBadge()),
            const SizedBox(height: 26),
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: const Text(
                'Sign in with Phone',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FadeSlideIn(
              delay: const Duration(milliseconds: 110),
              child: const Text(
                "We'll text you a 6-digit code to verify your number.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 34),
            FadeSlideIn(
              delay: const Duration(milliseconds: 160),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _CountrySelector(country: _country, onTap: _pickCountry),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AuthTextField(
                      controller: _phoneController,
                      label: 'Mobile number',
                      hint: '98765 43210',
                      icon: Icons.smartphone_rounded,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9 \-]')),
                      ],
                      validator: _validatePhone,
                      onSubmitted: (_) => _sendOtp(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            FadeSlideIn(
              delay: const Duration(milliseconds: 210),
              child: AuthPrimaryButton(
                label: 'Send OTP',
                busy: _busy,
                onPressed: _busy ? null : _sendOtp,
              ),
            ),
            const SizedBox(height: 20),
            FadeSlideIn(
              delay: const Duration(milliseconds: 250),
              child: const Text(
                'Standard SMS rates may apply.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// The gradient phone badge shown at the top of the phone-login screen.
class _PhoneBadge extends StatelessWidget {
  const _PhoneBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(Icons.smartphone_rounded, color: Colors.white, size: 38),
      ),
    );
  }
}

/// The tappable country-code box shown to the left of the number field.
class _CountrySelector extends StatelessWidget {
  const _CountrySelector({required this.country, required this.onTap});

  final _Country country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(country.flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Text(
              country.dialCode,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// A searchable bottom sheet for choosing a country dialling code.
class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet();

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? _countries
        : _countries
            .where((c) =>
                c.name.toLowerCase().contains(q) || c.dialCode.contains(q))
            .toList();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select Country',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Search country or code',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: AppColors.textMuted),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final c = results[i];
                  return ListTile(
                    leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                    title: Text(c.name,
                        style: const TextStyle(color: AppColors.textDark)),
                    trailing: Text(
                      c.dialCode,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(c),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
