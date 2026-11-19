// App imports.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';

import 'splash_screen.dart';
import 'secrets.dart';
import 'settings_screen.dart';
import 'onboarding_screen.dart';
import 'fuel_pricing.dart';
import 'location_support.dart';
import 'http_text.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const GazolApp());
}

class GazolApp extends StatelessWidget {
  const GazolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        primaryColor: const Color(0xFFFF8C32),
      ),
      home: const LaunchGate(), // Select onboarding or the main app
    );
  }
}

/// Chooses onboarding or the calculator screen.
class LaunchGate extends StatelessWidget {
  const LaunchGate({super.key});

  Future<bool> _needsOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool("onboarding_complete") ?? false;

    final carsJson = prefs.getString("cars");
    bool hasCar = false;
    if (carsJson != null) {
      final list = json.decode(carsJson);
      hasCar = list is List && list.isNotEmpty;
    }

    return !(done && hasCar);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _needsOnboarding(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8C32)),
            ),
          );
        }

        // Show onboarding if this is a first launch or no vehicle exists.
        if (snapshot.data == true) return const OnboardingScreen();

        // Otherwise, continue through the splash screen.
        return SplashScreen();
      },
    );
  }
}

// Background pattern.
class GazolWallpaper extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    const style = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Color.fromARGB(18, 255, 255, 255),
      letterSpacing: 2,
    );
    const word = "GAZOL";
    const sx = 80.0;
    const sy = 28.0;

    for (double y = 0; y < size.height; y += sy) {
      for (double x = 0; x < size.width; x += sx) {
        tp.text = const TextSpan(text: word, style: style);
        tp.layout();
        tp.paint(canvas, Offset(x, y));
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}


// FuelScreen.

class FuelScreen extends StatefulWidget {
  @override
  _FuelScreenState createState() => _FuelScreenState();
}

class _FuelScreenState extends State<FuelScreen>
    with SingleTickerProviderStateMixin {
  final destinationCtrl = TextEditingController();
  final distanceCtrl = TextEditingController();
  final fuelCtrl = TextEditingController();
  final priceCtrl = TextEditingController();

  List<Map<String, dynamic>> cars = [];
  String? selectedCar;
  String? selectedFuel;
  FuelRegion selectedRegion = FuelRegion.inland;
  bool _isShowingFirstFuelPrompt = false;
  bool _isFetchingDistance = false;
  bool _hasValidTripDistance = false;

  // current coordinates for map use
  double? currentLat;
  double? currentLng;

  String locationText = "Locating...";
  double? litres, oneWay, returnCost;

  BannerAd? bannerAd;
  late AnimationController fadeCtrl;

  @override
  void initState() {
    super.initState();
    fadeCtrl =
    AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();

    bannerAd = BannerAd(
      adUnitId: "ca-app-pub-6307184524524548/7751970611",
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(onAdLoaded: (_) => setState(() {})),
    )..load();

    loadCars();
    getLocation();
  }

  /// loads cars AND restores previous selections (car + fuel) if present
  Future<void> loadCars() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString("cars");
    cars = saved != null
        ? List<Map<String, dynamic>>.from(json.decode(saved))
        : [];
    selectedRegion = parseFuelRegion(prefs.getString("fuel_region"));

    final savedCar = prefs.getString("last_selected_car");
    final savedFuel = prefs.getString("last_selected_fuel");
    if (migrateLegacyVehicleFuelTypes(cars, savedFuel)) {
      await prefs.setString("cars", json.encode(cars));
    }

    if (savedCar != null && savedCar.isNotEmpty &&
        cars.any((car) => car["name"] == savedCar)) {
      selectedCar = savedCar;
      final car = cars.firstWhere((item) => item["name"] == savedCar);
      fuelCtrl.text = car["consumption"].toString();
    } else {
      selectedCar = null;
      if (savedCar != null) await prefs.remove("last_selected_car");
    }

    final activeCars = cars.where((car) => car["name"] == selectedCar);
    selectedFuel = activeCars.isNotEmpty
        ? vehicleFuelType(activeCars.first) ?? normalizeFuelType(savedFuel)
        : normalizeFuelType(savedFuel);
    priceCtrl.text = selectedFuel == null
        ? ""
        : storedFuelPrice(prefs, selectedRegion, selectedFuel!);

    if (!mounted) return;
    setState(() {});
    if (selectedFuel == null) await _showFirstFuelPrompt();
  }

  Future<void> _showFirstFuelPrompt() async {
    if (!mounted || selectedFuel != null || _isShowingFirstFuelPrompt) return;

    _isShowingFirstFuelPrompt = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              "Choose your fuel type",
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Select the fuel type to use in the calculator. You can change it anytime.",
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                _firstFuelChoice(dialogContext, "Petrol 93", "fuel93"),
                _firstFuelChoice(dialogContext, "Petrol 95", "fuel95"),
                _firstFuelChoice(dialogContext, "Diesel 50ppm", "diesel50"),
                _firstFuelChoice(dialogContext, "Diesel 500ppm", "diesel500"),
              ],
            ),
          ),
        ),
      );
    } finally {
      _isShowingFirstFuelPrompt = false;
    }
  }

  Widget _firstFuelChoice(
    BuildContext dialogContext,
    String label,
    String fuelKey,
  ) {
    return TextButton(
      onPressed: () async {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        final price = storedFuelPrice(prefs, selectedRegion, fuelKey);

        setState(() {
          selectedFuel = fuelKey;
          priceCtrl.text = price;
        });
        await _saveSelectedFuel(fuelKey);
        _recalculateForSelectedVehicleIfReady();
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
      },
      child: Text(label, style: const TextStyle(color: Color(0xFFFF8C32))),
    );
  }

  // helper: persist chosen car name
  Future<void> _saveSelectedCar(String? carName) async {
    final prefs = await SharedPreferences.getInstance();
    if (carName == null) {
      await prefs.remove("last_selected_car");
    } else {
      await prefs.setString("last_selected_car", carName);
    }
  }

  // helper: persist chosen fuel key
  Future<void> _saveSelectedFuel(String? fuelKey) async {
    final prefs = await SharedPreferences.getInstance();
    await persistActiveVehicleFuelType(prefs, cars, selectedCar, fuelKey);
  }

  // LOCATION (stores coordinates)
  Future<void> getLocation() async {
    final result = await lookupCurrentPositionSafely(
      isServiceEnabled: Geolocator.isLocationServiceEnabled,
      checkPermission: Geolocator.checkPermission,
      requestPermission: Geolocator.requestPermission,
      getCurrentPosition: Geolocator.getCurrentPosition,
    );
    final position = result.position;
    if (position == null) {
      if (mounted) {
        setState(() => locationText = result.serviceEnabled == false
            ? "GPS Off"
            : "Location unavailable");
      }
      return;
    }

    currentLat = position.latitude;
    currentLng = position.longitude;
    try {
      final places = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final place = places.isEmpty ? null : places.first;
      final parts = [
        place?.locality,
        place?.administrativeArea,
        place?.country,
      ].where((value) => value != null && value.trim().isNotEmpty)
          .map((value) => value!)
          .toList();
      if (mounted) {
        setState(() => locationText = parts.isEmpty
            ? "Location unavailable"
            : parts.join(", "));
      }
    } catch (_) {
      if (mounted) setState(() => locationText = "Location unavailable");
    }
  }

  Future<void> fetchDistance() async {
    if (_isFetchingDistance || destinationCtrl.text.trim().isEmpty) return;

    _isFetchingDistance = true;
    _hasValidTripDistance = false;
    // Hide any prior estimate while this destination is being verified.
    setState(() {
      litres = null;
      oneWay = null;
      returnCost = null;
    });
    try {
      final uri = Uri.https(
        "maps.googleapis.com",
        "/maps/api/distancematrix/json",
        {
          "origins": locationText,
          "destinations": destinationCtrl.text.trim(),
          "mode": "driving",
          "key": googleApiKey,
        },
      );

      final res = await http.get(uri);
      if (res.statusCode != 200) {
        throw const FormatException("Distance lookup failed");
      }
      final data = json.decode(decodeHttpResponseBody(res));
      if (!mounted) return;
      if (data["status"] != "OK") {
        throw const FormatException("Distance lookup failed");
      }

      final element = data["rows"][0]["elements"][0];
      if (element["status"] != "OK") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Destination not found. Please enter a valid location.",
            ),
          ),
        );
        return;
      }

      final meters = element["distance"]["value"];
      if (meters is! num || !meters.isFinite || meters <= 0) {
        throw const FormatException("Invalid distance");
      }

      if (!mounted) return;
      distanceCtrl.text = (meters / 1000).toStringAsFixed(1);
      calculate();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not verify destination. Try again."),
        ),
      );
    } finally {
      _isFetchingDistance = false;
    }
  }

  // Opens maps app or fallback to web maps
  Future<void> _openMap() async {
    // if we don't have coordinates, try to notify user
    if (currentLat == null || currentLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Current location not available yet.")),
      );
      return;
    }

    final lat = currentLat!;
    final lng = currentLng!;
    final destText = destinationCtrl.text.trim();

    // If user provided a destination, prefer showing directions
    if (destText.isNotEmpty) {
      final encodedDest = Uri.encodeComponent(destText);

      // Try to open Google Maps app with origin coords and destination
      final googleAppUri = Uri.parse("google.navigation:q=$encodedDest");
      if (await canLaunchUrl(googleAppUri)) {
        await launchUrl(googleAppUri, mode: LaunchMode.externalApplication);
        return;
      }

      // Fallback: open browser with origin & destination specified
      final fallback = Uri.parse("https://www.google.com/maps/dir/?api=1&origin=$lat,$lng&destination=$encodedDest");
      if (await canLaunchUrl(fallback)) {
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
        return;
      }

      // last resort: open destination search only
      final search = Uri.parse("https://www.google.com/maps/search/?api=1&query=$encodedDest");
      if (await canLaunchUrl(search)) {
        await launchUrl(search, mode: LaunchMode.externalApplication);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open map app.")),
      );
      return;
    }

    // No destination was provided; center the map on current coordinates.
    // Try geo: scheme (Android) or Google Maps app
    final geoUri = Uri.parse("geo:$lat,$lng?q=$lat,$lng");
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      return;
    }

    final mapsWeb = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    if (await canLaunchUrl(mapsWeb)) {
      await launchUrl(mapsWeb, mode: LaunchMode.externalApplication);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Could not open map app.")),
    );
  }

  // Calculator calculations.
  void calculate({bool showValidationErrors = true}) {
    final d = double.tryParse(distanceCtrl.text.replaceAll(',', '.'),);
    final f = double.tryParse(fuelCtrl.text.replaceAll(',', '.'),);
    final p = double.tryParse(priceCtrl.text.replaceAll(',', '.'),);
    _hasValidTripDistance = d != null && d.isFinite && d > 0;

    String? validationMessage;
    if (!_hasValidTripDistance) {
      validationMessage = "Please enter a valid distance (km)";
    } else if (f == null || !f.isFinite || f <= 0) {
      validationMessage = "Please enter a valid fuel consumption";
    } else if (p == null || !p.isFinite || p <= 0) {
      validationMessage = "Please select a fuel type & set prices";
    }

    if (validationMessage != null) {
      _clearTripEstimate();
      if (showValidationErrors) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(validationMessage)));
      }
      return;
    }

    litres = (d! / 100) * f!;
    oneWay = litres! * p!;
    returnCost = oneWay! * 2;
    setState(() {});
  }

  void _clearTripEstimate() {
    litres = null;
    oneWay = null;
    returnCost = null;
    if (mounted) setState(() {});
  }

  void _recalculateForSelectedVehicleIfReady() {
    if (_hasValidTripDistance) {
      calculate(showValidationErrors: false);
    }
  }

  // Trip launcher.
  Future<void> startTrip() async {
    if (destinationCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Enter a destination first")));
      return;
    }

    String dest = Uri.encodeComponent(destinationCtrl.text);

    Future<void> openUrl(Uri uri) async {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("App not found, using Google Maps...")));
        final Uri fallback =
        Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$dest");
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape:
      const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          const Text("Start trip using:", style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 10),
          tripButton("Google Maps", () async {
            await openUrl(Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$dest"));
          }),
          tripButton("Waze", () async {
            final wazeUri = Uri.parse("waze://?q=$dest&navigate=yes");

            if (await canLaunchUrl(wazeUri)) {
              await launchUrl(
                wazeUri,
                mode: LaunchMode.externalApplication,
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Waze is not installed")),
              );
            }
          }),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
            tripButton("Apple Maps", () async {
              await openUrl(Uri.parse("http://maps.apple.com/?daddr=$dest"));
            }),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // Action buttons.
  Widget tripButton(String title, VoidCallback action) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF8C32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onPressed: () {
          Navigator.pop(context);
          action();
        },
        child: Center(
            child: Text(title, style: const TextStyle(color: Colors.black))),
      ),
    );
  }

  InputDecoration boxInput(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white54),
    filled: true,
    fillColor: const Color(0xFF111111),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFFF8C32), width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );

  // Fuel selection chip.
  Widget fuelChip(String label, String key) {
    final bool isSelected = selectedFuel == key;
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        final price = storedFuelPrice(prefs, selectedRegion, key);
        if (price.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please enter fuel prices in Settings first")),
          );
          return;
        }
        setState(() {
          selectedFuel = key;
          priceCtrl.text = price;
        });
        await _saveSelectedFuel(key);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF8C32) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFA866) : const Color(0xFF3A3A3A),
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: GazolWallpaper())),

        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: FadeTransition(
              opacity: fadeCtrl,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () async {
                          await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => SettingsScreen()));
                          // reload cars (this will also re-apply saved selections)
                          await loadCars();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.settings, color: Colors.white70),
                        ),
                      ),
                    ),

                    const SizedBox(height: 0),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo
                        Image.asset(
                          "assets/images/gazol_logo.png",
                          height: 70,
                        ),

                        const SizedBox(width: 10),

                        // Texts
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Fuel Trip Calculator",
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "📍 $locationText",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFFA866),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Destination row (Destination field + Get button)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: destinationCtrl,
                            keyboardType: TextInputType.text,
                            style: const TextStyle(color: Colors.white),
                            decoration: boxInput("Destination").copyWith(
                              suffixIcon: currentLat != null && currentLng != null
                                  ? IconButton(
                                onPressed: _openMap,
                                icon: const Icon(
                                  Icons.map,
                                  color: Color(0xFFFF8C32),
                                ),
                              )
                                  : null,
                            ),
                          ),
                        ),

                        const SizedBox(width: 6),

                        ElevatedButton(
                          onPressed: fetchDistance,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8C32),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: const Text(
                            "Get",
                            style: TextStyle(color: Colors.black),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    const Text("Select Car:", style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),

                    Wrap(
                      spacing: 8,
                      children: cars.map((car) {
                        final sel = selectedCar == car["name"];
                        return GestureDetector(
                          onTap: () async {
                            final prefs = await SharedPreferences.getInstance();
                            if (!mounted) return;
                            final nextFuel = vehicleFuelType(car);
                            setState(() {
                              selectedCar = car["name"];
                              fuelCtrl.text = car["consumption"]?.toString() ?? "";
                              selectedFuel = nextFuel;
                              priceCtrl.text = nextFuel == null
                                  ? ""
                                  : storedFuelPrice(prefs, selectedRegion, nextFuel);
                            });
                            _recalculateForSelectedVehicleIfReady();
                            await _saveSelectedCar(selectedCar);
                            if (nextFuel == null) {
                              await _saveSelectedFuel(null);
                              await _showFirstFuelPrompt();
                            } else {
                              await _saveSelectedFuel(nextFuel);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: sel ? const Color(0xFFFF8C32) : const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel ? const Color(0xFFFFA866) : const Color(0xFF3A3A3A),
                                width: sel ? 1.6 : 1,
                              ),
                            ),
                            child: Text(
                              car["name"],
                              style: TextStyle(
                                  color: sel ? Colors.black : Colors.white70, fontSize: 12),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: distanceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white),
                            decoration: boxInput("Distance (km)"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: fuelCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white),
                            decoration: boxInput("Fuel (L/100km)"),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    const Text("Fuel Type:", style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),

                    Wrap(
                      spacing: 8,
                      children: [
                        fuelChip("Petrol 95", "fuel95"),
                        fuelChip("Petrol 93", "fuel93"),
                        fuelChip("Diesel 50ppm", "diesel50"),
                        fuelChip("Diesel 500ppm", "diesel500"),
                      ],
                    ),

                    const SizedBox(height: 10),
                    TextField(
                        controller: priceCtrl,
                        readOnly: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: boxInput("Fuel Price (Auto)")),
                    const SizedBox(height: 12),

                    ElevatedButton(
                      onPressed: calculate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("CALCULATE",
                          style: TextStyle(
                              color: Colors.black, fontWeight: FontWeight.bold)),
                    ),

                    const SizedBox(height: 10),

                    // ---------- BIGGER, BOLDER, CENTERED RESULTS ----------
                    if (litres != null)
                      Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF1B1B1B)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
              Column(
                children: [
                  const Text(
                    "Estimated Fuel Usage",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white60,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    "${litres!.toStringAsFixed(2)} L",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
                                const SizedBox(height: 6),
                                Text(
                                  "One-way: R${oneWay!.toStringAsFixed(2)}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Return: R${returnCost!.toStringAsFixed(2)}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 22, fontWeight: FontWeight.bold),
                                ),const SizedBox(height: 14),

                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    onPressed: startTrip,
                                    icon: const Icon(Icons.navigation, color: Colors.black, size: 18),
                                    label: const Text(
                                      "Start Trip",
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF8C32),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        ],
                      ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),

          bottomNavigationBar: bannerAd == null
              ? const SizedBox.shrink()
              : Container(
            height: bannerAd!.size.height.toDouble(),
            color: Colors.black,
            child: AdWidget(ad: bannerAd!),
          ),
        ),
      ],
    );
  }
}
