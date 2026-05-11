import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_stripe/flutter_stripe.dart';
import '../core/config/api_base.dart';

class StripeConfig {
  final String? publishableKey;
  final bool stripeEnabled;
  StripeConfig({this.publishableKey, required this.stripeEnabled});
}

class StripeService {
  final http.Client _client = http.Client();

  Future<StripeConfig> fetchConfig() async {
    final uri = Uri.parse('$kApiBaseUrl/stripe-config');
    final resp = await _client.get(uri);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final Map<String, dynamic> body = jsonDecode(resp.body);
      return StripeConfig(publishableKey: body['publishableKey'], stripeEnabled: body['stripeEnabled'] == true);
    }
    return StripeConfig(publishableKey: null, stripeEnabled: false);
  }

  Future<Map<String, dynamic>> createPaymentIntent({required int amount, String currency = 'usd', Map<String, String>? metadata}) async {
    final uri = Uri.parse('$kApiBaseUrl/create-payment-intent');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'amount': amount,
        'currency': currency,
        'metadata': metadata ?? {},
      }),
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }

    throw Exception('Failed to create PaymentIntent: ${resp.statusCode} ${resp.body}');
  }

  Future<void> confirmPayment({required String clientSecret}) async {
    // Wrapper around flutter_stripe confirmation so callers can mock this in tests.
    await Stripe.instance.confirmPayment(
      paymentIntentClientSecret: clientSecret,
      data: PaymentMethodParams.card(paymentMethodData: PaymentMethodData()),
    );
  }
}
