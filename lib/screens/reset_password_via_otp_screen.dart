import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/app_notice.dart';

class ResetPasswordViaOtpScreen extends StatefulWidget {
  const ResetPasswordViaOtpScreen({super.key});

  @override
  State<ResetPasswordViaOtpScreen> createState() =>
      _ResetPasswordViaOtpScreenState();
}

class _ResetPasswordViaOtpScreenState extends State<ResetPasswordViaOtpScreen> {
  String? _phone;
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _verifying = false;
  DateTime? _sentAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _phone = args['phone'] as String?;
      final sent = args['sentAt'] as String?;
      if (sent != null) {
        _sentAt = DateTime.tryParse(sent) ?? DateTime.now();
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _isExpired {
    if (_sentAt == null) return false;
    return DateTime.now().difference(_sentAt!).inMinutes > 30;
  }

  Future<void> _reset() async {
    final phone = _phone;
    if (phone == null || phone.trim().isEmpty) {
      AppNotice.showError(context, 'No phone number available');
      return;
    }
    if (_isExpired) {
      AppNotice.showError(context, 'Verification code expired. Please resend.');
      return;
    }

    final code = _codeController.text.trim();
    final pwd = _passwordController.text;
    if (pwd.isEmpty || pwd != _confirmController.text) {
      AppNotice.showError(context, 'Passwords do not match or are empty');
      return;
    }

    setState(() => _verifying = true);
    try {
      await AuthService().resetPasswordWithOtp(
        phone: phone,
        code: code,
        newPassword: pwd,
        context: context,
      );
      if (!mounted) return;
      AppNotice.showSuccess(
        context,
        'Password reset successful. Please log in with your new password.',
      );
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(context, e, fallbackMessage: 'Password reset failed.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password via OTP')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the code and your new password',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Verification code',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Confirm new password'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _verifying ? null : _reset,
              child: Text(_verifying ? 'Resetting...' : 'Reset Password'),
            ),
            if (_sentAt != null) Text('Code sent at: ${_sentAt!.toLocal()}'),
            if (_isExpired)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Code expired',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
