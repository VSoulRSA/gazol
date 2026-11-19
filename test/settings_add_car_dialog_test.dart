import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gazol/settings_screen.dart';

Future<void> _openAddCarDialog(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'lastFuelUpdate': DateTime.now().millisecondsSinceEpoch,
    'last_selected_fuel': 'fuel95',
  });
  await tester.pumpWidget(MaterialApp(home: SettingsScreen()));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.byIcon(Icons.add));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Add Car'), findsOneWidget);
}

Finder _field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

void _expectNoFlexOverflow(WidgetTester tester) {
  final errors = <String>[];
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    errors.add(exception.toString());
  }
  expect(errors.join(' '), isNot(contains('RenderFlex overflowed')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Add Car dialog saves with keyboard open on a short screen',
      (tester) async {
    tester.view.physicalSize = const Size(600, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await _openAddCarDialog(tester);
    await tester.tap(_field('Car Name'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(_field('Car Name'), 'Toyota Corolla');
    await tester.pump();
    _expectNoFlexOverflow(tester);

    await tester.tap(_field('Fuel Consumption (L/100km)'));
    await tester.enterText(_field('Fuel Consumption (L/100km)'), '6.8');
    await tester.pump();
    _expectNoFlexOverflow(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('add-car-fuel-type')));
    await tester.tap(find.byKey(const ValueKey('add-car-fuel-type')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Diesel 500ppm'), findsWidgets);
    await tester.tap(find.text('Diesel 500ppm').last);
    await tester.pump(const Duration(milliseconds: 150));
    _expectNoFlexOverflow(tester);

    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Save'),
    ));
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump(const Duration(milliseconds: 600));
    final savedCars = (await SharedPreferences.getInstance()).getString('cars');
    expect(savedCars, contains('Toyota Corolla'));
    expect(savedCars, contains('diesel500'));
    _expectNoFlexOverflow(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Add Car dialog saves with keyboard closed on a short screen',
      (tester) async {
    tester.view.physicalSize = const Size(600, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _openAddCarDialog(tester);
    await tester.enterText(_field('Car Name'), 'VW Polo');
    await tester.enterText(_field('Fuel Consumption (L/100km)'), '5.5');
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Save'),
    ));
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump(const Duration(milliseconds: 600));
    expect((await SharedPreferences.getInstance()).getString('cars'),
        contains('VW Polo'));
    _expectNoFlexOverflow(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
