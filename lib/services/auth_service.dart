import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../widgets/beautiful_loader.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
// Social sign-ins are intentionally left as stubs until providers are configured.
// Remove these imports to avoid analyzer errors with mismatched package APIs.
import 'package:http/http.dart' as http;
import '../core/config/api_base.dart';
import '../core/utils/validation_service.dart';

class PhoneSignInSession {
  final String phoneNumber;
  final String? verificationId;
  final int? resendToken;
  final ConfirmationResult? confirmationResult;
  final UserCredential? autoVerifiedCredential;

  const PhoneSignInSession({
    required this.phoneNumber,
    this.verificationId,
    this.resendToken,
    this.confirmationResult,
    this.autoVerifiedCredential,
  });

  bool get requiresSmsCode =>
      verificationId != null || confirmationResult != null;
  bool get completedAutomatically => autoVerifiedCredential != null;
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await http.post(
      Uri.parse('$kApiBaseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    Map<String, dynamic>? data;
    if (resp.body.isNotEmpty) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      }
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final message =
          data?['error'] as String? ??
          'Request failed with status ${resp.statusCode}';
      throw FirebaseAuthException(code: 'backend-auth-error', message: message);
    }

    return data ?? <String, dynamic>{};
  }

  Future<UserCredential> signUp(
    String email,
    String password, {
    BuildContext? context,
  }) async {
    Future<UserCredential> operation() async {
      try {
        if (kDebugMode) debugPrint('[DEBUG AuthService] signUp called. Firebase.apps: ${Firebase.apps.map((a) => a.name).toList()}');
        final cred = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (kDebugMode) debugPrint('[DEBUG AuthService] signUp success uid=${cred.user?.uid}');
        return cred;
      } on FirebaseAuthException catch (e, st) {
        if (kDebugMode) debugPrint('[DEBUG AuthService] signUp FirebaseAuthException: $e');
        if (kDebugMode) debugPrint(st.toString());
        rethrow;
      } catch (e, st) {
        if (kDebugMode) debugPrint('[DEBUG AuthService] signUp error: $e');
        if (kDebugMode) debugPrint(st.toString());
        rethrow;
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }

    return await operation();
  }

  Future<UserCredential> signUpWithPhoneAndPassword({
    required String fullName,
    required String phone,
    required String password,
    BuildContext? context,
  }) async {
    Future<UserCredential> operation() async {
      final normalized = ValidationService.normalizePhoneNumber(phone);
      if (normalized == null) {
        throw FirebaseAuthException(
          code: 'invalid-phone',
          message: 'Invalid phone number',
        );
      }

      final payload = await _postJson('/auth/register-phone', {
        'fullName': fullName.trim(),
        'phone': normalized,
        'password': password,
      });

      final customToken = payload['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-custom-token',
          message: 'Server did not return a custom token',
        );
      }

      return _auth.signInWithCustomToken(customToken);
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    return await operation();
  }

  Future<UserCredential> login(
    String email,
    String password, {
    BuildContext? context,
  }) async {
    Future<UserCredential> operation() async {
      try {
        if (kDebugMode) debugPrint('[DEBUG AuthService] login called. Firebase.apps: ${Firebase.apps.map((a) => a.name).toList()}');
        final cred = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (kDebugMode) debugPrint('[DEBUG AuthService] login success uid=${cred.user?.uid}');
        return cred;
      } on FirebaseAuthException catch (e, st) {
        if (kDebugMode) debugPrint('[DEBUG AuthService] login FirebaseAuthException: $e');
        if (kDebugMode) debugPrint(st.toString());
        rethrow;
      } catch (e, st) {
        if (kDebugMode) debugPrint('[DEBUG AuthService] login error: $e');
        if (kDebugMode) debugPrint(st.toString());
        rethrow;
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }

    return await operation();
  }

  Future<void> sendPasswordResetEmail(
    String email, {
    BuildContext? context,
  }) async {
    Future<void> operation() async {
      try {
        await _auth.sendPasswordResetEmail(email: email);
      } on FirebaseAuthException {
        rethrow;
      } catch (_) {
        rethrow;
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }

    return await operation();
  }

  Future<Map<String, dynamic>> requestPasswordResetOtp(
    String phone, {
    BuildContext? context,
  }) async {
    Future<Map<String, dynamic>> operation() async {
      final normalized = ValidationService.normalizePhoneNumber(phone);
      if (normalized == null) {
        throw FirebaseAuthException(
          code: 'invalid-phone',
          message: 'Invalid phone number',
        );
      }
      return _postJson('/auth/request-password-reset', {'phone': normalized});
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    return await operation();
  }

  Future<void> resetPasswordWithOtp({
    required String phone,
    required String code,
    required String newPassword,
    BuildContext? context,
  }) async {
    Future<void> operation() async {
      final normalized = ValidationService.normalizePhoneNumber(phone);
      if (normalized == null) {
        throw FirebaseAuthException(
          code: 'invalid-phone',
          message: 'Invalid phone number',
        );
      }
      await _postJson('/auth/reset-password', {
        'phone': normalized,
        'code': code,
        'newPassword': newPassword,
      });
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    return await operation();
  }

  Future<PhoneSignInSession> startPhoneSignIn({
    required String phoneNumber,
    int? forceResendingToken,
    BuildContext? context,
  }) async {
    Future<PhoneSignInSession> operation() async {
      if (kIsWeb) {
        final confirmationResult = await _auth.signInWithPhoneNumber(
          phoneNumber,
        );
        return PhoneSignInSession(
          phoneNumber: phoneNumber,
          confirmationResult: confirmationResult,
        );
      }

      final completer = Completer<PhoneSignInSession>();

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: forceResendingToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final userCredential = await _auth.signInWithCredential(credential);
            if (!completer.isCompleted) {
              completer.complete(
                PhoneSignInSession(
                  phoneNumber: phoneNumber,
                  autoVerifiedCredential: userCredential,
                ),
              );
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!completer.isCompleted) {
            completer.complete(
              PhoneSignInSession(
                phoneNumber: phoneNumber,
                verificationId: verificationId,
                resendToken: resendToken,
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!completer.isCompleted) {
            completer.complete(
              PhoneSignInSession(
                phoneNumber: phoneNumber,
                verificationId: verificationId,
              ),
            );
          }
        },
      );

      return completer.future;
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }

    return await operation();
  }

  Future<UserCredential> confirmPhoneSignIn({
    required PhoneSignInSession session,
    required String smsCode,
    BuildContext? context,
  }) async {
    Future<UserCredential> operation() async {
      if (session.autoVerifiedCredential != null) {
        return session.autoVerifiedCredential!;
      }

      if (session.confirmationResult != null) {
        return await session.confirmationResult!.confirm(smsCode);
      }

      final verificationId = session.verificationId;
      if (verificationId == null) {
        throw FirebaseAuthException(
          code: 'missing-verification-id',
          message: 'No phone verification session is available.',
        );
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return await _auth.signInWithCredential(credential);
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }

    return await operation();
  }

  Future<void> logout({BuildContext? context}) async {
    Future<void> operation() async {
      try {
        await _auth.signOut();
      } catch (_) {
        rethrow;
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }

    return await operation();
  }

  User? getCurrentUser() {
    return _auth.currentUser;
  }

  /// Sign in with Google using `google_sign_in` and Firebase Authentication.
  /// Returns the signed-in [UserCredential].
  Future<UserCredential> signInWithGoogle({BuildContext? context}) async {
    Future<UserCredential> operation() async {
      throw FirebaseAuthException(code: 'ERROR_NOT_CONFIGURED', message: 'Google sign-in not configured');
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    return await operation();
  }

  /// Sign in with Facebook using `flutter_facebook_auth` and Firebase Authentication.
  Future<UserCredential> signInWithFacebook({BuildContext? context}) async {
    Future<UserCredential> operation() async {
      throw FirebaseAuthException(code: 'ERROR_NOT_CONFIGURED', message: 'Facebook sign-in not configured');
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    return await operation();
  }

  /// Start a TikTok OAuth flow using an external browser. A backend is usually
  /// required to exchange the authorization code for tokens and to mint a
  /// Firebase Custom Token if you want to sign-in a Firebase user.
  ///
  /// This method opens the provider's auth page and returns the raw `code`.
  Future<String> signInWithTikTok({
    required String clientKey,
    required String redirectUri,
    BuildContext? context,
  }) async {
    Future<String> operation() async {
      throw FirebaseAuthException(code: 'ERROR_NOT_CONFIGURED', message: 'TikTok sign-in not configured');
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    return await operation();
  }

  /// Complete TikTok -> Firebase sign-in using a backend exchange endpoint.
  ///
  /// Steps:
  /// 1. Opens TikTok OAuth and returns the `code` (via `signInWithTikTok`).
  /// 2. POSTs the `code` to `backendExchangeUrl` which must exchange the code
  ///    for TikTok access tokens, map/find/create a stable user id, and use the
  ///    Firebase Admin SDK to mint a Firebase Custom Token.
  /// 3. Signs in to Firebase with the returned custom token.
  Future<UserCredential> signInWithTikTokAndFirebase({
    required String clientKey,
    required String redirectUri,
    required String backendExchangeUrl,
    BuildContext? context,
  }) async {
    Future<UserCredential> operation() async {
      try {
        final code = await signInWithTikTok(
          clientKey: clientKey,
          redirectUri: redirectUri,
        );
        final resp = await http.post(
          Uri.parse(backendExchangeUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': code}),
        );
        if (resp.statusCode != 200) {
          throw Exception(
            'Backend exchange failed: ${resp.statusCode} ${resp.body}',
          );
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final customToken = data['firebaseCustomToken'] as String?;
        if (customToken == null) {
          throw Exception('Backend did not return firebaseCustomToken');
        }
        final userCred = await _auth.signInWithCustomToken(customToken);
        return userCred;
      } catch (e) {
        rethrow;
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    return await operation();
  }

  /// Link a phone (via sms code) to the currently signed-in user.
  Future<UserCredential> linkPhoneWithSmsCode({
    required String verificationId,
    required String smsCode,
    BuildContext? context,
  }) async {
    Future<UserCredential> operation() async {
      final current = _auth.currentUser;
      if (current == null) {
        throw FirebaseAuthException(code: 'no-current-user', message: 'No authenticated user to link phone to');
      }
      final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: smsCode);
      final result = await current.linkWithCredential(credential);
      return result;
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    return await operation();
  }

  /// Login using phone number + password. Looks up the auth email stored in phone_index.
  Future<UserCredential> loginWithPhoneAndPassword(
    String phone,
    String password, {
    BuildContext? context,
  }) async {
    Future<UserCredential> operation() async {
      final normalized = ValidationService.normalizePhoneNumber(phone);
      if (normalized == null) {
        throw FirebaseAuthException(
          code: 'invalid-phone',
          message: 'Invalid phone number',
        );
      }

      final payload = await _postJson('/auth/login-phone', {
        'phone': normalized,
        'password': password,
      });

      final customToken = payload['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-custom-token',
          message: 'Server did not return a custom token',
        );
      }

      return _auth.signInWithCustomToken(customToken);
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    return await operation();
  }
}
