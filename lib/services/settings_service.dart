import 'package:shared_preferences/shared_preferences.dart';

class SettingService {
  // =========================
  // Keys
  // =========================
  static const String _ssoKey = 'settings_sso_percent';
  static const String _editPinKey = 'edit_pin';

  // Defaults
  static const double _defaultSsoPercent = 5.0;
  static const String _defaultPin = '1234';

  // =========================
  // SSO (%)
  // =========================
  static Future<double> loadSsoPercent() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(_ssoKey);
    return (v == null || v <= 0) ? _defaultSsoPercent : v;
  }

  static Future<void> saveSsoPercent(double percent) async {
    // กันค่าหลุด
    final p = percent.clamp(0.0, 20.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ssoKey, p);
  }

  // =========================
  // Edit PIN
  // =========================
  static Future<String> loadEditPin() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_editPinKey);
    return (v == null || v.trim().isEmpty) ? _defaultPin : v.trim();
  }

  static Future<bool> verifyEditPin(String input) async {
    final pin = await loadEditPin();
    return input.trim() == pin;
  }

  static Future<bool> saveEditPin(String newPin) async {
    final p = newPin.trim();

    // basic validation: 4–6 digits
    if (p.length < 4 || p.length > 6) return false;
    if (!RegExp(r'^\d+$').hasMatch(p)) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_editPinKey, p);
    return true;
  }

  static Future<void> resetEditPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_editPinKey);
  }
}
