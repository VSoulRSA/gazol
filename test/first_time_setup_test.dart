import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart' show AdMessageCodec;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gazol/main.dart';

final _adsChannel = MethodChannel(
  'plugins.flutter.io/google_mobile_ads',
  StandardMethodCodec(AdMessageCodec()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_adsChannel.name, null);
  });

  testWidgets('first-time fuel prompt persists the selected fuel type',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'cars': json.encode([
        {'name': 'VW Polo', 'consumption': 6.4},
      ]),
      'last_selected_car': 'VW Polo',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_adsChannel.name, (message) async {
      _adsChannel.codec.decodeMethodCall(message!);
      return _adsChannel.codec.encodeSuccessEnvelope(null);
    });

    await tester.pumpWidget(MaterialApp(home: FuelScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Choose your fuel type'), findsOneWidget);
    await tester.tap(find.text('Petrol 93').last);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_selected_fuel'), 'fuel93');
    final cars = List<Map<String, dynamic>>.from(
      (json.decode(prefs.getString('cars')!) as List)
          .map((car) => Map<String, dynamic>.from(car as Map)),
    );
    expect(cars.single['fuelType'], 'fuel93');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
