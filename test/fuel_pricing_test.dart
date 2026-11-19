import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:gazol/fuel_pricing.dart';
import 'package:gazol/location_support.dart';
import 'package:gazol/settings_screen.dart';

const _beatForgePageFixture = '''
<p>South Africa Fuel Prices Inland - Petrol 93: R29.08 - Petrol 95: R30.24
- Diesel 50ppm: R31.60 - Diesel 500ppm: R30.85</p>
<p>Costal - Petrol 93: R29.87 - Petrol 95: R29.37
- Diesel 50ppm: R30.83 - Diesel 500ppm: R29.98</p>
<p>Last Updated: November 2026</p>
''';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('parses all four prices for Inland and misspelled Costal', () {
    final prices = parseBeatForgeFuelPrices(_beatForgePageFixture);

    expect(prices[FuelRegion.inland], {
      'fuel93': '29.08',
      'fuel95': '30.24',
      'diesel50': '31.60',
      'diesel500': '30.85',
    });
    expect(prices[FuelRegion.coastal], {
      'fuel93': '29.87',
      'fuel95': '29.37',
      'diesel50': '30.83',
      'diesel500': '29.98',
    });
  });

  test('rejects incomplete regional data without returning partial prices', () {
    expect(
      () => parseBeatForgeFuelPrices(
        '<p>Inland Petrol 93: R1.00</p><p>Coastal Petrol 93: R2.00</p>',
      ),
      throwsFormatException,
    );
  });

  test('legacy vehicle migration preserves profile fields and explicit types', () {
    final vehicles = <Map<String, dynamic>>[
      {'name': 'VW Polo', 'consumption': 6.4},
      {'name': 'Toyota Hilux', 'consumption': 9.2, 'fuelType': 'diesel500'},
    ];

    expect(migrateLegacyVehicleFuelTypes(vehicles, 'fuel95'), isTrue);
    expect(vehicles, [
      {'name': 'VW Polo', 'consumption': 6.4, 'fuelType': 'fuel95'},
      {'name': 'Toyota Hilux', 'consumption': 9.2, 'fuelType': 'diesel500'},
    ]);
  });

  test('vehicle switching saves and restores fuel type per vehicle', () async {
    final prefs = await SharedPreferences.getInstance();
    final vehicles = <Map<String, dynamic>>[
      {'name': 'VW Polo', 'consumption': 6.4},
      {'name': 'Toyota Hilux', 'consumption': 9.2},
    ];

    await persistActiveVehicleFuelType(prefs, vehicles, 'VW Polo', 'fuel95');
    await persistActiveVehicleFuelType(prefs, vehicles, 'Toyota Hilux', 'diesel50');
    await persistActiveVehicleFuelType(prefs, vehicles, 'VW Polo', 'fuel95');

    final savedVehicles = List<Map<String, dynamic>>.from(
      (json.decode(prefs.getString('cars')!) as List)
          .map((vehicle) => Map<String, dynamic>.from(vehicle as Map)),
    );
    expect(vehicleFuelType(savedVehicles[0]), 'fuel95');
    expect(vehicleFuelType(savedVehicles[1]), 'diesel50');
    expect(prefs.getString('last_selected_fuel'), 'fuel95');
  });

  test('regional price values and manual region preference remain separate', () async {
    final prefs = await SharedPreferences.getInstance();
    await saveRegionFuelPrices(prefs, FuelRegion.inland, {
      'fuel93': '1.00',
      'fuel95': '2.00',
      'diesel50': '3.00',
      'diesel500': '4.00',
    });
    await saveRegionFuelPrices(prefs, FuelRegion.coastal, {
      'fuel93': '5.00',
      'fuel95': '6.00',
      'diesel50': '7.00',
      'diesel500': '8.00',
    });
    await saveFuelRegion(prefs, FuelRegion.coastal);

    expect(storedFuelPrice(prefs, FuelRegion.inland, 'diesel50'), '3.00');
    expect(storedFuelPrice(prefs, FuelRegion.coastal, 'diesel50'), '7.00');
    expect(parseFuelRegion(prefs.getString('fuel_region')), FuelRegion.coastal);
  });

  test('denied location permission leaves manual region usable and unchanged',
      () async {
    SharedPreferences.setMockInitialValues({'fuel_region': 'coastal'});
    final prefs = await SharedPreferences.getInstance();
    var requestedPosition = false;

    final result = await lookupCurrentPositionSafely(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async => LocationPermission.deniedForever,
      getCurrentPosition: () async {
        requestedPosition = true;
        throw StateError('Position should not be requested after denial');
      },
    );

    expect(result.position, isNull);
    expect(result.serviceEnabled, isTrue);
    expect(requestedPosition, isFalse);
    expect(parseFuelRegion(prefs.getString('fuel_region')), FuelRegion.coastal);
  });

  testWidgets('Settings region selector persists a manual Coastal choice',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'lastFuelUpdate': DateTime.now().millisecondsSinceEpoch,
      regionalFuelPriceKey(FuelRegion.coastal, 'fuel93'): '5.00',
    });

    await tester.pumpWidget(MaterialApp(home: SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('fuel-region-coastal')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fuel_region'), 'coastal');
    expect(
      storedFuelPrice(prefs, FuelRegion.coastal, 'fuel93'),
      '5.00',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
