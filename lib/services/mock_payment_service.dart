import 'dart:convert';

import 'package:http/http.dart' as http;
import '../core/config/api_base.dart';

class MockPaymentService {
  final http.Client _client = http.Client();

  Future<Map<String, dynamic>> mockPaymentSuccess({String? userId, int amount = 0, String plan = 'premium'}) async {
    final uri = Uri.parse('$kApiBaseUrl/mock-payment-success');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'plan': plan, 'amount': amount}),
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }

    throw Exception('Mock payment failed: ${resp.statusCode} ${resp.body}');
  }
}
