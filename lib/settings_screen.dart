import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'fuel_pricing.dart';
import 'http_text.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  TextEditingController petrol95Ctrl = TextEditingController();
  TextEditingController petrol93Ctrl = TextEditingController();
  TextEditingController dieselCtrl = TextEditingController();
  TextEditingController diesel500Ctrl = TextEditingController();
  FuelRegion selectedRegion = FuelRegion.inland;

  List<Map<String, dynamic>> cars = [];

  bool _isFetching = false;
  bool _isCarDialogOpen = false;

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
    diesel500Ctrl.dispose();
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
    final prefs = await SharedPreferences.getInstance();
    final originalName = cars[index]["name"] as String?;
    String? selectedFuelType = vehicleFuelType(cars[index]) ??
        normalizeFuelType(prefs.getString("last_selected_fuel"));

    setState(() => _isCarDialogOpen = true);
    try {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
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
              SizedBox(height: 10),
              _fuelTypeSelector(
                key: const ValueKey('edit-car-fuel-type'),
                initialValue: selectedFuelType,
                onChanged: (value) => selectedFuelType = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFF8C32)),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final cons = double.tryParse(consCtrl.text);
                if (name.isEmpty || cons == null || cons <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Enter valid name and consumption")));
                  return;
                }
                if (normalizeFuelType(selectedFuelType) == null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Select a fuel type")));
                  return;
                }
                cars[index]["name"] = name;
                cars[index]["consumption"] = cons;
                cars[index]["fuelType"] = selectedFuelType;
                if (prefs.getString("last_selected_car") == originalName) {
                  await prefs.setString("last_selected_fuel", selectedFuelType!);
                }
                await saveCars();
                setState(() {});
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: Text("Save", style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isCarDialogOpen = false);
    }
  }

  Future<void> addCarDialog() async {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController consCtrl = TextEditingController();
    final prefs = await SharedPreferences.getInstance();
    String? selectedFuelType =
        normalizeFuelType(prefs.getString("last_selected_fuel"));

    setState(() => _isCarDialogOpen = true);
    try {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
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
              SizedBox(height: 10),
              _fuelTypeSelector(
                key: const ValueKey('add-car-fuel-type'),
                initialValue: selectedFuelType,
                onChanged: (value) => selectedFuelType = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFF8C32)),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final cons = double.tryParse(consCtrl.text);
                if (name.isEmpty || cons == null || cons <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Enter valid name and consumption")));
                  return;
                }
                if (normalizeFuelType(selectedFuelType) == null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Select a fuel type")));
                  return;
                }
                cars.add({
                  "name": name,
                  "consumption": cons,
                  "fuelType": selectedFuelType,
                });
                await saveCars();
                setState(() {});
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: Text("Save", style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isCarDialogOpen = false);
    }
  }

  Future<void> loadFuelPrices() async {
    final prefs = await SharedPreferences.getInstance();
    selectedRegion = parseFuelRegion(prefs.getString("fuel_region"));
    petrol95Ctrl.text = storedFuelPrice(prefs, selectedRegion, "fuel95");
    petrol93Ctrl.text = storedFuelPrice(prefs, selectedRegion, "fuel93");
    dieselCtrl.text = storedFuelPrice(prefs, selectedRegion, "diesel50");
    diesel500Ctrl.text = storedFuelPrice(prefs, selectedRegion, "diesel500");
    if (mounted) setState(() {});
  }

  Future<void> saveFuelPrices() async {
    // basic validation: ensure numbers
    if (!_isValidPrice(petrol95Ctrl.text) ||
        !_isValidPrice(petrol93Ctrl.text) ||
        !_isValidPrice(dieselCtrl.text) ||
        !_isValidPrice(diesel500Ctrl.text)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Please enter valid numeric prices")));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await saveRegionFuelPrices(prefs, selectedRegion, {
      "fuel95": petrol95Ctrl.text,
      "fuel93": petrol93Ctrl.text,
      "diesel50": dieselCtrl.text,
      "diesel500": diesel500Ctrl.text,
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fuel prices saved")));
  }

  Future<void> _selectRegion(FuelRegion region) async {
    if (region == selectedRegion) return;
    final prefs = await SharedPreferences.getInstance();
    await saveFuelRegion(prefs, region);
    setState(() => selectedRegion = region);
    await loadFuelPrices();
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

      final prices = parseBeatForgeFuelPrices(decodeHttpResponseBody(response));
      final prefs = await SharedPreferences.getInstance();
      await saveAllRegionalFuelPrices(prefs, prices);
      await prefs.setInt("lastFuelUpdate", DateTime.now().millisecondsSinceEpoch);

      final selectedPrices = prices[selectedRegion]!;
      petrol95Ctrl.text = selectedPrices["fuel95"]!;
      petrol93Ctrl.text = selectedPrices["fuel93"]!;
      dieselCtrl.text = selectedPrices["diesel50"]!;
      diesel500Ctrl.text = selectedPrices["diesel500"]!;
      if (mounted) setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Fuel prices updated from BeatForge")),
      );
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not read all eight prices from BeatForge")),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Internet error - try again")),
      );
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

  Widget _regionButton(FuelRegion region, String label) {
    final isSelected = selectedRegion == region;
    return Expanded(
      child: InkWell(
        key: ValueKey('fuel-region-${region.name}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _selectRegion(region),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 160),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Color(0xFFFF8C32) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Color(0xFFFF8C32) : Color(0xFF3A3A3A),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white70,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
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

  Widget _fuelTypeSelector({
    required Key key,
    required String? initialValue,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: initialValue,
      isExpanded: true,
      menuMaxHeight: 260,
      dropdownColor: const Color(0xFF1E1E1E),
      iconEnabledColor: Colors.white70,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDec("Fuel Type").copyWith(
        hintText: "Select fuel type",
        filled: true,
        fillColor: const Color(0xFF111111),
      ),
      items: fuelTypeLabels.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value, style: const TextStyle(color: Colors.white)),
            ),
          )
          .toList(growable: false),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text("Settings")),
      resizeToAvoidBottomInset: !_isCarDialogOpen,

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

            Row(
              children: [
                Text("Fuel Region", style: TextStyle(color: Colors.white70)),
                SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      _regionButton(FuelRegion.inland, "Inland"),
                      SizedBox(width: 8),
                      _regionButton(FuelRegion.coastal, "Coastal"),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: 6),

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

            Text(
              "Manual ${selectedRegion == FuelRegion.inland ? 'Inland' : 'Coastal'} Fuel Prices",
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 8),

            TextField(controller: petrol95Ctrl, decoration: _inputDec("Unleaded 95 (R/L)").copyWith(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), keyboardType: TextInputType.number, style: TextStyle(color: Colors.white)),
            SizedBox(height: 6),
            TextField(controller: petrol93Ctrl, decoration: _inputDec("Unleaded 93 (R/L)").copyWith(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), keyboardType: TextInputType.number, style: TextStyle(color: Colors.white)),
            SizedBox(height: 6),
            TextField(controller: dieselCtrl, decoration: _inputDec("Diesel 50ppm (R/L)").copyWith(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), keyboardType: TextInputType.number, style: TextStyle(color: Colors.white)),
            SizedBox(height: 6),
            TextField(controller: diesel500Ctrl, decoration: _inputDec("Diesel 500ppm (R/L)").copyWith(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), keyboardType: TextInputType.number, style: TextStyle(color: Colors.white)),
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
