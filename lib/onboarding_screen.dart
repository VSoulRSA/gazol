import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'main.dart';

const _accent = Color(0xFFFF8C32);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final page = PageController();

  final p95Ctrl = TextEditingController();
  final p93Ctrl = TextEditingController();
  final d50Ctrl = TextEditingController();

  final carNameCtrl = TextEditingController();
  final carConsCtrl = TextEditingController();

  int step = 0;
  late AnimationController glowCtrl;

  // make sure we only auto-fetch once when the user first opens the fuel page
  bool _didAutoFetchFuelOnboarding = false;

  @override
  void initState() {
    super.initState();
    glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.8,
      upperBound: 1.15,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    page.dispose();
    glowCtrl.dispose();
    p95Ctrl.dispose();
    p93Ctrl.dispose();
    d50Ctrl.dispose();
    carNameCtrl.dispose();
    carConsCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white54),
    filled: true,
    fillColor: const Color(0xFF111111),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    enabledBorder:
    const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: _accent, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  Widget _orangeButton(String text, VoidCallback onPressed, {bool expand = true}) {
    final btn = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
      child: Text(text, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Future<void> _fetchLatestFuelPrices() async {
    try {
      final response = await http.get(Uri.parse("https://www.beatforge.co.za/about-4"));

      if (response.statusCode != 200) {
        _toast("Couldn't fetch fuel prices, enter manually.");
        return;
      }

      final body = response.body.toLowerCase();

      String _extract(String label) {
        final regex = RegExp("$label:\\s*r?([0-9]+\\.[0-9]+)", caseSensitive: false);
        final match = regex.firstMatch(body);
        return match != null ? match.group(1)! : "";
      }

      final p95 = _extract("petrol 95");
      final p93 = _extract("petrol 93");
      final d50 = _extract("diesel 50ppm");

      if (p95.isEmpty || p93.isEmpty || d50.isEmpty) {
        _toast("Format changed. Enter prices manually.");
        return;
      }

      setState(() {
        p95Ctrl.text = p95;
        p93Ctrl.text = p93;
        d50Ctrl.text = d50;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("fuel95", p95);
      await prefs.setString("fuel93", p93);
      await prefs.setString("diesel50", d50);
    } catch (_) {
      _toast("Failed to fetch prices. Try again.");
    }
  }

  Future<void> _saveFuelPrices() async {
    final p95 = double.tryParse(p95Ctrl.text);
    final p93 = double.tryParse(p93Ctrl.text);
    final d50 = double.tryParse(d50Ctrl.text);
    if (p95 == null || p95 <= 0) return _toast("Enter a valid price for 95");
    if (p93 == null || p93 <= 0) return _toast("Enter a valid price for 93");
    if (d50 == null || d50 <= 0) {
      return _toast("Enter a valid price for Diesel 50ppm");
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("fuel95", p95Ctrl.text);
    await prefs.setString("fuel93", p93Ctrl.text);
    await prefs.setString("diesel50", d50Ctrl.text);
  }

  Future<void> _saveFirstCar() async {
    final name = carNameCtrl.text.trim();
    final cons = double.tryParse(carConsCtrl.text);
    if (name.isEmpty) return _toast("Please enter a car name");
    if (cons == null || cons <= 0) {
      return _toast("Enter a valid fuel consumption (L/100km)");
    }

    final prefs = await SharedPreferences.getInstance();
    final list = [
      {"name": name, "consumption": cons}
    ];
    await prefs.setString("cars", json.encode(list));
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("onboarding_complete", true);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => FuelScreen(),
        transitionsBuilder: (c, a, s, child) => FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  // helper to call once when entering fuel page
  Future<void> _maybeAutoFetchForFuelPage() async {
    if (!_didAutoFetchFuelOnboarding) {
      _didAutoFetchFuelOnboarding = true;
      await _fetchLatestFuelPrices();
    }
  }

  Future<void> _next() async {
    if (step == 0) {
      setState(() => step = 1);
      await page.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      // we've just entered step 1 — trigger the auto-fetch (once)
      await _maybeAutoFetchForFuelPage();
      return;
    }

    if (step == 1) {
      await _saveFuelPrices();
      setState(() => step = 2);
      await page.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      return;
    }

    if (step == 2) {
      await _saveFirstCar();
      await _complete();
    }
  }

  Widget _topLogo() {
    return ScaleTransition(
      scale: glowCtrl,
      child: Container(
        decoration: BoxDecoration(boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.55),
            blurRadius: 60,
            spreadRadius: 10,
          ),
        ]),
        child: Image.asset("assets/images/gazol_logo.png", height: 120),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // when step != 0 we keep the header above the pageview (old behaviour),
    // but for step == 0 we move the header into the page so the whole screen centers.
    final showGlobalHeader = step != 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  // global header (only visible when not on first screen)
                  if (showGlobalHeader) ...[
                    _topLogo(),
                    const SizedBox(height: 10),
                    const Text(
                      "Gazol",
                      style: TextStyle(
                        color: _accent,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        shadows: [Shadow(blurRadius: 24, color: _accent)],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        3,
                            (i) => Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                          decoration: BoxDecoration(
                            color: step == i ? _accent : const Color(0xFF333333),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // when step == 0 we won't show the global header; the first page will include it instead,
                  // so that the whole first-screen content can center vertically.
                  Expanded(
                    child: PageView(
                      controller: page,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        // STEP 1 — fully centered content (includes logo/title/dots)
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _topLogo(),
                            const SizedBox(height: 10),
                            const Text(
                              "Gazol",
                              style: TextStyle(
                                color: _accent,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                shadows: [Shadow(blurRadius: 24, color: _accent)],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                3,
                                    (i) => Container(
                                  width: 10,
                                  height: 10,
                                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: step == i ? _accent : const Color(0xFF333333),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Welcome to Gazol 🚗⛽",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              "We’ll set two things to give you accurate trip costs:\n\n"
                                  "1) Your local fuel prices\n"
                                  "2) Your car’s fuel consumption",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 40),
                            _orangeButton("Get Started", _next),
                          ],
                        ),

                        // STEP 2 — fuel prices + update button
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              "Fuel Prices",
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            _orangeButton("Update Fuel Prices Automatically", _fetchLatestFuelPrices),
                            const SizedBox(height: 12),
                            TextField(controller: p95Ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec("Unleaded 95 (R/L)")),
                            const SizedBox(height: 10),
                            TextField(controller: p93Ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec("Unleaded 93 (R/L)")),
                            const SizedBox(height: 10),
                            TextField(controller: d50Ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec("Diesel 50ppm (R/L)")),
                            const SizedBox(height: 12),
                            const Text("Tip: You can update these anytime in Settings.", style: TextStyle(color: Colors.white54)),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      // go back to step 0
                                      setState(() => step = 0);
                                      await page.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: _accent),
                                      foregroundColor: _accent,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: const Text("Back"),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: _orangeButton("Next", _next, expand: false)),
                              ],
                            ),
                          ],
                        ),

                        // STEP 3 — first car
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              "Add Your Car",
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            TextField(controller: carNameCtrl, style: const TextStyle(color: Colors.white), decoration: _dec("Car name (e.g., Polo 1.0 TSI)")),
                            const SizedBox(height: 10),
                            TextField(controller: carConsCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec("Fuel Consumption (L/100km)")),
                            const SizedBox(height: 12),
                            const Text("Example: 6.8 means 6.8 litres per 100 km.", style: TextStyle(color: Colors.white54)),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      // back to step 1 (fuel)
                                      setState(() => step = 1);
                                      await page.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                                      // we just entered step 1 again — ensure auto-fetch happens if not already
                                      await _maybeAutoFetchForFuelPage();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: _accent),
                                      foregroundColor: _accent,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: const Text("Back"),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: _orangeButton("Finish", _next, expand: false)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
