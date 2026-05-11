import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/otp_service.dart';
import '../services/profile_completion_gate_service.dart';
import '../services/route_persistence.dart';
import '../widgets/app_notice.dart';

class VerifyPhoneLinkScreen extends StatefulWidget {
  const VerifyPhoneLinkScreen({super.key});

  @override
  State<VerifyPhoneLinkScreen> createState() => _VerifyPhoneLinkScreenState();
}

class _VerifyPhoneLinkScreenState extends State<VerifyPhoneLinkScreen> {
  static const int _otpLength = 6;
  static const int _resendCooldownSeconds = 30;

  final StringBuffer _codeBuffer = StringBuffer();
  Timer? _ticker;
  bool _verifying = false;
  bool _requesting = false;
  DateTime? _sentAt;
  String? _phone;
  String? _uid;
  String? _returnTo;
  Map<String, dynamic>? _returnArgs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _phone = args['phone'] as String?;
      _uid = args['uid'] as String?;
      _returnTo = args['returnTo'] as String?;
      _returnArgs = args['returnArgs'] as Map<String, dynamic>?;
      final sent = args['sentAt'] as String?;
      if (sent != null) {
        _sentAt = DateTime.tryParse(sent) ?? DateTime.now();
      }
    }
    _sentAt ??= DateTime.now();
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _isExpired {
    if (_sentAt == null) return false;
    return DateTime.now().difference(_sentAt!).inMinutes > 10;
  }

  int get _resendRemaining {
    if (_sentAt == null) return 0;
    final elapsed = DateTime.now().difference(_sentAt!).inSeconds;
    final remaining = _resendCooldownSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  String get _code => _codeBuffer.toString();

  String get _resendLabel {
    final remaining = _resendRemaining;
    if (remaining <= 0) return 'Resend code';
    final seconds = remaining.toString().padLeft(2, '0');
    return 'Resend code in 00:$seconds';
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _appendDigit(String digit) {
    if (_verifying || _requesting || _isExpired || _code.length >= _otpLength) {
      return;
    }
    setState(() {
      _codeBuffer.write(digit);
    });
    if (_code.length == _otpLength) {
      unawaited(_verify());
    }
  }

  void _removeDigit() {
    if (_verifying || _code.isEmpty) return;
    setState(() {
      final next = _code.substring(0, _code.length - 1);
      _codeBuffer
        ..clear()
        ..write(next);
    });
  }

  Future<void> _verify() async {
    final targetUid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (targetUid == null) {
      AppNotice.showError(context, 'No user id available for verification');
      return;
    }
    if (_isExpired) {
      AppNotice.showError(context, 'Verification code expired. Please resend.');
      return;
    }
    if (_code.length != _otpLength) {
      AppNotice.showError(context, 'Enter the 6-digit verification code.');
      return;
    }

    setState(() => _verifying = true);
    try {
      final resp = await OtpService.verifyOtp(uid: targetUid, code: _code);
      if (resp['ok'] == true) {
        if (!mounted) return;
        final userName = FirebaseAuth.instance.currentUser?.displayName ?? 'Member';
        AppNotice.showSuccess(context, 'Phone number verified successfully.');
        if (_returnTo != null && _returnTo!.isNotEmpty) {
          unawaited(RoutePersistence.save(_returnTo!, _returnArgs));
          Navigator.of(context).pushReplacementNamed(_returnTo!, arguments: _returnArgs);
        } else {
          unawaited(RoutePersistence.save('/home', {'userName': userName, 'name': userName}));
          await ProfileCompletionGateService.routeAfterAuth(
            context,
            homeArgs: {'userName': userName, 'name': userName},
          );
        }
      } else {
        if (!mounted) return;
        final error = resp['error'] ?? resp['body'] ?? resp['status'] ?? 'unknown';
        AppNotice.showError(context, error, fallbackMessage: 'Verification failed.');
      }
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(context, e, fallbackMessage: 'Verification failed.');
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  Future<void> _resend() async {
    final phone = _phone;
    final targetUid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (phone == null || targetUid == null || _requesting || _resendRemaining > 0) {
      return;
    }
    setState(() => _requesting = true);
    try {
      final resp = await OtpService.sendOtp(uid: targetUid, phone: phone);
      if (resp['ok'] == true) {
        if (!mounted) return;
        setState(() {
          _sentAt = DateTime.now();
          _codeBuffer.clear();
        });
        AppNotice.showSuccess(context, 'Verification code resent.');
      } else {
        if (!mounted) return;
        final error = resp['error'] ?? resp['body'] ?? resp['status'] ?? 'error';
        AppNotice.showError(context, error, fallbackMessage: 'Could not resend code.');
      }
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(context, e, fallbackMessage: 'Could not resend code.');
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
      }
    }
  }

  String _maskPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) return 'your phone number';
    final cleaned = phone.trim();
    if (cleaned.length <= 4) return cleaned;
    final visibleEnd = cleaned.substring(cleaned.length - 4);
    final prefixLength = cleaned.startsWith('+') ? 3 : 2;
    final prefix = cleaned.substring(0, cleaned.length < prefixLength ? cleaned.length : prefixLength);
    return '$prefix ${'•' * 3} ${'•' * 3} $visibleEnd';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F2EA),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: _verifying ? null : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Verify your number',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF172B24),
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Enter the 6 digit code sent to',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF5B6B62),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _maskPhone(_phone),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF172B24),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 34),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        _otpLength,
                        (index) => _OtpDigitBox(
                          value: index < _code.length ? _code[index] : '',
                          isActive: !_verifying && index == _code.length && _code.length < _otpLength,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _verifying
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF16A34A)),
                                ),
                              )
                            : TextButton(
                                onPressed: (_requesting || _resendRemaining > 0) ? null : _resend,
                                child: Text(
                                  _requesting ? 'Resending...' : _resendLabel,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: (_requesting || _resendRemaining > 0)
                                        ? const Color(0xFF9AA6A0)
                                        : const Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    if (_isExpired)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Center(
                          child: Text(
                            'This code expired. Please request a new one.',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _OtpKeypad(
              enabled: !_verifying && !_requesting && !_isExpired,
              onDigitPressed: _appendDigit,
              onBackspace: _removeDigit,
            ),
          ],
        ),
      ),
    );
  }
}

class _OtpDigitBox extends StatelessWidget {
  final String value;
  final bool isActive;

  const _OtpDigitBox({required this.value, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 48,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? const Color(0xFF16A34A) : const Color(0xFFE7DED2),
          width: isActive ? 2 : 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Color(0xFF172B24),
        ),
      ),
    );
  }
}

class _OtpKeypad extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onDigitPressed;
  final VoidCallback onBackspace;

  const _OtpKeypad({
    required this.enabled,
    required this.onDigitPressed,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '', '0', 'back',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xFFF3ECE1),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: keys.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.55,
        ),
        itemBuilder: (context, index) {
          final key = keys[index];
          if (key.isEmpty) {
            return const SizedBox.shrink();
          }

          if (key == 'back') {
            return _KeypadButton(
              enabled: enabled,
              onTap: onBackspace,
              child: const Icon(Icons.backspace_outlined, color: Color(0xFF172B24)),
            );
          }

          return _KeypadButton(
            enabled: enabled,
            onTap: () => onDigitPressed(key),
            child: Text(
              key,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF172B24),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool enabled;

  const _KeypadButton({
    required this.child,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: enabled ? 1 : 0.45,
          child: Center(child: child),
        ),
      ),
    );
  }
}
