import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_light_mobile/main.dart';

void main() {
  testWidgets('renders Green Light brand mark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrandMark())),
    );

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
