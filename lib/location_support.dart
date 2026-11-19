import 'package:geolocator/geolocator.dart';

class LocationLookupResult {
  const LocationLookupResult({
    required this.serviceEnabled,
    this.position,
  });

  final bool? serviceEnabled;
  final Position? position;
}

Future<LocationLookupResult> lookupCurrentPositionSafely({
  required Future<bool> Function() isServiceEnabled,
  required Future<LocationPermission> Function() checkPermission,
  required Future<LocationPermission> Function() requestPermission,
  required Future<Position> Function() getCurrentPosition,
}) async {
  bool? serviceEnabled;
  try {
    serviceEnabled = await isServiceEnabled();
    if (!serviceEnabled) {
      return const LocationLookupResult(serviceEnabled: false);
    }

    var permission = await checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const LocationLookupResult(serviceEnabled: true);
    }

    return LocationLookupResult(
      serviceEnabled: true,
      position: await getCurrentPosition(),
    );
  } catch (_) {
    return LocationLookupResult(serviceEnabled: serviceEnabled);
  }
}
