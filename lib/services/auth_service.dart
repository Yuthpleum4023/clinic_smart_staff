import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _pinKey = 'edit_pin';

  // =========================
  // Load PIN (nullable)
  // =========================
  static Future<String?> loadPin() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_pinKey);
    if (v == null) return null;
    final cleaned = v.trim();
    if (cleaned.isEmpty || cleaned.toLowerCase() == 'null') return null;
    return cleaned;
  }

  // =========================
  // Has PIN?
  // =========================
  static Future<bool> hasPin() async {
    final pin = await loadPin();
    return pin != null && pin.isNotEmpty;
  }

  // =========================
  // Verify (ถ้ายังไม่ตั้ง PIN -> false)
  // =========================
  static Future<bool> verifyPin(String input) async {
    final pin = await loadPin();
    if (pin == null || pin.isEmpty) return false;

    final cleaned = input.trim();
    return cleaned.isNotEmpty && cleaned == pin;
  }

  // =========================
  // Change PIN
  // =========================
  static Future<bool> setPin(String newPin) async {
    final cleaned = newPin.trim();

    // basic validation
    if (cleaned.length < 4 || cleaned.length > 6) return false;
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, cleaned);
    return true;
  }

  // =========================
  // Reset
  // =========================
  static Future<void> resetPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
  }
}
