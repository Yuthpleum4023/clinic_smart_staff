// lib/services/settings_service.dart
//
// ✅ FULL FILE — SettingsService
// - SSO + PIN
// - Clinic Contact Phone
// - ✅ Clinic Location (local + sync)
// - ✅ Helper Location (local + sync)
// - ✅ NEW: district / province / address / label
// - ✅ NEW: clear local caches for logout / account switch
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
  static const String _clinicDistrictKey = 'clinic_location_district';
  static const String _clinicProvinceKey = 'clinic_location_province';
  static const String _clinicAddressKey = 'clinic_location_address';
  static const String _clinicLabelKey = 'clinic_location_label';

  // ✅ helper location keys
  static const String _helperLatKey = 'helper_location_lat';
  static const String _helperLngKey = 'helper_location_lng';
  static const String _helperDistrictKey = 'helper_location_district';
  static const String _helperProvinceKey = 'helper_location_province';
  static const String _helperAddressKey = 'helper_location_address';
  static const String _helperLabelKey = 'helper_location_label';

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

    return AppLocation(
      lat: lat,
      lng: lng,
      district: (prefs.getString(_clinicDistrictKey) ?? '').trim(),
      province: (prefs.getString(_clinicProvinceKey) ?? '').trim(),
      address: (prefs.getString(_clinicAddressKey) ?? '').trim(),
      label: (prefs.getString(_clinicLabelKey) ?? '').trim(),
    );
  }

  static Future<void> saveClinicLocation({
    required double lat,
    required double lng,
    String district = '',
    String province = '',
    String address = '',
    String label = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_clinicLatKey, lat);
    await prefs.setDouble(_clinicLngKey, lng);
    await prefs.setString(_clinicDistrictKey, district.trim());
    await prefs.setString(_clinicProvinceKey, province.trim());
    await prefs.setString(_clinicAddressKey, address.trim());
    await prefs.setString(_clinicLabelKey, label.trim());
  }

  static Future<void> clearClinicLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clinicLatKey);
    await prefs.remove(_clinicLngKey);
    await prefs.remove(_clinicDistrictKey);
    await prefs.remove(_clinicProvinceKey);
    await prefs.remove(_clinicAddressKey);
    await prefs.remove(_clinicLabelKey);
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

    return AppLocation(
      lat: lat,
      lng: lng,
      district: (prefs.getString(_helperDistrictKey) ?? '').trim(),
      province: (prefs.getString(_helperProvinceKey) ?? '').trim(),
      address: (prefs.getString(_helperAddressKey) ?? '').trim(),
      label: (prefs.getString(_helperLabelKey) ?? '').trim(),
    );
  }

  static Future<void> saveHelperLocation({
    required double lat,
    required double lng,
    String district = '',
    String province = '',
    String address = '',
    String label = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_helperLatKey, lat);
    await prefs.setDouble(_helperLngKey, lng);
    await prefs.setString(_helperDistrictKey, district.trim());
    await prefs.setString(_helperProvinceKey, province.trim());
    await prefs.setString(_helperAddressKey, address.trim());
    await prefs.setString(_helperLabelKey, label.trim());
  }

  static Future<void> clearHelperLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_helperLatKey);
    await prefs.remove(_helperLngKey);
    await prefs.remove(_helperDistrictKey);
    await prefs.remove(_helperProvinceKey);
    await prefs.remove(_helperAddressKey);
    await prefs.remove(_helperLabelKey);
  }

  // ============================================================
  // ✅ Clear local caches (important for logout / switch account)
  // ============================================================
  static Future<void> clearAllLocations() async {
    await clearClinicLocation();
    await clearHelperLocation();
  }

  static Future<void> clearAllLocalProfileCaches() async {
    await clearAllLocations();
    await clearClinicContactPhone();
  }

  static Future<void> resetAllLocalSettingsForAccountSwitch() async {
    await clearAllLocalProfileCaches();
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
      'district': location.district,
      'province': location.province,
      'address': location.address,
      'label': location.label,
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
  final String district;
  final String province;
  final String address;
  final String label;

  const AppLocation({
    required this.lat,
    required this.lng,
    this.district = '',
    this.province = '',
    this.address = '',
    this.label = '',
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'district': district,
        'province': province,
        'address': address,
        'label': label,
      };

  factory AppLocation.fromJson(Map<String, dynamic> j) => AppLocation(
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        district: (j['district'] ?? j['amphoe'] ?? '').toString().trim(),
        province: (j['province'] ?? j['changwat'] ?? '').toString().trim(),
        address: (j['address'] ?? j['fullAddress'] ?? '').toString().trim(),
        label: (j['label'] ?? j['locationLabel'] ?? '').toString().trim(),
      );

  AppLocation copyWith({
    double? lat,
    double? lng,
    String? district,
    String? province,
    String? address,
    String? label,
  }) {
    return AppLocation(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      district: district ?? this.district,
      province: province ?? this.province,
      address: address ?? this.address,
      label: label ?? this.label,
    );
  }
}

// ============================================================
// ✅ Backward-compatible alias
// โค้ดเก่าที่ใช้ ClinicLocation จะยังใช้ได้
// ============================================================
typedef ClinicLocation = AppLocation;