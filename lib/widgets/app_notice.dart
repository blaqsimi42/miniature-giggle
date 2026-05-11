import 'dart:async';

import 'package:flutter/material.dart';

enum AppNoticeType { success, error, loading }

class AppNotice {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      context,
      message: message,
      type: AppNoticeType.success,
      duration: duration,
    );
  }

  static void showError(
    BuildContext context,
    Object error, {
    String? fallbackMessage,
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      context,
      message: friendlyMessage(error, fallbackMessage: fallbackMessage),
      type: AppNoticeType.error,
      duration: duration,
    );
  }

  static void showLoading(
    BuildContext context,
    String message,
  ) {
    _show(
      context,
      message: message,
      type: AppNoticeType.loading,
      duration: Duration.zero,
    );
  }

  static String friendlyMessage(
    Object error, {
    String? fallbackMessage,
  }) {
    var raw = error.toString().trim();
    if (raw.startsWith('Exception:')) {
      raw = raw.substring('Exception:'.length).trim();
    }

    final bracketMatch = RegExp(r'^\[[^\]]+\]\s*(.*)$').firstMatch(raw);
    if (bracketMatch != null) {
      raw = (bracketMatch.group(1) ?? raw).trim();
    }

    final lower = raw.toLowerCase();

    if (lower.contains('firestore not configured on server')) {
      return 'Service is temporarily unavailable. Please try again in a moment.';
    }
    if (lower.contains('already registered') ||
        lower.contains('already in use') ||
        lower.contains('number already used')) {
      return 'Phone number already in use.';
    }
    if (lower.contains('invalid phone')) {
      return 'Enter a valid phone number.';
    }
    if (lower.contains('phone and password are required')) {
      return 'Enter both your phone number and password.';
    }
    if (lower.contains('no account found for this phone number')) {
      return 'No account was found for that phone number.';
    }
    if (lower.contains('invalid code')) {
      return 'The verification code you entered is invalid.';
    }
    if (lower.contains('otp expired') ||
        lower.contains('verification code expired')) {
      return 'That verification code has expired. Please request a new one.';
    }
    if (lower.contains('passwords do not match')) {
      return 'Passwords do not match.';
    }
    if (lower.contains('password must be at least 8 characters')) {
      return 'Password must be at least 8 characters long.';
    }
    if (lower.contains('uppercase')) {
      return 'Password must include at least one uppercase letter.';
    }
    if (lower.contains('digit')) {
      return 'Password must include at least one number.';
    }
    if (lower.contains('special character')) {
      return 'Password must include at least one special character.';
    }

    if (fallbackMessage != null && fallbackMessage.trim().isNotEmpty) {
      return fallbackMessage.trim();
    }

    return raw.isEmpty ? 'Something went wrong. Please try again.' : raw;
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  static void _show(
    BuildContext context, {
    required String message,
    required AppNoticeType type,
    required Duration duration,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    hide();

    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (context) => _AppNoticeCard(
        message: message,
        type: type,
      ),
    );
    overlay.insert(entry);
    _entry = entry;
    if (duration > Duration.zero) {
      _timer = Timer(duration, hide);
    }
  }
}

class _AppNoticeCard extends StatelessWidget {
  final String message;
  final AppNoticeType type;

  const _AppNoticeCard({
    required this.message,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final isError = type == AppNoticeType.error;
    final isLoading = type == AppNoticeType.loading;
    final accent = isLoading
        ? const Color(0xFF0F766E)
        : isError
            ? const Color(0xFFDC2626)
            : const Color(0xFF16A34A);
    final icon = isError ? Icons.priority_high_rounded : Icons.check_rounded;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      right: 16,
      left: MediaQuery.of(context).size.width < 420 ? 16 : null,
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.topRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 20,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(accent),
                              ),
                            )
                          : Icon(icon, color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
