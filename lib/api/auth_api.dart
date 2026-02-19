// lib/api/auth_api.dart
//
// ✅ FINAL (ROBUST) for Regis → Login → Me → Home
// - ยิงไป auth_user_service (3101) ผ่าน ApiConfig.authBaseUrl
// - มี timeout กัน spin ค้าง
// - รองรับ backend รับหลาย key: emailOrPhone / email / identifier
// - รองรับ token หลายชื่อ: token / jwt
// - me รองรับ response แบบ {user:{...}} หรือ {...}
//
// ✅ FIX (สำคัญมาก):
// - Login สำเร็จแล้ว "ต้องเซฟ token" ให้ทุกหน้าที่อ่าน SharedPreferences หาเจอ
// - me() ก็ sync token -> prefs เผื่อบาง flow มี token แค่ใน storage
//
// ✅ NEW (AppContext Pattern):
// - หลัง me() ได้ข้อมูลแล้ว จะ cache app_clinic_id/app_user_id/app_role ให้ทั้งแอปใช้แบบเดียวกัน
//

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class AuthApi {
  // 🔧 ถ้า backend ใช้ /auth/login ให้เปลี่ยนเป็น '/auth/login'
  static const String _loginPath = '/login';
  // 🔧 ถ้า backend ใช้ /auth/me ให้เปลี่ยนเป็น '/auth/me'
  static const String _mePath = '/me';

  static const Duration _timeout = Duration(seconds: 15);

  static Uri _url(String path) => Uri.parse('${ApiConfig.authBaseUrl}$path');

  // ✅ Shared prefs keys (pattern เดียวทั้งแอป)
  static const String _kClinicId = 'app_clinic_id';
  static const String _kUserId = 'app_user_id';
  static const String _kRole = 'app_role';

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
    // 1) เซฟผ่าน storage หลักของคุณ
    await AuthStorage.saveToken(token);

    // 2) เซฟซ้ำลง prefs หลาย key (กันหน้าอื่นอ่านไม่เจอ)
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
        // sync กลับเข้า storage + keys อื่นด้วย
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

  static String _extractRole(Map<String, dynamic> me) {
    final r1 = _pickString(me['role']);
    if (r1.isNotEmpty) return r1;

    final roles = me['roles'];
    if (roles is List && roles.isNotEmpty) {
      return _pickString(roles.first);
    }
    return '';
  }

  static Future<void> _cacheAppContextFromMe(Map<String, dynamic> me) async {
    final clinicId = _extractClinicId(me);
    final userId = _extractUserId(me);
    final role = _extractRole(me);

    // cache เฉพาะเมื่อมีค่าจริง
    if (clinicId.isEmpty && userId.isEmpty && role.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    if (clinicId.isNotEmpty) await prefs.setString(_kClinicId, clinicId);
    if (userId.isNotEmpty) await prefs.setString(_kUserId, userId);
    if (role.isNotEmpty) await prefs.setString(_kRole, role);
  }

  /// Login แล้ว save token
  /// ✅ ปรับให้ return user จาก me() ด้วย (ช่วย flow: login -> dashboard พร้อม clinicId/userId ทันที)
  static Future<Map<String, dynamic>> login({
    required String email, // ใช้เป็น id ได้ทั้ง email/phone
    required String password,
  }) async {
    final res = await http
        .post(
          _url(_loginPath),
          headers: const {'Content-Type': 'application/json'},
          body: json.encode({
            'emailOrPhone': email,
            'email': email,
            'identifier': email,
            'password': password,
          }),
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

    // ✅ FIX: เซฟ token ให้ทุกหน้าหาเจอ
    await _saveTokenEverywhere(token);

    // ✅ NEW: ดึง /me ต่อทันที เพื่อ cache app_context ให้พร้อมใช้
    return await me();
  }

  /// ดึงข้อมูลผู้ใช้จาก token
  /// ✅ return Map เพื่อให้ AuthGate / AppContext ใช้ต่อได้
  static Future<Map<String, dynamic>> me() async {
    final token = await _getTokenRobust();
    if (token == null || token.trim().isEmpty) {
      throw Exception('Not logged in');
    }

    // ✅ sync token ไป prefs ทุกครั้ง เผื่อ prefs โดนล้าง
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

    // ✅ รองรับ backend ส่ง { user: {...} }
    final Map<String, dynamic> me =
        (map['user'] is Map) ? (map['user'] as Map).cast<String, dynamic>() : map;

    // ✅ NEW: cache clinicId/userId/role ลง prefs แบบ pattern เดียว
    await _cacheAppContextFromMe(me);

    return me;
  }
}
