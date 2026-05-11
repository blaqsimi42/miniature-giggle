// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrimonial_app/screens/forgot_password_screen.dart';

void main() {
  testWidgets('forgot password screen renders expected fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ForgotPasswordScreen()),
    );

    expect(find.text('Forgot Password'), findsOneWidget);
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Send Reset Link'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
