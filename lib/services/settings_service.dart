// lib/services/settings_service.dart
//
// ✅ FULL FILE — SettingsService (SSO + PIN + Clinic Location + Contact Phone + Sync to Backend)
// - เก็บ SSO% + Edit PIN เหมือนเดิม
// - ✅ เพิ่ม: Clinic Contact Phone (local prefs)
// - เก็บพิกัดคลินิกลงเครื่อง (lat/lng)
// - sync พิกัดขึ้น backend (PATCH /clinics/me/location)
//   ใช้ baseUrl: ApiConfig.payrollBaseUrl (ส่งมาจาก screen)
// - PRODUCTION SAFE: timeout + error ชัด
//

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/services/auth_storage.dart';

class SettingService {
  // =========================
  // Keys
  // =========================
  static const String _ssoKey = 'settings_sso_percent';
  static const String _editPinKey = 'edit_pin';

  // ✅ location keys
  static const String _clinicLatKey = 'clinic_location_lat';
  static const String _clinicLngKey = 'clinic_location_lng';

  // ✅ clinic contact phone key
  static const String _clinicContactPhoneKey = 'clinic_contact_phone';

  // Defaults
  static const double _defaultSsoPercent = 5.0;
  static const String _defaultPin = '1234';

  // timeout
  static const Duration _timeout = Duration(seconds: 30);

  // =========================
  // SSO (%)
  // =========================
  static Future<double> loadSsoPercent() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(_ssoKey);
    return (v == null || v <= 0) ? _defaultSsoPercent : v;
  }

  static Future<void> saveSsoPercent(double percent) async {
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

  // ============================================================
  // ✅ Clinic Contact Phone (Local)
  // ============================================================
  static Future<String> loadClinicContactPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_clinicContactPhoneKey) ?? '').trim();
  }

  static Future<void> saveClinicContactPhone(String phone) async {
    final p = phone.trim();
    // ไม่บังคับ format แข็งใน service (ให้ UI validate ได้)
    // แต่กัน null/empty และกันเก็บค่าแปลก ๆ แบบ "null"
    if (p.isEmpty || p == 'null') return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clinicContactPhoneKey, p);
  }

  static Future<void> clearClinicContactPhone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clinicContactPhoneKey);
  }

  // ============================================================
  // ✅ Clinic Location (Local)
  // ============================================================
  static Future<ClinicLocation?> loadClinicLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_clinicLatKey);
    final lng = prefs.getDouble(_clinicLngKey);

    if (lat == null || lng == null) return null;
    if (lat == 0 && lng == 0) return null;

    return ClinicLocation(lat: lat, lng: lng);
  }

  static Future<void> saveClinicLocation({
    required double lat,
    required double lng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_clinicLatKey, lat);
    await prefs.setDouble(_clinicLngKey, lng);
  }

  static Future<void> clearClinicLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clinicLatKey);
    await prefs.remove(_clinicLngKey);
  }

  // ============================================================
  // ✅ Sync clinic location to backend
  // - PATCH {baseUrl}{path}
  // - default path: /clinics/me/location
  // - body: { lat, lng }
  // ============================================================
  static Uri _u(String baseUrl, String path) {
    final b = baseUrl.trim().replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$b$p');
  }

  static Future<http.Response> syncClinicLocationToBackend({
    required String baseUrl,
    required String token,
    required ClinicLocation location,
    String path = '/clinics/me/location',
  }) async {
    // ✅ ถ้า token ว่าง/ไม่ใช่ JWT ให้หยุดเลย กัน jwt malformed
    final t = token.trim();
    if (t.isEmpty || t.split('.').length != 3) {
      throw Exception('token malformed (กรุณา login ใหม่)');
    }

    final uri = _u(baseUrl, path);

    final body = jsonEncode({
      'lat': location.lat,
      'lng': location.lng,
    });

    final res = await http
        .patch(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $t',
          },
          body: body,
        )
        .timeout(_timeout);

    return res;
  }

  // ============================================================
  // ✅ Convenience: sync using AuthStorage (optional)
  // ============================================================
  static Future<http.Response> syncClinicLocationWithStoredToken({
    required String baseUrl,
    required ClinicLocation location,
    String path = '/clinics/me/location',
  }) async {
    final token = await AuthStorage.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('no token (กรุณา login ก่อน)');
    }
    return syncClinicLocationToBackend(
      baseUrl: baseUrl,
      token: token,
      location: location,
      path: path,
    );
  }
}

// ============================================================
// ✅ Model: ClinicLocation (ใช้ร่วมกับ LocationSettingsScreen)
// ============================================================
class ClinicLocation {
  final double lat;
  final double lng;

  const ClinicLocation({required this.lat, required this.lng});

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  factory ClinicLocation.fromJson(Map<String, dynamic> j) => ClinicLocation(
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
      );
}
