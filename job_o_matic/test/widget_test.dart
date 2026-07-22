import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/presentation/screens/job_input_screen.dart';

void main() {
  testWidgets('App loads and shows Job Input Screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: JobInputScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify the app title is shown
    expect(find.text('Job-O-Matic'), findsOneWidget);
    expect(find.text('Stellenangebote eingeben'), findsOneWidget);
  });

  testWidgets('App shows search and continue buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: JobInputScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify the buttons are present
    expect(find.text('Jobsuche'), findsOneWidget);
    expect(find.text('Weiter'), findsOneWidget);
  });
}