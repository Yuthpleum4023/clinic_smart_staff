// ===============================================================
// payroll_tax_api.dart (SUPERMAN DEBUG VERSION)
// ===============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/payroll_tax_result.dart';
import 'api_config.dart';

class PayrollTaxApi {
  /// ✅ ROUTE ที่ถูกต้องจาก backend จริง
  static const String _path = '/users/me/payroll/calc-tax';

  // ============================================================
  // TOKEN RESOLVER
  // ============================================================
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();

    for (final k in [
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
    ]) {
      final v = prefs.getString(k);

      if (v != null && v.isNotEmpty && v != 'null') {
        return v;
      }
    }

    return null;
  }

  // ============================================================
  // RESPONSE PARSER (SAFE)
  // ============================================================
  static PayrollTaxResult _ensureResult(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      return PayrollTaxResult.fromMap(decoded);
    }

    if (decoded is Map) {
      return PayrollTaxResult.fromMap(
        Map<String, dynamic>.from(decoded),
      );
    }

    throw Exception('รูปแบบ response ไม่ถูกต้อง: ${decoded.runtimeType}');
  }

  // ============================================================
  // MAIN API
  // ============================================================
  static Future<PayrollTaxResult> calcMyTax({
    required int year,
    required double grossMonthly,
    double ssoEmployeeMonthly = 0,
    double pvdEmployeeMonthly = 0,
  }) async {
    /// ✅ IMPORTANT: ยิงไป auth_user_service
    final base = ApiConfig.authBaseUrl;

    final url = Uri.parse('$base$_path?year=$year');

    final body = <String, dynamic>{
      'grossMonthly': grossMonthly,
      'monthsPerYear': 12,
      'ssoEmployeeMonthly': ssoEmployeeMonthly,
      'pvdEmployeeMonthly': pvdEmployeeMonthly,
    };

    final token = await _getToken();

    // ============================================================
    // 🔥 SUPERMAN DEBUG LOG
    // ============================================================
    print('======================');
    print('🔥 PAYROLL TAX CALL');
    print('🔥 BASE  = $base');
    print('🔥 PATH  = $_path');
    print('🔥 URL   = $url');
    print('🔥 TOKEN = $token');
    print('🔥 BODY  = ${jsonEncode(body)}');
    print('======================');

    final res = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    // ============================================================
    // 🔥 RESPONSE DEBUG
    // ============================================================
    print('======================');
    print('🔥 PAYROLL TAX RESPONSE');
    print('🔥 STATUS = ${res.statusCode}');
    print('🔥 BODY   = ${res.body}');
    print('======================');

    if (res.statusCode != 200) {
      throw Exception(
        'calcMyTax failed: ${res.statusCode} ${res.body}',
      );
    }

    final decoded = jsonDecode(res.body);
    return _ensureResult(decoded);
  }
}
