import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';

/// Contact Support — a validated message form that composes an email to the
/// support address via the device's mail app (a real, reliable send path that
/// needs no backend table).
class ContactSupportScreen extends StatefulWidget {
  const ContactSupportScreen({super.key, this.supportEmail});

  final String? supportEmail;

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  static const _fallbackEmail = 'support@ino.app';

  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;

  String get _email => widget.supportEmail ?? _fallbackEmail;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final uri = Uri(
        scheme: 'mailto',
        path: _email,
        query: _encodeQuery({
          'subject': _subject.text.trim(),
          'body': '${_message.text.trim()}\n\n— Sent from INO',
        }),
      );
      developer.log('contact: launching $uri', name: 'support');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (ok) {
        BiometricUx.successSnack(
            context, 'Opening your mail app to send the message.');
        Navigator.of(context).pop();
      } else {
        BiometricUx.errorSnack(
            context, 'No mail app found. Email us at $_email');
      }
    } catch (e) {
      developer.log('contact send error: $e', name: 'support', error: e);
      if (mounted) {
        BiometricUx.errorSnack(context, 'Could not open your mail app.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Uri's query encoder turns spaces into '+'; mail clients want %20, so encode
  // the components ourselves.
  String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsScaffold(
      title: 'Contact Support',
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md,
              AppSpacing.screen, AppSpacing.xl),
          children: [
            Text(
              'Tell us what’s going on and we’ll get back to you. Your message '
              'opens in your mail app addressed to our support team.',
              style: AppText.body
                  .copyWith(color: palette.textSecondary, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            AuthTextField(
              controller: _subject,
              label: 'Subject',
              icon: Icons.subject_rounded,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Add a short subject'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _MessageField(controller: _message),
            const SizedBox(height: AppSpacing.lg),
            SettingsCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.alternate_email_rounded,
                      color: palette.textSecondary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_email,
                        style: AppText.body
                            .copyWith(color: palette.textSecondary)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SettingsPrimaryButton(
              label: 'Send Message',
              icon: Icons.send_rounded,
              busy: _busy,
              onPressed: _busy ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// A multi-line message input styled to match [AuthTextField].
class _MessageField extends StatelessWidget {
  const _MessageField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: 5,
      maxLines: 8,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(
        color: AppColors.textDark,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      validator: (v) =>
          (v == null || v.trim().length < 10) ? 'Add a bit more detail' : null,
      decoration: InputDecoration(
        labelText: 'Message',
        alignLabelWithHint: true,
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        floatingLabelStyle: const TextStyle(color: AppColors.primaryGreen),
        border: _border(const Color(0xFFE2E8F0)),
        enabledBorder: _border(const Color(0xFFE2E8F0)),
        focusedBorder: _border(AppColors.primaryGreen, width: 1.6),
        errorBorder: _border(AppColors.critical),
        focusedErrorBorder: _border(AppColors.critical, width: 1.6),
      ),
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1.2}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
}
