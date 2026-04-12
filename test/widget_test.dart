import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polri_body_worn/main.dart';

void main() {
  testWidgets('renders startup shell', (tester) async {
    await tester.pumpWidget(const BodyWornApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
