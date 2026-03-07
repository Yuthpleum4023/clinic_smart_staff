// lib/api/auth_api.dart
//
// ✅ FINAL (ROBUST) + ✅ MULTI-ROLE READY
// - login รองรับ activeRole (optional)
// - เพิ่ม switchRole() -> POST /switch-role (auth required)
// - me() cache app_clinic_id/app_user_id/app_role + app_active_role/app_roles
//

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class AuthApi {
  static const String _loginPath = '/login';
  static const String _mePath = '/me';

  // ✅ NEW: switch role endpoint (ตาม backend ที่ท่านทำไว้)
  static const String _switchRolePath = '/switch-role';

  static const Duration _timeout = Duration(seconds: 15);

  static Uri _url(String path) => Uri.parse('${ApiConfig.authBaseUrl}$path');

  // ✅ Shared prefs keys (pattern เดียวทั้งแอป)
  static const String _kClinicId = 'app_clinic_id';
  static const String _kUserId = 'app_user_id';

  // legacy: หน้าต่าง ๆ ยังอ่าน app_role อยู่
  static const String _kRole = 'app_role';

  // ✅ NEW: multi-role cache
  static const String _kActiveRole = 'app_active_role';
  static const String _kRolesJson = 'app_roles_json';

  static const List<String> _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
  ];

  static String _pickString(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty || s == 'null') return '';
    return s;
  }

  static String _pickToken(dynamic data) {
    if (data is! Map) return '';
    final t = _pickString(data['token'] ?? data['jwt']);
    return t;
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    throw Exception('Response is not a JSON object');
  }

  // ✅ เซฟ token ให้ครบทุก key ที่หน้าอื่น ๆ ใช้หา
  static Future<void> _saveTokenEverywhere(String token) async {
    await AuthStorage.saveToken(token);

    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      await prefs.setString(k, token);
    }
  }

  // ✅ Sync token จาก prefs -> AuthStorage เผื่อกรณีมี token ใน prefs แต่ storage ว่าง
  static Future<String?> _getTokenRobust() async {
    final t = await AuthStorage.getToken();
    if (t != null && t.trim().isNotEmpty && t != 'null') return t.trim();

    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = prefs.getString(k);
      if (v != null && v.trim().isNotEmpty && v != 'null') {
        await _saveTokenEverywhere(v.trim());
        return v.trim();
      }
    }
    return null;
  }

  // ------------------------------
  // Extract app context from /me
  // ------------------------------
  static String _extractClinicId(Map<String, dynamic> me) {
    final direct = _pickString(me['clinicId']);
    if (direct.isNotEmpty) return direct;

    final clinic = me['clinic'];
    if (clinic is String) return _pickString(clinic);
    if (clinic is Map) {
      final m = Map<String, dynamic>.from(clinic);
      return _pickString(m['id'] ?? m['_id'] ?? m['clinicId']);
    }

    final clinics = me['clinics'];
    if (clinics is List && clinics.isNotEmpty) {
      final first = clinics.first;
      if (first is String) return _pickString(first);
      if (first is Map) {
        final m = Map<String, dynamic>.from(first);
        return _pickString(m['id'] ?? m['_id'] ?? m['clinicId']);
      }
    }

    return '';
  }

  static String _extractUserId(Map<String, dynamic> me) {
    final id1 = _pickString(me['userId']);
    if (id1.isNotEmpty) return id1;

    final id2 = _pickString(me['id']);
    if (id2.isNotEmpty) return id2;

    final id3 = _pickString(me['_id']);
    if (id3.isNotEmpty) return id3;

    final user = me['user'];
    if (user is Map) {
      final m = Map<String, dynamic>.from(user);
      final uid = _pickString(m['id'] ?? m['_id'] ?? m['userId']);
      if (uid.isNotEmpty) return uid;
    }

    return '';
  }

  // ✅ IMPORTANT (Multi-role):
  // prefer activeRole > role > roles[0]
  static String _extractRole(Map<String, dynamic> me) {
    final ar = _pickString(me['activeRole']);
    if (ar.isNotEmpty) return ar;

    final r1 = _pickString(me['role']);
    if (r1.isNotEmpty) return r1;

    final roles = me['roles'];
    if (roles is List && roles.isNotEmpty) {
      return _pickString(roles.first);
    }
    return '';
  }

  static List<String> _extractRoles(Map<String, dynamic> me) {
    final roles = me['roles'];
    if (roles is List) {
      return roles.map((e) => _pickString(e)).where((e) => e.isNotEmpty).toList();
    }
    // fallback: ถ้าไม่มี roles แต่มี role เดียว
    final single = _pickString(me['role']);
    if (single.isNotEmpty) return [single];
    return [];
  }

  static Future<void> _cacheAppContextFromMe(Map<String, dynamic> me) async {
    final clinicId = _extractClinicId(me);
    final userId = _extractUserId(me);
    final role = _extractRole(me);

    final roles = _extractRoles(me);
    final activeRole = _pickString(me['activeRole']).isNotEmpty ? _pickString(me['activeRole']) : role;

    final prefs = await SharedPreferences.getInstance();

    if (clinicId.isNotEmpty) await prefs.setString(_kClinicId, clinicId);
    if (userId.isNotEmpty) await prefs.setString(_kUserId, userId);

    // legacy consumers
    if (role.isNotEmpty) await prefs.setString(_kRole, role);

    // ✅ multi-role cache
    if (activeRole.isNotEmpty) await prefs.setString(_kActiveRole, activeRole);
    await prefs.setString(_kRolesJson, jsonEncode(roles));
  }

  /// Login แล้ว save token
  /// ✅ NEW: ส่ง activeRole ได้ (optional)
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? activeRole, // ✅ NEW
  }) async {
    final body = {
      'emailOrPhone': email,
      'email': email,
      'identifier': email,
      'password': password,
    };

    // ✅ backend รองรับ body.activeRole ตามที่ท่านแก้ไว้
    if (activeRole != null && activeRole.trim().isNotEmpty) {
      body['activeRole'] = activeRole.trim();
    }

    final res = await http
        .post(
          _url(_loginPath),
          headers: const {'Content-Type': 'application/json'},
          body: json.encode(body),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('Login failed: ${res.statusCode} ${res.body}');
    }

    final data = json.decode(res.body);
    final token = _pickToken(data);

    if (token.isEmpty) {
      throw Exception('Login ok but token missing');
    }

    await _saveTokenEverywhere(token);

    // ✅ ดึง /me ต่อทันที เพื่อ cache app_context ให้พร้อมใช้
    return await me();
  }

  /// ✅ NEW: Switch role แล้วออก token ใหม่
  static Future<Map<String, dynamic>> switchRole({
    required String activeRole,
  }) async {
    final token = await _getTokenRobust();
    if (token == null || token.trim().isEmpty) {
      throw Exception('Not logged in');
    }

    final res = await http
        .post(
          _url(_switchRolePath),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'activeRole': activeRole.trim()}),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('switchRole failed: ${res.statusCode} ${res.body}');
    }

    final data = json.decode(res.body);
    final newToken = _pickToken(data);
    if (newToken.isEmpty) {
      throw Exception('switchRole ok but token missing');
    }

    await _saveTokenEverywhere(newToken);

    // response บางทีส่ง {user:{...}} ให้ unify เป็น me map
    final map = _asMap(data);
    final Map<String, dynamic> meMap =
        (map['user'] is Map) ? (map['user'] as Map).cast<String, dynamic>() : map;

    await _cacheAppContextFromMe(meMap);
    return meMap;
  }

  /// ดึงข้อมูลผู้ใช้จาก token
  static Future<Map<String, dynamic>> me() async {
    final token = await _getTokenRobust();
    if (token == null || token.trim().isEmpty) {
      throw Exception('Not logged in');
    }

    await _saveTokenEverywhere(token);

    final res = await http
        .get(
          _url(_mePath),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('me() failed: ${res.statusCode} ${res.body}');
    }

    final data = json.decode(res.body);
    final map = _asMap(data);

    final Map<String, dynamic> me =
        (map['user'] is Map) ? (map['user'] as Map).cast<String, dynamic>() : map;

    await _cacheAppContextFromMe(me);
    return me;
  }
}