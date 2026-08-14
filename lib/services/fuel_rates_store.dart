import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/shared_prefs_cache.dart';

/// User-entered petrol / diesel rates (₹/litre).
///
/// Fuel prices are not fetched live — the user types them when needed. Values
/// persist across launches via [SharedPreferences].
class FuelRatesStore extends ChangeNotifier {
  FuelRatesStore._();
  static final FuelRatesStore instance = FuelRatesStore._();

  static const _kPetrol = 'pref_fuel_petrol_per_litre';
  static const _kDiesel = 'pref_fuel_diesel_per_litre';
  static const _kSelectedCity = 'pref_fuel_selected_city';

  static const List<String> cities = [
    'Custom',
    'Mumbai',
    'Delhi',
    'Kolkata',
    'Chennai',
    'Bengaluru',
    'Hyderabad',
    'Pune',
    'Ahmedabad',
  ];

  static const Map<String, ({double petrol, double diesel})> defaultCityRates = {
    'Mumbai': (petrol: 104.21, diesel: 92.15),
    'Delhi': (petrol: 94.72, diesel: 87.62),
    'Kolkata': (petrol: 103.94, diesel: 90.76),
    'Chennai': (petrol: 100.75, diesel: 92.34),
    'Bengaluru': (petrol: 102.84, diesel: 88.95),
    'Hyderabad': (petrol: 107.41, diesel: 95.65),
    'Pune': (petrol: 104.55, diesel: 91.05),
    'Ahmedabad': (petrol: 96.42, diesel: 92.17),
  };

  double? _petrol;
  double? _diesel;
  String _selectedCity = 'Custom';
  final Map<String, double?> _cityPetrol = {};
  final Map<String, double?> _cityDiesel = {};
  bool _loaded = false;

  String get selectedCity => _selectedCity;

  double? get petrolPerLitre {
    if (_selectedCity == 'Custom') {
      return _petrol;
    }
    return _cityPetrol[_selectedCity] ?? defaultCityRates[_selectedCity]?.petrol;
  }

  double? get dieselPerLitre {
    if (_selectedCity == 'Custom') {
      return _diesel;
    }
    return _cityDiesel[_selectedCity] ?? defaultCityRates[_selectedCity]?.diesel;
  }

  bool get hasPetrol => petrolPerLitre != null && petrolPerLitre! > 0;
  bool get hasDiesel => dieselPerLitre != null && dieselPerLitre! > 0;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      _petrol = p.getDouble(_kPetrol);
      _diesel = p.getDouble(_kDiesel);
      _selectedCity = p.getString(_kSelectedCity) ?? 'Custom';
      for (final city in cities) {
        if (city == 'Custom') continue;
        _cityPetrol[city] = p.getDouble('${_kPetrol}_$city');
        _cityDiesel[city] = p.getDouble('${_kDiesel}_$city');
      }
    } catch (e) {
      debugPrint('FuelRatesStore load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSelectedCity(String city) async {
    if (!cities.contains(city)) return;
    _selectedCity = city;
    notifyListeners();
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.setString(_kSelectedCity, city);
    } catch (e) {
      debugPrint('FuelRatesStore save selected city failed: $e');
    }
  }

  Future<void> setPetrol(double? value) async {
    final v = (value != null && value > 0) ? value : null;
    if (_selectedCity == 'Custom') {
      _petrol = v;
    } else {
      _cityPetrol[_selectedCity] = v;
    }
    notifyListeners();
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final key = _selectedCity == 'Custom' ? _kPetrol : '${_kPetrol}_$_selectedCity';
      if (v == null) {
        await p.remove(key);
      } else {
        await p.setDouble(key, v);
      }
    } catch (e) {
      debugPrint('FuelRatesStore save petrol failed: $e');
    }
  }

  Future<void> setDiesel(double? value) async {
    final v = (value != null && value > 0) ? value : null;
    if (_selectedCity == 'Custom') {
      _diesel = v;
    } else {
      _cityDiesel[_selectedCity] = v;
    }
    notifyListeners();
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final key = _selectedCity == 'Custom' ? _kDiesel : '${_kDiesel}_$_selectedCity';
      if (v == null) {
        await p.remove(key);
      } else {
        await p.setDouble(key, v);
      }
    } catch (e) {
      debugPrint('FuelRatesStore save diesel failed: $e');
    }
  }
}
