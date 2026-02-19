// lib/api/payroll_close_api.dart
//
// ✅ FINAL — USE ApiClient (single source of truth for Authorization)
// - ยิงไป payroll_service ผ่าน ApiConfig.payrollBaseUrl
// - ไม่อ่าน token จาก SharedPreferences หลาย key อีกต่อไป
// - ApiClient จะ sanitize token + Render-safe timeout ให้แล้ว
// - แยก error 409/401/403 ให้ชัด
//
import 'api_client.dart';
import 'api_config.dart';

class PayrollCloseApi {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  /// ✅ Payroll Close API (ปิดงวดเงินจริง)
  /// POST /payroll-close/close-month
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
    bool auth = true,
  }) async {
    try {
      return await _client.post(
        '/payroll-close/close-month',
        auth: auth,
        body: <String, dynamic>{
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
        },
      );
    } catch (e) {
      // ApiClient โยน Exception รูปแบบ: "API Error (code): message"
      final msg = e.toString();

      // ✅ แยกเคสให้ชัดเหมือนเดิม
      if (msg.contains('API Error (409)')) {
        throw Exception('409: month already closed');
      }
      if (msg.contains('API Error (401)')) {
        throw Exception('401: unauthorized (token หมดอายุ/ไม่ถูกต้อง)');
      }
      if (msg.contains('API Error (403)')) {
        throw Exception('403: forbidden (ไม่มีสิทธิ์ปิดงวด)');
      }

      rethrow;
    }
  }
}
