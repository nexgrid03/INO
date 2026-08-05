import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-entered petrol / diesel rates (₹/litre).
///
/// Fuel prices are not fetched live — the user types them when needed. Values
/// persist across launches via [SharedPreferences].
class FuelRatesStore extends ChangeNotifier {
  FuelRatesStore._();
  static final FuelRatesStore instance = FuelRatesStore._();

  static const _kPetrol = 'pref_fuel_petrol_per_litre';
  static const _kDiesel = 'pref_fuel_diesel_per_litre';

  double? _petrol;
  double? _diesel;
  bool _loaded = false;

  double? get petrolPerLitre => _petrol;
  double? get dieselPerLitre => _diesel;
  bool get hasPetrol => _petrol != null && _petrol! > 0;
  bool get hasDiesel => _diesel != null && _diesel! > 0;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _petrol = p.getDouble(_kPetrol);
      _diesel = p.getDouble(_kDiesel);
    } catch (e) {
      debugPrint('FuelRatesStore load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPetrol(double? value) async {
    _petrol = (value != null && value > 0) ? value : null;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      if (_petrol == null) {
        await p.remove(_kPetrol);
      } else {
        await p.setDouble(_kPetrol, _petrol!);
      }
    } catch (e) {
      debugPrint('FuelRatesStore save petrol failed: $e');
    }
  }

  Future<void> setDiesel(double? value) async {
    _diesel = (value != null && value > 0) ? value : null;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      if (_diesel == null) {
        await p.remove(_kDiesel);
      } else {
        await p.setDouble(_kDiesel, _diesel!);
      }
    } catch (e) {
      debugPrint('FuelRatesStore save diesel failed: $e');
    }
  }
}
