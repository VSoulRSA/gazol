import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gazol/http_text.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('decodes UTF-8 text when the HTTP charset is omitted', () {
    const text = 'Gqeberha \u2013 Stellenbosch \u2014 KwaZulu-Natal';
    final response = http.Response.bytes(
      utf8.encode(text),
      200,
      headers: {'content-type': 'text/html'},
    );

    expect(decodeHttpResponseBody(response), text);
  });

  test('honors a declared response charset', () {
    final response = http.Response.bytes(
      latin1.encode('Caf\u00e9'),
      200,
      headers: {'content-type': 'text/plain; charset=iso-8859-1'},
    );

    expect(decodeHttpResponseBody(response), 'Caf\u00e9');
  });

  test('SharedPreferences preserves vehicle names and special characters',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final vehicles = [
      {'name': 'Audi A1 \u2013 5.5 L/100km', 'consumption': 5.5},
      {'name': 'Renault Duster \u2014 Caf\u00e9 Zo\u00eb', 'consumption': 6.9},
      {'name': 'Toyota Hilux \u2013 Gqeberha, KwaZulu-Natal', 'consumption': 8.4},
      {'name': 'VW Polo ASCII', 'consumption': 5.8},
    ];

    await prefs.setString('cars', json.encode(vehicles));
    final restored = List<Map<String, dynamic>>.from(
      (json.decode(prefs.getString('cars')!) as List)
          .map((vehicle) => Map<String, dynamic>.from(vehicle as Map)),
    );

    expect(restored, vehicles);
  });
}
