import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/primary_button.dart';
import '../services/auth_service.dart';
import '../core/utils/validation_service.dart';
import '../services/otp_service.dart';
import '../widgets/app_notice.dart';

const Color _kGreen = Color(0xFF16A34A);
// File-level helpers for password validation
bool _hasMinChars(String s) => s.length >= 8;
bool _hasCapital(String s) => RegExp(r'[A-Z]').hasMatch(s);
bool _hasSpecial(String s) => RegExp(r'[!@#\$%\^&*(),.?":{}|<>]').hasMatch(s);
bool _noCommon(String s) =>
    !RegExp(r'123456|password|qwerty|admin').hasMatch(s.toLowerCase());

class PasswordSetupScreen extends StatefulWidget {
  const PasswordSetupScreen({super.key});

  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _step2Complete = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_updateStep2);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_updateStep2);
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _updateStep2() {
    final filled = _passwordController.text.trim().isNotEmpty && _passwordController.text.length >= 8;
    if (filled != _step2Complete) setState(() => _step2Complete = filled);
  }

  Future<void> _completeSignUp({
    required String? prefilledName,
    required String? prefilledPhone,
  }) async {
    final navigator = Navigator.of(context);
    final name = prefilledName?.trim() ?? '';
    final phoneRaw = prefilledPhone?.trim() ?? '';
    final normalizedPhone = phoneRaw.startsWith('+') ? phoneRaw : (phoneRaw.isNotEmpty ? '+$phoneRaw' : '');

    if (phoneRaw.isEmpty) {
      AppNotice.showError(context, 'Phone missing from previous step');
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      AppNotice.showError(context, 'Passwords do not match');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final normalized = ValidationService.normalizePhoneNumber(normalizedPhone) ?? normalizedPhone;
      final cred = await AuthService().signUpWithPhoneAndPassword(
        fullName: name,
        phone: normalized,
        password: _passwordController.text,
      );

      final uid = cred.user?.uid;
      if (uid == null) throw Exception('Failed to create auth user');
      if (kDebugMode) debugPrint('[DEBUG signup] created phone-password user uid=$uid');

      // Start server-side OTP flow: request OTP to be sent to phone
      try {
        final resp = await OtpService.sendOtp(uid: uid, phone: normalized);
        if (resp['ok'] == true) {
          if (!mounted) return;
          AppNotice.showSuccess(context, 'Verification code sent.');
          navigator.pushNamed('/verify-phone-link', arguments: {
            'phone': normalized,
            'uid': uid,
            'sentAt': DateTime.now().toIso8601String(),
          });
        } else {
          if (!mounted) return;
          AppNotice.showError(
            context,
            resp['error'] ?? resp['body'] ?? 'Failed to send verification code.',
          );
        }
      } catch (e) {
        if (!mounted) return;
        AppNotice.showError(context, e, fallbackMessage: 'Failed to send verification code.');
      }
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(context, e, fallbackMessage: 'Sign up failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pwd = _passwordController.text;
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final prefilledName = args?['name'] as String?;
    final prefilledPhone = args?['phone'] as String?;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'STEP 2 OF 2',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Two-segment progress bar showing step1 completion on the left and step2 progress on the right
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Builder(builder: (ctx) {
                final leftFilled = (prefilledName?.trim().isNotEmpty ?? false) && (prefilledPhone?.trim().isNotEmpty ?? false);
                return Container(
                  height: 8,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0,2))]),
                  child: Row(
                    children: [
                      Expanded(child: Container(decoration: BoxDecoration(color: leftFilled ? _kGreen : Colors.white, borderRadius: const BorderRadius.horizontal(left: Radius.circular(8))))),
                      Expanded(child: Container(decoration: BoxDecoration(color: _step2Complete ? _kGreen : Colors.white, borderRadius: const BorderRadius.horizontal(right: Radius.circular(8))))),
                    ],
                  ),
                );
              }),
            ),

            const Text('Choose a strong password', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('This helps keep your account secure', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF6B7280))),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))]),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CustomTextField(
                    controller: _passwordController,
                    labelText: 'Password',
                    icon: Icons.lock,
                    obscureText: _obscure,
                    suffix: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: _confirmController,
                    labelText: 'Confirm Password',
                    icon: Icons.lock,
                    obscureText: _obscure,
                  ),
                  const SizedBox(height: 16),
                  _ValidationChecklist(pwd: pwd),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: _isSubmitting ? 'Processing...' : 'Complete Sign Up',
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting
                        ? null
                        : () => _completeSignUp(
                              prefilledName: prefilledName,
                              prefilledPhone: prefilledPhone,
                            ),
                  ),

                  const SizedBox(height: 12),
                  const Text(
                    'By continuing you agree to our Privacy Policy & Terms',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ValidationChecklist extends StatelessWidget {
  final String pwd;
  const _ValidationChecklist({required this.pwd});

  @override
  Widget build(BuildContext context) {
    bool min = _hasMinChars(pwd);
    bool cap = _hasCapital(pwd);
    bool spec = _hasSpecial(pwd);
    bool common = _noCommon(pwd);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _check('8+ characters', min),
        const SizedBox(height: 8),
        _check('1 capital letter', cap),
        const SizedBox(height: 8),
        _check('1 special character', spec),
        const SizedBox(height: 8),
        _check('No common patterns', common),
      ],
    );
  }

  Widget _check(String text, bool ok) => Row(
    children: [
      Icon(
        ok ? Icons.check_circle : Icons.radio_button_unchecked,
        color: ok ? Color(0xFF16A34A) : Colors.black26,
        size: 18,
      ),
      const SizedBox(width: 8),
      Text(text),
    ],
  );
}
