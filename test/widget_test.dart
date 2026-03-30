import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:izumi/core/constants/app_colors.dart';
import 'package:izumi/widgets/glass/gradient_background.dart';

void main() {
  testWidgets('Branded shell renders without Firebase bootstrapping', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GradientBackground(
            child: Center(
              child: Text(
                'Izumi',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Izumi'), findsOneWidget);
    expect(find.byType(GradientBackground), findsOneWidget);
  });
}
