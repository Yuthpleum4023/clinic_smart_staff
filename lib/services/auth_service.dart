import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class AuthService {
  static const Duration _timeout = Duration(seconds: 15);

  // Legacy local keys: kept only for cleanup / migration safety.
  static const String _legacyPinKey = 'edit_pin';
  static const String _legacyEmployeeDetailPinKey = 'app_edit_pin';

  static Uri _url(String path) {
    final base = ApiConfig.authBaseUrl.trim().replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  static String _clean(String v) {
    var t = v.trim();

    if ((t.startsWith('"') && t.endsWith('"')) ||
        (t.startsWith("'") && t.endsWith("'"))) {
      t = t.substring(1, t.length - 1).trim();
    }

    while (t.toLowerCase().startsWith('bearer ')) {
      t = t.substring(7).trim();
    }

    return t;
  }

  static Future<Map<String, String>> _headers() async {
    final raw = await AuthStorage.getToken();
    final token = _clean(raw ?? '');

    if (token.isEmpty || token.toLowerCase() == 'null') {
      throw Exception('AUTH_REQUIRED');
    }

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decodeObject(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();

    throw Exception('Response is not a JSON object');
  }

  static Map<String, dynamic> _dataMap(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return json;
  }

  static bool _pickBool(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  static bool _isValidPin(String pin) {
    final p = pin.trim();
    return RegExp(r'^\d{4,6}$').hasMatch(p);
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    final res = await http
        .get(_url(path), headers: await _headers())
        .timeout(_timeout);

    final json = _decodeObject(res.body);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return json;
    }

    final code = (json['code'] ?? '').toString();
    final msg = (json['message'] ?? res.body).toString();
    throw Exception('$code $msg'.trim());
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await http
        .post(
          _url(path),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    final json = _decodeObject(res.body);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return json;
    }

    final code = (json['code'] ?? '').toString();
    final msg = (json['message'] ?? res.body).toString();
    throw Exception('$code $msg'.trim());
  }

  // Deprecated: backend PIN is the source of truth now.
  static Future<String?> loadPin() async {
    return null;
  }

  // Backend clinic PIN status.
  static Future<bool> hasPin() async {
    try {
      final json = await _get('/clinic-security/pin/status');
      final data = _dataMap(json);
      return _pickBool(data['hasPin']);
    } catch (_) {
      // Keep old UI stable. setPin/verifyPin will still surface real errors.
      return false;
    }
  }

  // Backend clinic PIN verification.
  static Future<bool> verifyPin(String input) async {
    final cleaned = input.trim();

    if (!_isValidPin(cleaned)) return false;

    final json = await _post('/clinic-security/pin/verify', {
      'pin': cleaned,
    });

    final data = _dataMap(json);

    return _pickBool(data['valid']) || _pickBool(json['valid']);
  }

  // Backend clinic PIN set/change. Admin/clinic_admin only on backend.
  static Future<bool> setPin(String newPin) async {
    final cleaned = newPin.trim();

    if (!_isValidPin(cleaned)) return false;

    final json = await _post('/clinic-security/pin/set', {
      'pin': cleaned,
    });

    final data = _dataMap(json);

    return _pickBool(json['ok']) || _pickBool(data['hasPin']);
  }

  // No backend reset endpoint yet. This only cleans old local PIN leftovers.
  static Future<void> resetPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyPinKey);
    await prefs.remove(_legacyEmployeeDetailPinKey);
  }
}
