import 'package:shared_preferences/shared_preferences.dart';

/// เก็บ / อ่าน JWT token สำหรับเรียก backend (auth + score_service)
class AuthStorage {
  static const String _tokenKey = 'auth_token';

  /// บันทึก token หลัง login
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// อ่าน token (ใช้ตอนเรียก API)
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// ลบ token (logout)
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// เช็คว่า login อยู่ไหม
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
