import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

enum FuelRegion { inland, coastal }

const Map<String, String> fuelTypeLabels = {
  'fuel93': 'Petrol 93',
  'fuel95': 'Petrol 95',
  'diesel50': 'Diesel 50ppm',
  'diesel500': 'Diesel 500ppm',
};

String fuelRegionName(FuelRegion region) => region.name;

Future<void> saveFuelRegion(SharedPreferences prefs, FuelRegion region) =>
    prefs.setString('fuel_region', fuelRegionName(region));

FuelRegion parseFuelRegion(String? value) {
  return value?.toLowerCase() == 'coastal'
      ? FuelRegion.coastal
      : FuelRegion.inland;
}

String regionalFuelPriceKey(FuelRegion region, String fuelType) =>
    'fuel_price_${fuelRegionName(region)}_$fuelType';

String storedFuelPrice(SharedPreferences prefs, FuelRegion region, String fuelType) {
  final regional = prefs.getString(regionalFuelPriceKey(region, fuelType));
  if (regional != null && regional.isNotEmpty) return regional;
  if (region == FuelRegion.inland && fuelType != 'diesel500') {
    return prefs.getString(fuelType) ?? '';
  }
  return '';
}

Future<void> saveRegionFuelPrices(
  SharedPreferences prefs,
  FuelRegion region,
  Map<String, String> prices,
) async {
  for (final fuelType in fuelTypeLabels.keys) {
    final price = prices[fuelType];
    if (price == null) {
      throw FormatException('Missing ${fuelTypeLabels[fuelType]} price.');
    }
    await prefs.setString(regionalFuelPriceKey(region, fuelType), price);
    // Keep the original keys in sync with Inland for older saved installs.
    if (region == FuelRegion.inland && fuelType != 'diesel500') {
      await prefs.setString(fuelType, price);
    }
  }
}

Future<void> saveAllRegionalFuelPrices(
  SharedPreferences prefs,
  Map<FuelRegion, Map<String, String>> prices,
) async {
  for (final region in FuelRegion.values) {
    final regionPrices = prices[region];
    if (regionPrices == null) {
      throw FormatException('Missing ${fuelRegionName(region)} fuel prices.');
    }
    await saveRegionFuelPrices(prefs, region, regionPrices);
  }
}

String? normalizeFuelType(Object? value) {
  return value is String && fuelTypeLabels.containsKey(value) ? value : null;
}

String? vehicleFuelType(Map<String, dynamic> vehicle) =>
    normalizeFuelType(vehicle['fuelType']);

/// Copies the previous app-wide fuel selection into legacy vehicle records
/// that do not yet have a per-vehicle fuel type. Other vehicle fields remain
/// untouched.
bool migrateLegacyVehicleFuelTypes(
  List<Map<String, dynamic>> vehicles,
  Object? legacyFuelType,
) {
  final fuelType = normalizeFuelType(legacyFuelType);
  if (fuelType == null) return false;

  var changed = false;
  for (final vehicle in vehicles) {
    if (vehicleFuelType(vehicle) == null) {
      vehicle['fuelType'] = fuelType;
      changed = true;
    }
  }
  return changed;
}

bool setVehicleFuelType(
  List<Map<String, dynamic>> vehicles,
  String? vehicleName,
  String fuelType,
) {
  if (vehicleName == null || normalizeFuelType(fuelType) == null) return false;
  final vehicle = vehicles.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['name'] == vehicleName,
        orElse: () => null,
      );
  if (vehicle == null) return false;
  vehicle['fuelType'] = fuelType;
  return true;
}

Future<void> persistActiveVehicleFuelType(
  SharedPreferences prefs,
  List<Map<String, dynamic>> vehicles,
  String? activeVehicleName,
  String? fuelType,
) async {
  final normalized = normalizeFuelType(fuelType);
  if (normalized == null) {
    await prefs.remove('last_selected_fuel');
    return;
  }

  await prefs.setString('last_selected_fuel', normalized);
  setVehicleFuelType(vehicles, activeVehicleName, normalized);
  await prefs.setString('cars', json.encode(vehicles));
}

/// Parses all eight prices from BeatForge's existing regional price page.
/// The page has historically misspelled Coastal as "Costal"; both are accepted.
/// A partial or changed page fails as a whole so incomplete prices are never
/// persisted over previously saved values.
Map<FuelRegion, Map<String, String>> parseBeatForgeFuelPrices(String source) {
  final text = (html_parser.parseFragment(source).text ?? '')
      .replaceAll('\u00a0', ' ');
  final regionMarkers = RegExp(
    r'\b(inland|coastal|costal)\b',
    caseSensitive: false,
  ).allMatches(text).toList();
  final result = <FuelRegion, Map<String, String>>{};

  for (var i = 0; i < regionMarkers.length; i++) {
    final marker = regionMarkers[i];
    final label = marker.group(1)!.toLowerCase();
    final region = label == 'inland' ? FuelRegion.inland : FuelRegion.coastal;
    if (result.containsKey(region)) continue;

    final nextMarker = regionMarkers.skip(i + 1).firstWhere(
          (candidate) =>
              (candidate.group(1)!.toLowerCase() == 'inland') !=
              (region == FuelRegion.inland),
          orElse: () => marker,
        );
    final end = identical(nextMarker, marker) ? text.length : nextMarker.start;
    final section = text.substring(marker.end, end);
    final prices = <String, String>{};

    for (final fuelType in fuelTypeLabels.keys) {
      final priceMatch = _pricePattern(fuelType).firstMatch(section);
      if (priceMatch != null) prices[fuelType] = priceMatch.group(1)!;
    }

    if (prices.length == fuelTypeLabels.length) {
      result[region] = prices;
    }
  }

  if (result.length != FuelRegion.values.length) {
    throw const FormatException(
      'BeatForge page did not contain all four fuel prices for both regions.',
    );
  }
  return result;
}

RegExp _pricePattern(String fuelType) {
  final label = switch (fuelType) {
    'fuel93' => r'petrol\s*93',
    'fuel95' => r'petrol\s*95',
    'diesel50' => r'diesel\s*50\s*ppm',
    'diesel500' => r'diesel\s*500\s*ppm',
    _ => throw ArgumentError.value(fuelType, 'fuelType'),
  };
  return RegExp(r'$label\s*:\s*r\s*([0-9]+(?:\.[0-9]+)?)'
      .replaceFirst(r'$label', label),
      caseSensitive: false);
}
