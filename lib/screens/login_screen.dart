import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/data/countries.dart';
import '../core/utils/validation_service.dart';
import '../services/auth_service.dart';
import '../services/profile_completion_gate_service.dart';
import '../services/route_persistence.dart';
import '../widgets/app_notice.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<_PhoneFieldState> _phoneFieldKey = GlobalKey<_PhoneFieldState>();
  bool _isLoggingIn = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _openForgotPassword() async {
    final navigator = Navigator.of(context);
    final args = <String, dynamic>{};
    final phone = _phoneFieldKey.currentState?.fullPhoneNumber ?? _phoneController.text.trim();
    if (phone.isNotEmpty) args['phone'] = phone;
    unawaited(RoutePersistence.save('/forgot-password', args.isEmpty ? null : args));
    navigator.pushNamed('/forgot-password', arguments: args.isEmpty ? null : args);
  }

  Future<void> _loginWithPhonePassword() async {
    setState(() => _isLoggingIn = true);
    try {
      final phone = _phoneFieldKey.currentState?.fullPhoneNumber ?? _phoneController.text.trim();
      await AuthService().loginWithPhoneAndPassword(phone, _passwordController.text, context: context);
      if (!mounted) return;
      // Ensure keyboard is dismissed before routing to avoid negative viewInsets on web.
      try {
        FocusManager.instance.primaryFocus?.unfocus();
      } catch (_) {}

      unawaited(RoutePersistence.save('/home'));
      await ProfileCompletionGateService.routeAfterAuth(context);
    } catch (e) {
      if (kDebugMode) debugPrint('Phone password login error: $e');
      if (!mounted) return;
      AppNotice.showError(context, e, fallbackMessage: 'Login failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFAF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report, color: Colors.black54),
              onPressed: () => Navigator.of(context).pushNamed('/debug'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // Header
            const SizedBox(height: 8),
            const Text('Welcome back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Let\'s find your perfect match', style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
            const SizedBox(height: 20),

            // Card containing inputs
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))],
              ),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Phone / Email input with country code
                    _PhoneField(key: _phoneFieldKey, controller: _phoneController),
                  const SizedBox(height: 12),

                  // Password field (reusing existing controller and logic)
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _openForgotPassword, child: const Text('Forgot password?')),
                  ),

                  const SizedBox(height: 8),
                  // Primary button (reuses existing login logic)
                  ElevatedButton(
                    onPressed: _isLoggingIn ? null : _loginWithPhonePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isLoggingIn) ...[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          _isLoggingIn ? 'Processing...' : 'Log in',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(),
                  ),
                  TextButton(
                    onPressed: () {
                      unawaited(RoutePersistence.save('/personal'));
                      Navigator.pushReplacementNamed(context, '/personal');
                    },
                    child: const Text('Create an account'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            // Footer
            const Text(
              'By continuing you agree to our Terms & Conditions and Privacy Policy',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}


// Small internal widget: phone-only field with country picker.
class _PhoneField extends StatefulWidget {
  final TextEditingController controller;
  const _PhoneField({super.key, required this.controller});

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  String _countryCode = '+91';

  String get fullPhoneNumber {
    final localPhone = widget.controller.text.trim();
    if (localPhone.isEmpty) return '';

    if (localPhone.startsWith('+')) {
      return ValidationService.normalizePhoneNumber(localPhone) ?? localPhone;
    }

    final digitsOnly = localPhone.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) return '';

    final countryDigits = _countryCode.replaceAll('+', '');
    return ValidationService.normalizePhoneNumber('+$countryDigits$digitsOnly') ??
        '+$countryDigits$digitsOnly';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openCountryPicker,
            child: Row(
              children: [
                Text(_flagForDial(_countryCode), style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(_countryCode, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: 'Phone number',
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _flagForDial(String dial) {
    final item = kCountries.firstWhere((c) => c['dial'] == dial, orElse: () => kCountries.first);
    return item['flag'] ?? '🏳️';
  }

  void _openCountryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, sc) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4))),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: Align(alignment: Alignment.centerLeft, child: Text('Select your country', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: sc,
                    itemCount: kCountries.length,
                    itemBuilder: (context, i) {
                      final c = kCountries[i];
                      return ListTile(
                        leading: Text(c['flag'] ?? '', style: const TextStyle(fontSize: 20)),
                        title: Text('${c['name']}'),
                        subtitle: Text(c['dial'] ?? ''),
                        onTap: () {
                          setState(() => _countryCode = c['dial'] ?? _countryCode);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
