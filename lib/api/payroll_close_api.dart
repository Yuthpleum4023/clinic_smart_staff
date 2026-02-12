// lib/api/payroll_close_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// ✅ Payroll Close API (ปิดงวดเงินจริง)
/// - POST /payroll-close/close-month
/// - ใช้ ApiConfig.payrollBaseUrl (DEV ยิงเข้าเครื่อง / PROD ยิง Render)
/// - กัน key token หลายชื่อ
/// - แยก error 409 (ปิดซ้ำ) ให้ชัด
/// - ✅ กัน URL ซ้อน /
/// - ✅ timeout กันค้าง
/// - ✅ error 401/403 ชัดเจน
/// - ✅ FIX: clean token กัน jwt malformed (quote/Bearer ซ้อน/space)
class PayrollCloseApi {
  static const Duration _timeout = Duration(seconds: 15);

  static const List<String> _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
  ];

  static Future<String?> _getTokenRaw() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  /// ✅ Clean token กันเคส:
  /// - มี "..." ติดมา (จาก jsonEncode)
  /// - มี Bearer ติดมาอยู่แล้ว
  /// - มีช่องว่าง/ขึ้นบรรทัดใหม่
  static String _cleanToken(String raw) {
    var t = raw.trim();

    // ตัด quote ครอบทั้งก้อน: "aaa.bbb.ccc"
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      t = t.substring(1, t.length - 1).trim();
    }

    // ตัด Bearer ซ้อน (case-insensitive)
    final lower = t.toLowerCase();
    if (lower.startsWith('bearer ')) {
      t = t.substring(7).trim();
    }

    // กัน newline/space แปลก ๆ
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();

    return t;
  }

  static int _dotCount(String s) {
    return '.'.allMatches(s).length;
  }

  static String _normalizeBase(String baseUrl) {
    var b = baseUrl.trim();
    b = b.replaceAll(RegExp(r'\/+$'), '');
    return b;
  }

  static Uri _buildUri(String baseUrl, String path) {
    final b = _normalizeBase(baseUrl);
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$b$p');
  }

  static Future<Map<String, dynamic>> closeMonth({
    required String clinicId,
    required String employeeId,
    required String month, // yyyy-MM
    required double grossBase,
    double otPay = 0,
    double bonus = 0,
    double otherAllowance = 0,
    double otherDeduction = 0,
    double ssoEmployeeMonthly = 0,
    double pvdEmployeeMonthly = 0,
  }) async {
    final rawToken = await _getTokenRaw();

    if (rawToken == null || rawToken.trim().isEmpty) {
      throw Exception('no token (กรุณา login ก่อน)');
    }

    final token = _cleanToken(rawToken);

    // ✅ ถ้าไม่ใช่ JWT (ต้องมี dot 2 จุด)
    final dots = _dotCount(token);
    if (dots < 2) {
      // ไม่โชว์ token เต็มเพื่อความปลอดภัย
      throw Exception('token malformed (dots=$dots) กรุณา login ใหม่');
    }

    final baseUrl = ApiConfig.payrollBaseUrl;
    final url = _buildUri(baseUrl, '/payroll-close/close-month');

    final payload = <String, dynamic>{
      'clinicId': clinicId,
      'employeeId': employeeId,
      'month': month,
      'grossBase': grossBase,
      'otPay': otPay,
      'bonus': bonus,
      'otherAllowance': otherAllowance,
      'otherDeduction': otherDeduction,
      'ssoEmployeeMonthly': ssoEmployeeMonthly,
      'pvdEmployeeMonthly': pvdEmployeeMonthly,
    };

    final res = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        )
        .timeout(_timeout);

    if (res.statusCode == 409) {
      throw Exception('409: month already closed');
    }

    if (res.statusCode == 401) {
      throw Exception('401: unauthorized (token หมดอายุ/ไม่ถูกต้อง)');
    }
    if (res.statusCode == 403) {
      throw Exception('403: forbidden (ไม่มีสิทธิ์ปิดงวด)');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Close payroll failed: ${res.statusCode} ${res.body}');
    }

    if (res.body.trim().isEmpty) {
      return <String, dynamic>{'ok': true, 'statusCode': res.statusCode};
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);

    throw Exception('Invalid response format: ${decoded.runtimeType}');
  }
}
