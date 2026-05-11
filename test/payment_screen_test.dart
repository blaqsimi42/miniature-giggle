import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:matrimonial_app/screens/payment_screen.dart';
import 'package:matrimonial_app/services/mock_payment_service.dart';
import 'package:matrimonial_app/services/stripe_service.dart';

class FakeStripeService extends StripeService {
  @override
  Future<StripeConfig> fetchConfig() async => StripeConfig(publishableKey: null, stripeEnabled: false);
}

class FakeMockPaymentService extends MockPaymentService {
  bool called = false;
  @override
  Future<Map<String, dynamic>> mockPaymentSuccess({String? userId, int amount = 0, String plan = 'premium'}) async {
    called = true;
    return {'status': 'succeeded'};
  }
}

void main() {
  setUp(() async {
    await GetIt.instance.reset();
    // register only the fakes needed by PaymentScreen
    GetIt.I.registerSingleton<StripeService>(FakeStripeService());
    GetIt.I.registerSingleton<MockPaymentService>(FakeMockPaymentService());
  });

  testWidgets('PaymentScreen uses mock payment when Stripe disabled', (tester) async {
    final fakeMock = GetIt.I<MockPaymentService>() as FakeMockPaymentService;

    await tester.pumpWidget(MaterialApp(home: PaymentScreen(amount: 499)));
    await tester.pumpAndSettle();

    final payButton = find.text('Pay');
    expect(payButton, findsOneWidget);
    await tester.tap(payButton);
    await tester.pumpAndSettle();

    expect(fakeMock.called, isTrue);
  });
}
