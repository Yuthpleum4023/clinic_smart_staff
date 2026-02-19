// This is a basic Flutter widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clinic_smart_staff/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // ✅ เช็คว่าแอป build ได้ (ไม่ต้องใช้ counter แล้ว)
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
