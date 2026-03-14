import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  TextEditingController petrol95Ctrl = TextEditingController();
  TextEditingController petrol93Ctrl = TextEditingController();
  TextEditingController dieselCtrl = TextEditingController();

  List<Map<String, dynamic>> cars = [];

  bool _isFetching = false;

  // animation for update button glow/scale
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    // glow animation setup
    _glowCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 1200));
    _glowAnim = Tween<double>(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
    _glowCtrl.repeat(reverse: true);

    loadFuelPrices();
    loadCars();
    autoUpdateWeekly();
  }

  @override
  void dispose() {
    petrol95Ctrl.dispose();
    petrol93Ctrl.dispose();
    dieselCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> loadCars() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString("cars");
    cars = saved != null ? List<Map<String, dynamic>>.from(json.decode(saved)) : [];
    setState(() {});
  }

  Future<void> saveCars() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("cars", json.encode(cars));
  }

  Future<void> removeCar(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text("Remove Car?", style: TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to delete this car?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Delete", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirmed == true) {
      cars.removeAt(index);
      await saveCars();
      setState(() {});
      // small snackbar to give feedback
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Car deleted")));
    }
  }

  Future<void> editCarDialog(int index) async {
    TextEditingController nameCtrl = TextEditingController(text: cars[index]["name"]);
    TextEditingController consCtrl = TextEditingController(text: cars[index]["consumption"].toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text("Edit Car", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: _inputDec("Car Name"),
              style: TextStyle(color: Colors.white),
            ),
            SizedBox(height: 10),
            TextField(
              controller: consCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDec("Fuel Consumption (L/100km)"),
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFF8C32)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final cons = double.tryParse(consCtrl.text);
              if (name.isEmpty || cons == null || cons <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Enter valid name and consumption")));
                return;
              }
              cars[index] = {"name": name, "consumption": cons};
              await saveCars();
              setState(() {});
              Navigator.pop(context);
            },
            child: Text("Save", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> addCarDialog() async {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController consCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text("Add Car", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: _inputDec("Car Name"),
              style: TextStyle(color: Colors.white),
            ),
            SizedBox(height: 10),
            TextField(
              controller: consCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDec("Fuel Consumption (L/100km)"),
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFF8C32)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final cons = double.tryParse(consCtrl.text);
              if (name.isEmpty || cons == null || cons <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Enter valid name and consumption")));
                return;
              }
              cars.add({"name": name, "consumption": cons});
              await saveCars();
              setState(() {});
              Navigator.pop(context);
            },
            child: Text("Save", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> loadFuelPrices() async {
    final prefs = await SharedPreferences.getInstance();
    petrol95Ctrl.text = prefs.getString("fuel95") ?? "";
    petrol93Ctrl.text = prefs.getString("fuel93") ?? "";
    dieselCtrl.text = prefs.getString("diesel50") ?? "";
  }

  Future<void> saveFuelPrices() async {
    // basic validation: ensure numbers
    if (!_isValidPrice(petrol95Ctrl.text) ||
        !_isValidPrice(petrol93Ctrl.text) ||
        !_isValidPrice(dieselCtrl.text)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Please enter valid numeric prices")));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("fuel95", petrol95Ctrl.text);
    await prefs.setString("fuel93", petrol93Ctrl.text);
    await prefs.setString("diesel50", dieselCtrl.text);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Fuel prices saved")));
  }

  bool _isValidPrice(String s) {
    if (s.trim().isEmpty) return false;
    final v = double.tryParse(s);
    return v != null && v > 0;
  }

  // Fetch from Beatforge (keeps _isFetching state and only writes last update on success)
  Future<void> fetchFromBeatforge() async {
    final url = Uri.parse("https://www.beatforge.co.za/about-4");
    setState(() => _isFetching = true);

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) throw Exception("Failed to load");

      final body = response.body;

      final reg95 = RegExp(r"95:\s*R([0-9.]+)", caseSensitive: false);
      final reg93 = RegExp(r"93:\s*R([0-9.]+)", caseSensitive: false);
      final regDiesel = RegExp(r"Diesel.*?:\s*R([0-9.]+)", caseSensitive: false);

      final p95 = reg95.firstMatch(body)?.group(1);
      final p93 = reg93.firstMatch(body)?.group(1);
      final d50 = regDiesel.firstMatch(body)?.group(1);

      if (p95 == null || p93 == null || d50 == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ Could not read prices – check Beatforge format")));
        return;
      }

      petrol95Ctrl.text = p95;
      petrol93Ctrl.text = p93;
      dieselCtrl.text = d50;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("fuel95", p95);
      await prefs.setString("fuel93", p93);
      await prefs.setString("diesel50", d50);
      await prefs.setInt("lastFuelUpdate", DateTime.now().millisecondsSinceEpoch);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Fuel prices updated from Beatforge")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Internet error — try again")));
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  Future<void> autoUpdateWeekly() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt("lastFuelUpdate") ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const week = 1000 * 60 * 60 * 24 * 7;

    if (now - last > week) {
      await fetchFromBeatforge();
      // fetchFromBeatforge writes lastFuelUpdate on success
    }
  }

  Future<void> openWeb(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not open link")));
    }
  }

  InputDecoration _inputDec(String label) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: Colors.white54),
    filled: true,
    fillColor: Color(0xFF111111),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF8C32), width: 2)),
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text("Settings")),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFFFF8C32),
        child: Icon(Icons.add, color: Colors.black),
        onPressed: addCarDialog,
      ),

      body: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // CALTEX + AA ROW
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => openWeb("https://caltex.co.za/motorists/products-and-services/fuel-price.html"),
                    style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF1E1E1E)),
                    child: Text("Caltex", style: TextStyle(color: Colors.white70)),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => openWeb("https://aa.co.za/fuel-pricing/"),
                    style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF1E1E1E)),
                    child: Text("AA", style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ),

            SizedBox(height: 12),

            // decorative divider with arrow icon
            Row(
              children: [
                Expanded(child: Divider(color: Colors.white10, thickness: 1)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_downward, color: Colors.white24, size: 18),
                ),
                Expanded(child: Divider(color: Colors.white10, thickness: 1)),
              ],
            ),

            SizedBox(height: 12),

            // CENTERED UPDATE BUTTON with subtle scale/glow animation
            Center(
              child: ScaleTransition(
                scale: _glowAnim,
                child: ElevatedButton(
                  onPressed: _isFetching ? null : fetchFromBeatforge,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFF8C32),
                    padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 8,
                    shadowColor: Color(0xFFFF8C32).withOpacity(0.6),
                  ),
                  child: _isFetching
                      ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_download, color: Colors.black),
                      SizedBox(width: 8),
                      Text("Update Fuel Prices Automatically", style: TextStyle(color: Colors.black)),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(height: 16),

            Text("Manual Fuel Prices", style: TextStyle(color: Colors.white70)),
            SizedBox(height: 8),

            TextField(controller: petrol95Ctrl, decoration: _inputDec("Unleaded 95 (R/L)"), keyboardType: TextInputType.number, style: TextStyle(color: Colors.white)),
            SizedBox(height: 8),
            TextField(controller: petrol93Ctrl, decoration: _inputDec("Unleaded 93 (R/L)"), keyboardType: TextInputType.number, style: TextStyle(color: Colors.white)),
            SizedBox(height: 8),
            TextField(controller: dieselCtrl, decoration: _inputDec("Diesel 50ppm (R/L)"), keyboardType: TextInputType.number, style: TextStyle(color: Colors.white)),
            SizedBox(height: 8),

            Center(
              child: ElevatedButton(
                onPressed: saveFuelPrices,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFFF8C32),
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text("Save", style: TextStyle(color: Colors.black)),
              ),
            ),

            SizedBox(height: 16),

            Text("Saved Cars", style: TextStyle(color: Colors.white70)),
            SizedBox(height: 8),

            // AnimatedSwitcher wraps the list area so changes animate smoothly
            Expanded(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: 300),
                child: cars.isEmpty
                    ? Center(key: ValueKey('empty'), child: Text("No cars added yet", style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                  key: ValueKey('list'),
                  itemCount: cars.length,
                  itemBuilder: (_, i) {
                    final car = cars[i];
                    return Container(
                      margin: EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        tileColor: Colors.transparent,
                        title: Text("${car["name"]} — ${car["consumption"]} L/100km", style: TextStyle(color: Colors.white)),
                        trailing: IconButton(icon: Icon(Icons.delete, color: Colors.redAccent), onPressed: () => removeCar(i)),
                        onTap: () => editCarDialog(i),
                      ),
                    );
                  },
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}
