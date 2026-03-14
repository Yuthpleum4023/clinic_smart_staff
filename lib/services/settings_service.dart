// lib/services/settings_service.dart
//
// ✅ FULL FILE — SettingsService
// - SSO + PIN
// - Clinic Contact Phone
// - ✅ Clinic Location (local + sync)
// - ✅ Helper Location (local + sync)
// - PRODUCTION SAFE: timeout + error ชัด
//
// NOTE:
// - ฝั่ง clinic ใช้ path เดิมได้ เช่น /clinics/me/location หรือ /users/me/location
// - ฝั่ง helper แนะนำใช้ /users/me/location
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

  // ✅ clinic location keys
  static const String _clinicLatKey = 'clinic_location_lat';
  static const String _clinicLngKey = 'clinic_location_lng';

  // ✅ helper location keys
  static const String _helperLatKey = 'helper_location_lat';
  static const String _helperLngKey = 'helper_location_lng';

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
  static Future<AppLocation?> loadClinicLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_clinicLatKey);
    final lng = prefs.getDouble(_clinicLngKey);

    if (lat == null || lng == null) return null;
    if (lat == 0 && lng == 0) return null;

    return AppLocation(lat: lat, lng: lng);
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
  // ✅ Helper Location (Local)
  // ============================================================
  static Future<AppLocation?> loadHelperLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_helperLatKey);
    final lng = prefs.getDouble(_helperLngKey);

    if (lat == null || lng == null) return null;
    if (lat == 0 && lng == 0) return null;

    return AppLocation(lat: lat, lng: lng);
  }

  static Future<void> saveHelperLocation({
    required double lat,
    required double lng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_helperLatKey, lat);
    await prefs.setDouble(_helperLngKey, lng);
  }

  static Future<void> clearHelperLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_helperLatKey);
    await prefs.remove(_helperLngKey);
  }

  // ============================================================
  // Shared HTTP helpers
  // ============================================================
  static Uri _u(String baseUrl, String path) {
    final b = baseUrl.trim().replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$b$p');
  }

  static Future<http.Response> _syncLocationToBackend({
    required String baseUrl,
    required String token,
    required AppLocation location,
    required String path,
  }) async {
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
  // ✅ Sync clinic location to backend
  // - PATCH {baseUrl}{path}
  // - default path: /clinics/me/location
  // ============================================================
  static Future<http.Response> syncClinicLocationToBackend({
    required String baseUrl,
    required String token,
    required AppLocation location,
    String path = '/clinics/me/location',
  }) async {
    return _syncLocationToBackend(
      baseUrl: baseUrl,
      token: token,
      location: location,
      path: path,
    );
  }

  static Future<http.Response> syncClinicLocationWithStoredToken({
    required String baseUrl,
    required AppLocation location,
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

  // ============================================================
  // ✅ Sync helper location to backend
  // - PATCH {baseUrl}{path}
  // - default path: /users/me/location
  // ============================================================
  static Future<http.Response> syncHelperLocationToBackend({
    required String baseUrl,
    required String token,
    required AppLocation location,
    String path = '/users/me/location',
  }) async {
    return _syncLocationToBackend(
      baseUrl: baseUrl,
      token: token,
      location: location,
      path: path,
    );
  }

  static Future<http.Response> syncHelperLocationWithStoredToken({
    required String baseUrl,
    required AppLocation location,
    String path = '/users/me/location',
  }) async {
    final token = await AuthStorage.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('no token (กรุณา login ก่อน)');
    }
    return syncHelperLocationToBackend(
      baseUrl: baseUrl,
      token: token,
      location: location,
      path: path,
    );
  }
}

// ============================================================
// ✅ Model: AppLocation (กลาง ใช้ได้ทั้ง clinic + helper)
// ============================================================
class AppLocation {
  final double lat;
  final double lng;

  const AppLocation({
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
      };

  factory AppLocation.fromJson(Map<String, dynamic> j) => AppLocation(
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
      );
}

// ============================================================
// ✅ Backward-compatible alias
// โค้ดเก่าที่ใช้ ClinicLocation จะยังใช้ได้
// ============================================================
typedef ClinicLocation = AppLocation;