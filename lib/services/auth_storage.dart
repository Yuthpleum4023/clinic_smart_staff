// lib/services/auth_storage.dart
//
// ✅ FIX — DO NOT REQUIRE JWT FORMAT ON CLIENT
// - sanitize: trim/strip quotes/strip bearer/remove weird whitespace
// - allow opaque tokens (ไม่บังคับต้องมี 3 ส่วน)
// - still blocks empty/"null"
//
// ✅ NEW
// - clear local cached settings when logout
// - prevents previous user's location/settings from leaking
//

import 'package:shared_preferences/shared_preferences.dart';
import 'package:clinic_smart_staff/services/settings_service.dart';

class AuthStorage {
  static const String _tokenKey = 'auth_token';

  // =========================
  // sanitize token
  // =========================
  static String _sanitize(String token) {
    var t = token.trim();

    // กันเคสมีเครื่องหมาย "..."
    if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) {
      t = t.substring(1, t.length - 1).trim();
    }

    // กันเคสเก็บมาพร้อม Bearer
    while (t.toLowerCase().startsWith('bearer ')) {
      t = t.substring(7).trim();
    }

    // กัน newline/space แปลก ๆ
    t = t.replaceAll(RegExp(r'\s+'), '').trim();

    // กัน null string
    if (t.isEmpty || t.toLowerCase() == 'null') return '';

    return t;
  }

  // =========================
  // Save token
  // =========================
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final t = _sanitize(token);

    if (t.isEmpty) {
      // ถ้า token ไม่ถูกต้องก็ลบทิ้ง ไม่เก็บ garbage
      await prefs.remove(_tokenKey);
      return;
    }

    await prefs.setString(_tokenKey, t);
  }

  // =========================
  // Get token
  // =========================
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tokenKey);

    if (raw == null) return null;

    final t = _sanitize(raw);
    if (t.isEmpty) return null;

    // ✅ IMPORTANT: ไม่บังคับต้องเป็น JWT แล้ว
    return t;
  }

  // =========================
  // Logout / Clear token
  // =========================
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();

    // ลบ token
    await prefs.remove(_tokenKey);

    // ✅ NEW — ลบ cache settings ของ user เก่า
    try {
      await SettingService.resetAllLocalSettingsForAccountSwitch();
    } catch (_) {
      // กัน crash ถ้า settings service มีปัญหา
    }
  }

  // =========================
  // Check login state
  // =========================
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}