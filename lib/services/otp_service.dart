import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/api_base.dart';

class OtpService {
  static Future<Map<String, dynamic>> sendOtp({required String uid, required String phone}) async {
    final uri = Uri.parse('$kApiBaseUrl/send-otp');
    final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'uid': uid, 'phone': phone}));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return {'ok': true, 'data': resp.body.isNotEmpty ? jsonDecode(resp.body) : null};
    }
    return {
      'ok': false,
      'status': resp.statusCode,
      'body': resp.body,
      'error': _extractError(resp.body),
    };
  }

  static Future<Map<String, dynamic>> verifyOtp({required String uid, required String code}) async {
    final uri = Uri.parse('$kApiBaseUrl/verify-otp');
    final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'uid': uid, 'code': code}));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return {'ok': true, 'data': resp.body.isNotEmpty ? jsonDecode(resp.body) : null};
    }
    return {
      'ok': false,
      'status': resp.statusCode,
      'body': resp.body,
      'error': _extractError(resp.body),
    };
  }

  static String? _extractError(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error.trim();
        }
      }
    } catch (_) {
      // Ignore JSON parse errors and fall back to raw body.
    }
    return body.trim().isEmpty ? null : body.trim();
  }
}
