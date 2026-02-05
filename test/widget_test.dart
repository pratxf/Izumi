// Basic Flutter widget test for Izumi app

import 'package:flutter_test/flutter_test.dart';

import 'package:izumi/main.dart';

void main() {
  testWidgets('App launches and shows welcome screen', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const IzumiApp());

    // Verify that the welcome screen is shown
    expect(find.text('Izumi'), findsWidgets);
  });
}
