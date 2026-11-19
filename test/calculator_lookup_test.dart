import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart' show AdMessageCodec;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gazol/fuel_pricing.dart';
import 'package:gazol/main.dart';

final _adsChannel = MethodChannel(
  'plugins.flutter.io/google_mobile_ads',
  StandardMethodCodec(AdMessageCodec()),
);

http.Response _distanceResponse({
  String topStatus = 'OK',
  String elementStatus = 'OK',
  Object? meters = 10000,
}) {
  return http.Response(
    json.encode({
      'status': topStatus,
      'rows': [
        {
          'elements': [
            {
              'status': elementStatus,
              if (elementStatus == 'OK') 'distance': {'value': meters},
            },
          ],
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Future<void> _pumpCalculator(
  WidgetTester tester, {
  List<Map<String, dynamic>>? cars,
  String selectedCar = 'Test car',
  String selectedFuel = 'fuel95',
  FuelRegion region = FuelRegion.inland,
  Map<String, String>? prices,
}) async {
  final savedCars = cars ?? [
    {'name': 'Test car', 'consumption': 6.0, 'fuelType': 'fuel95'},
  ];
  SharedPreferences.setMockInitialValues({
    'cars': json.encode(savedCars),
    'last_selected_car': selectedCar,
    'last_selected_fuel': selectedFuel,
    'fuel_region': fuelRegionName(region),
    for (final entry in (prices ?? {'fuel95': '20.00'}).entries)
      regionalFuelPriceKey(region, entry.key): entry.value,
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_adsChannel.name, (message) async {
    _adsChannel.codec.decodeMethodCall(message!);
    return _adsChannel.codec.encodeSuccessEnvelope(null);
  });
  await tester.pumpWidget(MaterialApp(home: FuelScreen()));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_adsChannel.name, null);
  });

  testWidgets('Get calculates after a successful distance lookup',
      (tester) async {
    await _pumpCalculator(tester);
    await tester.enterText(_field('Destination'), 'Stellenbosch');
    var calls = 0;

    await http.runWithClient(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Get'));
      await tester.pumpAndSettle();
    }, () => MockClient((_) async {
          calls++;
          return _distanceResponse();
        }));

    expect(calls, 1);
    expect(find.text('Estimated Fuel Usage'), findsOneWidget);
    expect(find.text('0.60 L'), findsOneWidget);
    expect(find.text('One-way: R12.00'), findsOneWidget);
    expect(find.text('Return: R24.00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed lookup does not calculate and shows existing feedback',
      (tester) async {
    await _pumpCalculator(tester);
    await tester.enterText(_field('Destination'), 'Invalid destination');

    await http.runWithClient(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Get'));
      await tester.pumpAndSettle();
    }, () => MockClient((_) async => _distanceResponse(
          elementStatus: 'ZERO_RESULTS',
        )));

    expect(find.text('Estimated Fuel Usage'), findsNothing);
    expect(
      find.text('Destination not found. Please enter a valid location.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rapid Get taps issue only one request', (tester) async {
    await _pumpCalculator(tester);
    await tester.enterText(_field('Destination'), 'Stellenbosch');
    final response = Completer<http.Response>();
    var calls = 0;

    await http.runWithClient(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Get'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Get'));
      await tester.pump();
      expect(calls, 1);
      response.complete(_distanceResponse());
      await tester.pumpAndSettle();
    }, () => MockClient((_) {
          calls++;
          return response.future;
        }));

    expect(find.text('0.60 L'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual Calculate still calculates entered distance',
      (tester) async {
    await _pumpCalculator(tester);
    await tester.enterText(_field('Distance (km)'), '10');
    await tester.tap(find.text('CALCULATE'));
    await tester.pumpAndSettle();

    expect(find.text('0.60 L'), findsOneWidget);
    expect(find.text('One-way: R12.00'), findsOneWidget);
    expect(find.text('Return: R24.00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching vehicles recalculates using vehicle and regional fuel data',
      (tester) async {
    await _pumpCalculator(
      tester,
      cars: [
        {'name': 'VW Polo', 'consumption': 5.5, 'fuelType': 'fuel95'},
        {'name': 'Toyota Hilux', 'consumption': 9.2, 'fuelType': 'diesel500'},
      ],
      selectedCar: 'VW Polo',
      selectedFuel: 'fuel95',
      region: FuelRegion.coastal,
      prices: {
        'fuel95': '22.00',
        'diesel500': '35.00',
      },
    );
    await tester.enterText(_field('Destination'), 'Cape Town');

    await http.runWithClient(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Get'));
      await tester.pumpAndSettle();
    }, () => MockClient((_) async => _distanceResponse(meters: 100000)));

    expect(_field('Destination'), findsOneWidget);
    expect(_field('Distance (km)'), findsOneWidget);
    expect(find.text('100.0'), findsOneWidget);
    expect(find.text('5.50 L'), findsOneWidget);
    expect(find.text('One-way: R121.00'), findsOneWidget);

    await tester.ensureVisible(find.text('Toyota Hilux'));
    await tester.tap(find.text('Toyota Hilux'));
    await tester.pumpAndSettle();
    expect(find.text('Cape Town'), findsOneWidget);
    expect(find.text('100.0'), findsOneWidget);
    expect(find.text('9.20 L'), findsOneWidget);
    expect(find.text('One-way: R322.00'), findsOneWidget);
    expect(find.text('Return: R644.00'), findsOneWidget);

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_selected_car'), 'Toyota Hilux');
    expect(prefs.getString('last_selected_fuel'), 'diesel500');

    await tester.ensureVisible(find.text('VW Polo'));
    await tester.tap(find.text('VW Polo'));
    await tester.pumpAndSettle();
    expect(find.text('Cape Town'), findsOneWidget);
    expect(find.text('100.0'), findsOneWidget);
    expect(find.text('5.50 L'), findsOneWidget);
    expect(find.text('One-way: R121.00'), findsOneWidget);
    expect(find.text('Return: R242.00'), findsOneWidget);

    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_selected_car'), 'VW Polo');
    expect(prefs.getString('last_selected_fuel'), 'fuel95');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid vehicle consumption clears estimate but keeps trip',
      (tester) async {
    await _pumpCalculator(
      tester,
      cars: [
        {'name': 'Valid car', 'consumption': 6.0, 'fuelType': 'fuel95'},
        {'name': 'Incomplete car', 'consumption': 'unknown', 'fuelType': 'diesel50'},
      ],
      selectedCar: 'Valid car',
      selectedFuel: 'fuel95',
      prices: {'fuel95': '20.00', 'diesel50': '25.00'},
    );
    await tester.enterText(_field('Destination'), 'Durban');
    await http.runWithClient(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Get'));
      await tester.pumpAndSettle();
    }, () => MockClient((_) async => _distanceResponse(meters: 10000)));
    expect(find.text('0.60 L'), findsOneWidget);

    await tester.ensureVisible(find.text('Incomplete car'));
    await tester.tap(find.text('Incomplete car'));
    await tester.pumpAndSettle();
    expect(find.text('Estimated Fuel Usage'), findsNothing);
    expect(find.text('Durban'), findsOneWidget);
    expect(find.text('10.0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
