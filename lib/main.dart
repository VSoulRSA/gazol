// ✅IMPORTS — DO NOT CHANGE
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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
      home: const LaunchGate(), // ✅ Decide onboarding or app
    );
  }
}

/// ✅ Decides whether onboarding or splash → FuelScreen
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

        // ✅ If user still has no car or first launch → onboarding
        if (snapshot.data == true) return const OnboardingScreen();

        // ✅ Else → normal splash/app
        return SplashScreen();
      },
    );
  }
}

// ✅ BACKGROUND PATTERN — unchanged
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


// FuelScreen CODE —

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

    // restore selections
    final savedCar = prefs.getString("last_selected_car");
    final savedFuel = prefs.getString("last_selected_fuel");

    // only restore the car if it exists in the current list
    if (savedCar != null && savedCar.isNotEmpty) {
      final exists = cars.any((c) => c["name"] == savedCar);
      if (exists) {
        selectedCar = savedCar;
        // set fuel consumption from the saved car
        final car = cars.firstWhere((c) => c["name"] == savedCar);
        fuelCtrl.text = car["consumption"].toString();
      } else {
        // saved car not found — clear it
        selectedCar = null;
        await prefs.remove("last_selected_car");
      }
    } else {
      selectedCar = null;
    }

    // restore fuel selection if the key price exists
    if (savedFuel != null && savedFuel.isNotEmpty) {
      final price = prefs.getString(savedFuel) ?? "";
      if (price.isNotEmpty) {
        selectedFuel = savedFuel;
        priceCtrl.text = price;
      } else {
        // saved fuel type no longer has a price — clear it
        selectedFuel = null;
        await prefs.remove("last_selected_fuel");
      }
    } else {
      selectedFuel = null;
    }

    setState(() {});
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
    if (fuelKey == null) {
      await prefs.remove("last_selected_fuel");
    } else {
      await prefs.setString("last_selected_fuel", fuelKey);
    }
  }

  // LOCATION (stores coordinates)
  Future<void> getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => locationText = "GPS Off");
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return;

    final pos = await Geolocator.getCurrentPosition();
    currentLat = pos.latitude;
    currentLng = pos.longitude;

    final place =
        (await placemarkFromCoordinates(pos.latitude, pos.longitude)).first;

    final parts = [
      place.locality,
      place.administrativeArea,
      place.country
    ].where((e) => e != null && e.trim().isNotEmpty).map((e) => e!).toList();

    setState(() => locationText = parts.join(", "));
  }

  // ✅ GOOGLE DISTANCE
  Future<void> fetchDistance() async {
    if (destinationCtrl.text.isEmpty) return;

    final url =
        "https://maps.googleapis.com/maps/api/distancematrix/json?origins=$locationText&destinations=${destinationCtrl.text}&mode=driving&key=$googleApiKey";

    final res = await http.get(Uri.parse(url));
    final data = json.decode(res.body);

    try {
      final element = data["rows"][0]["elements"][0];
      if (element["status"] != "OK") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Destination not found. Please enter a valid location.")),
        );
        return;
      }

      final meters = element["distance"]["value"];
      setState(() => distanceCtrl.text = (meters / 1000).toStringAsFixed(1));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not verify destination. Try again.")),
      );
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

    // No destination provided — just center map on current coords
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

  // ✅ CALC
  void calculate() {
    final d = double.tryParse(distanceCtrl.text);
    final f = double.tryParse(fuelCtrl.text);
    final p = double.tryParse(priceCtrl.text);

    if (d == null || d <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Please enter a valid distance (km)")));
      return;
    }
    if (f == null || f <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Please enter a valid fuel consumption")));
      return;
    }
    if (p == null || p <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Please select a fuel type & set prices")));
      return;
    }

    litres = (d / 100) * f;
    oneWay = litres! * p;
    returnCost = oneWay! * 2;
    setState(() {});
  }

  // ✅ Trip launcher
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
          if (Platform.isIOS)
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

  // ✅ nice buttons
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

  // ✅ Fuel Chip
  Widget fuelChip(String label, String key) {
    final bool isSelected = selectedFuel == key;
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        final price = prefs.getString(key) ?? "";
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
        // persist fuel selection
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
                      children: [
                        Expanded(
                          child: TextField(
                            controller: destinationCtrl,
                            keyboardType: TextInputType.text,
                            style: const TextStyle(color: Colors.white),
                            decoration: boxInput("Destination"),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          onPressed: fetchDistance,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8C32),
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)),
                          ),
                          child: const Text("Get", style: TextStyle(color: Colors.black)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // <<< MOVED: Show on Map button is now directly under the destination field >>>
                    if (currentLat != null && currentLng != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 20),
                        child: ElevatedButton.icon(
                          onPressed: _openMap,
                          icon: const Icon(Icons.map, color: Colors.black),
                          label: const Text("Show on Map", style: TextStyle(color: Colors.black)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8C32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
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
                            setState(() {
                              selectedCar = car["name"];
                              fuelCtrl.text = car["consumption"].toString();
                            });
                            // persist selected car
                            await _saveSelectedCar(selectedCar);
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
                        fuelChip("95", "fuel95"),
                        fuelChip("93", "fuel93"),
                        fuelChip("Diesel", "diesel50"),
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
                                const Text(
                                  "Trip Estimate",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "${litres!.toStringAsFixed(2)} L",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.bold),
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
