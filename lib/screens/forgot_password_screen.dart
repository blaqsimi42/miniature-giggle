import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/primary_button.dart';
import '../core/utils/validation_service.dart';
import '../widgets/app_notice.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  bool _otpRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (_phoneController.text.isNotEmpty) {
      return;
    }
    if (args is Map) {
      final seed = args['phone'] as String?;
      if (seed != null && seed.trim().isNotEmpty) {
        _phoneController.text = seed.trim();
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      if (!mounted) return;
      AppNotice.showError(context, 'Enter your phone number first.');
      return;
    }

    final normalized = ValidationService.normalizePhoneNumber(phone);
    if (normalized == null) {
      if (!mounted) return;
      AppNotice.showError(context, 'Enter a valid phone number (with country code).');
      return;
    }

    try {
      await AuthService().requestPasswordResetOtp(normalized);
      if (!mounted) return;
      setState(() => _otpRequested = true);
      AppNotice.showSuccess(context, 'Verification code sent.');
      Navigator.pushNamed(context, '/reset-password-otp', arguments: {
        'phone': normalized,
        'sentAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(context, e, fallbackMessage: 'Could not send reset code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgot Password'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Reset your password',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your phone number and we will send you a verification code.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: _phoneController,
              labelText: 'Phone Number',
              icon: Icons.phone_android_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: _otpRequested ? 'Send Another Code' : 'Send Reset Code',
              onPressed: _sendResetLink,
            ),
            const SizedBox(height: 16),
            if (_otpRequested)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(22, 163, 74, 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'If the number exists, the verification screen will open after the code request succeeds.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
