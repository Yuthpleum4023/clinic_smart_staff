// lib/api/payroll_tax_api.dart
//
// ✅ FINAL — USE ApiClient (single source of truth for Authorization)
// - ไม่อ่าน token จาก SharedPreferences หลาย key อีกต่อไป
// - ใช้ ApiClient ที่ sanitize token + Render-safe timeout
// - ยิงไป auth_user_service ผ่าน ApiConfig.authBaseUrl
//
import '../models/payroll_tax_result.dart';
import 'api_client.dart';
import 'api_config.dart';

class PayrollTaxApi {
  /// ✅ ROUTE ที่ถูกต้องจาก backend จริง
  static const String _path = '/users/me/payroll/calc-tax';

  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.authBaseUrl);

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
    bool auth = true,
    bool debug = false,
  }) async {
    final body = <String, dynamic>{
      'grossMonthly': grossMonthly,
      'monthsPerYear': 12,
      'ssoEmployeeMonthly': ssoEmployeeMonthly,
      'pvdEmployeeMonthly': pvdEmployeeMonthly,
    };

    if (debug) {
      // ✅ ไม่ log token เต็ม (กันหลุด)
      // ✅ log เฉพาะ URL/Body เพื่อ debug route
      // (ApiClient จะจัดการ Authorization เอง)
      // ignore: avoid_print
      print('======================');
      // ignore: avoid_print
      print('🔥 PAYROLL TAX CALL');
      // ignore: avoid_print
      print('🔥 BASE  = ${ApiConfig.authBaseUrl}');
      // ignore: avoid_print
      print('🔥 PATH  = $_path');
      // ignore: avoid_print
      print('🔥 Q     = year=$year');
      // ignore: avoid_print
      print('🔥 BODY  = $body');
      // ignore: avoid_print
      print('======================');
    }

    final decoded = await _client.post(
      _path,
      auth: auth,
      query: {'year': '$year'},
      body: body,
    );

    // backend อาจส่ง {ok:true, result:{...}} หรือส่ง {...} ตรง ๆ
    final dynamic payload = decoded['result'] ?? decoded;

    return _ensureResult(payload);
  }
}
