import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/profile_completion_gate_service.dart';
import '../services/route_persistence.dart';
import '../services/user_service.dart';
import '../widgets/custom_text_field.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  PhoneSignInSession? _session;
  bool _requestingCode = false;
  bool _verifyingCode = false;
  String? _prefilledName;
  String? _prefilledEmail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final phone = args['phone'];
      final name = args['name'];
      final email = args['email'];
      if (_phoneController.text.isEmpty && phone is String && phone.trim().isNotEmpty) {
        _phoneController.text = phone.trim();
      }
      _prefilledName = name is String && name.trim().isNotEmpty
          ? name.trim()
          : null;
      _prefilledEmail = email is String && email.trim().isNotEmpty
          ? email.trim()
          : null;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _requestCode({bool isResend = false}) async {
    final scaffold = ScaffoldMessenger.of(context);
    final phoneNumber = _normalizePhoneNumber(_phoneController.text);
    if (phoneNumber == null) {
      scaffold.showSnackBar(
        const SnackBar(
          content: Text('Enter a valid phone number with country code, for example +15551234567.'),
        ),
      );
      return;
    }

    setState(() {
      _requestingCode = true;
    });

    try {
      final session = await _authService.startPhoneSignIn(
        phoneNumber: phoneNumber,
        forceResendingToken: isResend ? _session?.resendToken : null,
        context: context,
      );
      if (!mounted) {
        return;
      }

      if (session.completedAutomatically) {
        await _finishSignedIn(
          session.autoVerifiedCredential!,
          phoneNumber: phoneNumber,
        );
        return;
      }

      setState(() {
        _session = session;
      });
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            isResend
                ? 'A new verification code has been sent.'
                : 'Verification code sent to $phoneNumber',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      scaffold.showSnackBar(
        SnackBar(content: Text('Could not send verification code: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _requestingCode = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final scaffold = ScaffoldMessenger.of(context);
    final session = _session;
    if (session == null) {
      scaffold.showSnackBar(
        const SnackBar(content: Text('Request a verification code first.')),
      );
      return;
    }

    final smsCode = _otpController.text.trim();
    if (smsCode.length < 6) {
      scaffold.showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit verification code.')),
      );
      return;
    }

    setState(() {
      _verifyingCode = true;
    });

    try {
      final credential = await _authService.confirmPhoneSignIn(
        session: session,
        smsCode: smsCode,
        context: context,
      );
      if (!mounted) {
        return;
      }
      await _finishSignedIn(
        credential,
        phoneNumber: _normalizePhoneNumber(_phoneController.text) ?? session.phoneNumber,
      );
    } catch (e) {
      if (!mounted) return;
      scaffold.showSnackBar(
        SnackBar(content: Text('Verification failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _verifyingCode = false;
        });
      }
    }
  }

  Future<void> _finishSignedIn(
    UserCredential credential, {
    required String phoneNumber,
  }) async {
    await _completeSignIn(credential, phoneNumber: phoneNumber);
    if (!mounted) {
      return;
    }
    final userName = credential.user?.displayName ?? _prefilledName ?? 'Member';
    unawaited(
      RoutePersistence.save('/home', {'userName': userName, 'name': userName}),
    );
    await ProfileCompletionGateService.routeAfterAuth(
      context,
      homeArgs: {'userName': userName, 'name': userName},
    );
  }

  Future<void> _completeSignIn(
    UserCredential credential, {
    required String phoneNumber,
  }) async {
    final user = credential.user;
    if (user == null) {
      throw Exception('Phone sign-in completed without a user account.');
    }

    final existingProfile = await _userService.getUser(user.uid);
    final resolvedName =
        (existingProfile?.fullName.trim().isNotEmpty == true
            ? existingProfile!.fullName
            : _prefilledName) ??
        user.displayName ??
        'Member';
    final resolvedEmail = existingProfile?.email ?? _prefilledEmail ?? user.email;
    final resolvedPhone =
        existingProfile?.phone ?? user.phoneNumber ?? phoneNumber;

    if (existingProfile == null) {
      await _userService.createUserProfile(
        UserModel(
          uid: user.uid,
          fullName: resolvedName,
          email: resolvedEmail,
          phone: resolvedPhone,
        ),
      );
    } else {
      final updates = <String, dynamic>{};
      if ((existingProfile.phone ?? '').trim().isEmpty && resolvedPhone.isNotEmpty) {
        updates['phone'] = resolvedPhone;
      }
      if ((existingProfile.email ?? '').trim().isEmpty &&
          resolvedEmail != null &&
          resolvedEmail.trim().isNotEmpty) {
        updates['email'] = resolvedEmail.trim();
      }
      if (existingProfile.fullName.trim().isEmpty && resolvedName.trim().isNotEmpty) {
        updates['fullName'] = resolvedName.trim();
      }
      if (updates.isNotEmpty) {
        await _userService.updateUser(user.uid, updates);
      }
    }

    if ((user.displayName ?? '').trim().isEmpty && resolvedName.trim().isNotEmpty) {
      await user.updateDisplayName(resolvedName.trim());
      await user.reload();
    }
  }

  String? _normalizePhoneNumber(String input) {
    final compact = input.replaceAll(RegExp(r'[\s()-]'), '');
    if (compact.isEmpty) {
      return null;
    }
    if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(compact)) {
      return null;
    }
    return compact.startsWith('+') ? compact : '+$compact';
  }

  @override
  Widget build(BuildContext context) {
    final codeRequested = _session != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone OTP Login'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sign in with your mobile number',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use your country code and we will send a one-time verification code.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: _phoneController,
              labelText: 'Phone Number',
              icon: Icons.phone_android,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 8),
            const Text(
              'Example: +15551234567',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _requestingCode
                    ? null
                    : () => _requestCode(isResend: codeRequested),
                child: Text(
                  _requestingCode
                      ? 'Sending Code...'
                      : codeRequested
                      ? 'Send New Code'
                      : 'Send Verification Code',
                ),
              ),
            ),
            if (codeRequested) ...[
              const SizedBox(height: 24),
              CustomTextField(
                controller: _otpController,
                labelText: 'Verification Code',
                icon: Icons.lock_clock_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the code sent to ${_session!.phoneNumber}',
                style: const TextStyle(color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _verifyingCode ? null : _verifyCode,
                  child: Text(
                    _verifyingCode
                        ? 'Verifying...'
                        : 'Verify and Continue',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _requestingCode ? null : () => _requestCode(isResend: true),
                child: const Text('Resend Code'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
