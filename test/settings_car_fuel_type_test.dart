import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart' show AdMessageCodec;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gazol/fuel_pricing.dart';
import 'package:gazol/main.dart';
import 'package:gazol/settings_screen.dart';

final _adsChannel = MethodChannel(
  'plugins.flutter.io/google_mobile_ads',
  StandardMethodCodec(AdMessageCodec()),
);

Finder _field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

void _mockAdsChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_adsChannel.name, (message) async {
    _adsChannel.codec.decodeMethodCall(message!);
    return _adsChannel.codec.encodeSuccessEnvelope(null);
  });
}

Future<void> _openSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(home: SettingsScreen()));
  _consumeKnownListTileDiagnostic(tester);
  await tester.pump(const Duration(milliseconds: 100));
  _consumeKnownListTileDiagnostic(tester);
}

void _consumeKnownListTileDiagnostic(WidgetTester tester) {
  final error = tester.takeException();
  if (error != null &&
      !error.toString().contains('ListTile background color or ink splashes')) {
    throw error;
  }
}

void _ignoreKnownListTileDiagnosticForTest() {
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains(
      'ListTile background color or ink splashes may be invisible',
    )) {
      return;
    }
    previousHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousHandler);
}

Future<void> _openAddCar(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add));
  await tester.pump(const Duration(milliseconds: 300));
  _consumeKnownListTileDiagnostic(tester);
  expect(find.byKey(const ValueKey('add-car-fuel-type')), findsOneWidget);
}

Future<void> _chooseFuel(
  WidgetTester tester,
  String key,
  String label,
) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump(const Duration(milliseconds: 250));
  _consumeKnownListTileDiagnostic(tester);
  expect(find.text(label), findsWidgets);
  await tester.tap(find.text(label).last);
  await tester.pump(const Duration(milliseconds: 150));
  _consumeKnownListTileDiagnostic(tester);
}

Future<void> _saveDialog(WidgetTester tester) async {
  await tester.tap(find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(ElevatedButton, 'Save'),
  ));
  await tester.pump(const Duration(milliseconds: 500));
  _consumeKnownListTileDiagnostic(tester);
}

