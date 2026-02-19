import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const String _tokenKey = 'auth_token';

  static String _sanitize(String token) {
    var t = token.trim();

    // กันเคสมีเครื่องหมาย "..."
    if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) {
      t = t.substring(1, t.length - 1).trim();
    }

    // กันเคสเก็บมาพร้อม Bearer (ซ้ำหลายรอบก็เอาออกให้หมด)
    while (t.toLowerCase().startsWith('bearer ')) {
      t = t.substring(7).trim();
    }

    // กัน newline/space แปลก ๆ
    t = t.replaceAll(RegExp(r'\s+'), '').trim();

    // กัน null string
    if (t.isEmpty || t.toLowerCase() == 'null') return '';

    return t;
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final t = _sanitize(token);
    await prefs.setString(_tokenKey, t);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tokenKey);
    if (raw == null) return null;

    final t = _sanitize(raw);

    // ✅ guard: ถ้าไม่เหมือน JWT (ต้องมี 3 ส่วน) อย่าส่งไป
    if (t.split('.').length != 3) return null;

    return t;
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
