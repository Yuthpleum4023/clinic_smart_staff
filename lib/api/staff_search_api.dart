// lib/api/staff_search_api.dart
//
// ✅ Staff Search API (AUTH USER SERVICE)
// - GET  {authBaseUrl}/staff/search?q=...
// - GET  {authBaseUrl}/staff/by-staffid/:staffId
// - ✅ ใช้ AuthStorage เป็นแหล่ง token เดียว (sanitize + guard JWT)
// - ✅ กัน baseUrl ซ้อน /
// - ✅ timeout กันค้างเวลา Render cold start
// - ✅ parse response ได้หลายรูปแบบ (items / data / results / array ตรง ๆ)
//

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class StaffSearchApi {
  static const Duration _timeout = Duration(seconds: 60);

  // -----------------------------
  // base + url helper
  // -----------------------------
  static String _baseAuth() {
    final s = ApiConfig.authBaseUrl.trim();
    return s.replaceAll(RegExp(r'\/+$'), '');
  }

  static Uri _u(String base, String path, [Map<String, String>? query]) {
    final b = base.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$b$p');
    return (query == null) ? uri : uri.replace(queryParameters: query);
  }

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getToken(); // ✅ single source of truth
    if (token == null || token.isEmpty) {
      throw Exception('no token (กรุณา login ก่อน)');
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // -----------------------------
  // decode helpers
  // -----------------------------
  static dynamic _tryJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return {'raw': body};
    }
  }

  static List<Map<String, dynamic>> _extractItems(dynamic decoded) {
    // รูปแบบที่พบบ่อย:
    // 1) { items: [...] }
    // 2) { data: [...] }
    // 3) { results: [...] }
    // 4) [...] (array ตรง ๆ)
    // 5) { staff: {...} } (single)
    dynamic listAny = decoded;

    if (decoded is Map) {
      if (decoded['items'] is List) listAny = decoded['items'];
      else if (decoded['data'] is List) listAny = decoded['data'];
      else if (decoded['results'] is List) listAny = decoded['results'];
      else if (decoded['staff'] is Map) listAny = [decoded['staff']];
    }

    if (listAny is! List) return [];

    return listAny.map((e) {
      if (e is Map<String, dynamic>) return e;
      if (e is Map) return Map<String, dynamic>.from(e);
      return {'value': e};
    }).toList();
  }

  static Exception _httpError(String action, http.Response res) {
    final decoded = _tryJson(res.body);
    if (decoded is Map && (decoded['message'] != null || decoded['error'] != null)) {
      final msg = (decoded['message'] ?? decoded['error']).toString();
      return Exception('$action failed: ${res.statusCode} $msg');
    }
    return Exception('$action failed: ${res.statusCode} ${res.body}');
  }

  /// ============================================================
  /// ✅ Search staff
  /// GET /staff/search?q=สมชาย&limit=20
  /// returns: { items: [ { staffId, fullName, phone, ... } ] }
  /// ============================================================
  static Future<List<StaffSearchItem>> search({
    required String q,
    int limit = 20,
  }) async {
    final qq = q.trim();
    if (qq.isEmpty) return [];

    final base = _baseAuth();
    final uri = _u(base, ApiConfig.staffSearch, {
      'q': qq,
      'limit': limit.clamp(1, 50).toString(),
    });

    final res = await http.get(uri, headers: await _headers()).timeout(_timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _httpError('search staff', res);
    }

    final decoded = _tryJson(res.body);
    final items = _extractItems(decoded);

    return items.map(StaffSearchItem.fromMap).toList();
  }

  /// ============================================================
  /// ✅ Get staff by staffId
  /// GET /staff/by-staffid/:staffId
  /// ============================================================
  static Future<StaffSearchItem> getByStaffId(String staffId) async {
    final sid = staffId.trim();
    if (sid.isEmpty) throw Exception('staffId is empty');

    final base = _baseAuth();
    final uri = _u(base, '/staff/by-staffid/${Uri.encodeComponent(sid)}');

    final res = await http.get(uri, headers: await _headers()).timeout(_timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _httpError('getByStaffId', res);
    }

    final decoded = _tryJson(res.body);

    // รองรับทั้ง {staff:{...}} หรือ {...}
    if (decoded is Map && decoded['staff'] is Map) {
      return StaffSearchItem.fromMap(Map<String, dynamic>.from(decoded['staff'] as Map));
    }
    if (decoded is Map<String, dynamic>) {
      return StaffSearchItem.fromMap(decoded);
    }
    if (decoded is Map) {
      return StaffSearchItem.fromMap(Map<String, dynamic>.from(decoded));
    }

    throw Exception('Invalid response format: ${decoded.runtimeType}');
  }
}

/// =======================================
/// Model for UI
/// =======================================
class StaffSearchItem {
  final String staffId;
  final String fullName;
  final String phone;
  final String role;
  final String userId;
  final String clinicId;

  const StaffSearchItem({
    required this.staffId,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.userId,
    required this.clinicId,
  });

  static String _s(dynamic v) => (v ?? '').toString();

  factory StaffSearchItem.fromMap(Map<String, dynamic> m) {
    // รองรับ key หลายแบบ (กัน backend เปลี่ยนชื่อ)
    final staffId = _s(m['staffId'] ?? m['staff_id'] ?? m['id'] ?? m['_id']);
    final fullName = _s(m['fullName'] ?? m['name'] ?? m['displayName']);
    final phone = _s(m['phone'] ?? m['mobile'] ?? m['tel']);
    final role = _s(m['role'] ?? m['position']);
    final userId = _s(m['userId'] ?? m['user_id']);
    final clinicId = _s(m['clinicId'] ?? m['clinic_id']);

    return StaffSearchItem(
      staffId: staffId,
      fullName: fullName,
      phone: phone,
      role: role,
      userId: userId,
      clinicId: clinicId,
    );
  }

  String displayLabel() {
    final name = fullName.trim();
    final ph = phone.trim();
    final sid = staffId.trim();
    if (name.isNotEmpty && ph.isNotEmpty) return '$name • $ph';
    if (name.isNotEmpty && sid.isNotEmpty) return '$name • $sid';
    if (ph.isNotEmpty && sid.isNotEmpty) return '$ph • $sid';
    return sid.isNotEmpty ? sid : '(no staffId)';
  }
}