List<Map<String, dynamic>> _savedCars(SharedPreferences prefs) =>
    List<Map<String, dynamic>>.from(
      (json.decode(prefs.getString('cars')!) as List)
          .map((car) => Map<String, dynamic>.from(car as Map)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_adsChannel.name, null);
  });

  testWidgets('Add Car saves Petrol 95 and Diesel 500ppm per vehicle',
      (tester) async {
    _ignoreKnownListTileDiagnosticForTest();
    SharedPreferences.setMockInitialValues({
      'lastFuelUpdate': DateTime.now().millisecondsSinceEpoch,
      'last_selected_car': 'Existing car',
      'last_selected_fuel': 'fuel95',
      'cars': json.encode([
        {'name': 'Existing car', 'consumption': 6.0, 'fuelType': 'fuel95'},
      ]),
    });

    await _openSettings(tester);
    await _openAddCar(tester);
    await tester.enterText(_field('Car Name'), 'VW Polo');
    await tester.enterText(_field('Fuel Consumption (L/100km)'), '5.5');
    await _chooseFuel(tester, 'add-car-fuel-type', 'Petrol 95');
    await _saveDialog(tester);

    var prefs = await SharedPreferences.getInstance();
    var cars = _savedCars(prefs);
    expect(vehicleFuelType(cars[0]), 'fuel95');
    expect(vehicleFuelType(cars[1]), 'fuel95');

    await _openAddCar(tester);
    await tester.enterText(_field('Car Name'), 'Toyota Hilux');
    await tester.enterText(_field('Fuel Consumption (L/100km)'), '9.2');
    await _chooseFuel(tester, 'add-car-fuel-type', 'Diesel 500ppm');
    await _saveDialog(tester);

    prefs = await SharedPreferences.getInstance();
    cars = _savedCars(prefs);
    expect(cars.map((car) => car['name']), [
      'Existing car',
      'VW Polo',
      'Toyota Hilux',
    ]);
    expect(vehicleFuelType(cars[1]), 'fuel95');
    expect(vehicleFuelType(cars[2]), 'diesel500');
    expect(prefs.getString('last_selected_fuel'), 'fuel95');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Edit Car shows saved type and updates the active vehicle type',
      (tester) async {
    _ignoreKnownListTileDiagnosticForTest();
    SharedPreferences.setMockInitialValues({
      'lastFuelUpdate': DateTime.now().millisecondsSinceEpoch,
      'last_selected_car': 'Toyota Hilux',
      'last_selected_fuel': 'diesel500',
      'cars': json.encode([
        {'name': 'VW Polo', 'consumption': 5.5, 'fuelType': 'fuel95'},
        {'name': 'Toyota Hilux', 'consumption': 9.2, 'fuelType': 'diesel500'},
      ]),
    });

    await _openSettings(tester);
    await tester.tap(find.text('Toyota Hilux — 9.2 L/100km'));
    await tester.pump(const Duration(milliseconds: 250));
    _consumeKnownListTileDiagnostic(tester);

    final selector = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('edit-car-fuel-type')),
    );
    expect(selector.initialValue, 'diesel500');
    await _chooseFuel(tester, 'edit-car-fuel-type', 'Diesel 50ppm');
    await _saveDialog(tester);

    final prefs = await SharedPreferences.getInstance();
    final cars = _savedCars(prefs);
    expect(vehicleFuelType(cars[0]), 'fuel95');
    expect(vehicleFuelType(cars[1]), 'diesel50');
    expect(prefs.getString('last_selected_fuel'), 'diesel50');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Editing an inactive car does not overwrite active fuel choice',
      (tester) async {
    _ignoreKnownListTileDiagnosticForTest();
    SharedPreferences.setMockInitialValues({
      'lastFuelUpdate': DateTime.now().millisecondsSinceEpoch,
      'last_selected_car': 'VW Polo',
      'last_selected_fuel': 'fuel95',
      'cars': json.encode([
        {'name': 'VW Polo', 'consumption': 5.5, 'fuelType': 'fuel95'},
        {'name': 'Toyota Hilux', 'consumption': 9.2, 'fuelType': 'diesel500'},
      ]),
    });

    await _openSettings(tester);
    await tester.tap(find.text('Toyota Hilux — 9.2 L/100km'));
    await tester.pump(const Duration(milliseconds: 250));
    _consumeKnownListTileDiagnostic(tester);
    await _chooseFuel(tester, 'edit-car-fuel-type', 'Petrol 93');
    await _saveDialog(tester);

    final prefs = await SharedPreferences.getInstance();
    final cars = _savedCars(prefs);
    expect(vehicleFuelType(cars[0]), 'fuel95');
    expect(vehicleFuelType(cars[1]), 'fuel93');
    expect(prefs.getString('last_selected_fuel'), 'fuel95');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('region switching does not change vehicle fuel preference',
      (tester) async {
    _ignoreKnownListTileDiagnosticForTest();
    SharedPreferences.setMockInitialValues({
      'lastFuelUpdate': DateTime.now().millisecondsSinceEpoch,
      'last_selected_car': 'Toyota Hilux',
      'last_selected_fuel': 'diesel500',
      'cars': json.encode([
        {'name': 'Toyota Hilux', 'consumption': 9.2, 'fuelType': 'diesel500'},
      ]),
      regionalFuelPriceKey(FuelRegion.inland, 'diesel500'): '30.00',
      regionalFuelPriceKey(FuelRegion.coastal, 'diesel500'): '31.00',
    });

    await _openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('fuel-region-coastal')));
    await tester.pump(const Duration(milliseconds: 200));
    _consumeKnownListTileDiagnostic(tester);
    await tester.pump(const Duration(milliseconds: 200));
    _consumeKnownListTileDiagnostic(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(parseFuelRegion(prefs.getString('fuel_region')), FuelRegion.coastal);
    expect(vehicleFuelType(_savedCars(prefs).single), 'diesel500');
    expect(prefs.getString('last_selected_fuel'), 'diesel500');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('calculator restores active vehicle fuel and price after reload',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'cars': json.encode([
        {'name': 'VW Polo', 'consumption': 5.5, 'fuelType': 'fuel95'},
        {'name': 'Toyota Hilux', 'consumption': 9.2, 'fuelType': 'diesel500'},
      ]),
      'last_selected_car': 'Toyota Hilux',
      'last_selected_fuel': 'fuel95',
      'fuel_region': 'inland',
      regionalFuelPriceKey(FuelRegion.inland, 'fuel95'): '20.00',
      regionalFuelPriceKey(FuelRegion.inland, 'diesel500'): '30.50',
    });
    _mockAdsChannel();

    await tester.pumpWidget(MaterialApp(home: FuelScreen()));
    await tester.pump(const Duration(milliseconds: 800));

    final priceField = tester.widget<TextField>(_field('Fuel Price (Auto)'));
    expect(priceField.controller?.text, '30.50');
    expect(find.text('Toyota Hilux'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final cars = _savedCars(prefs);
    expect(vehicleFuelType(cars[1]), 'diesel500');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
