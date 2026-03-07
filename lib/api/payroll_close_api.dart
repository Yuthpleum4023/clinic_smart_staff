// lib/api/payroll_close_api.dart
//
// ✅ FINAL — USE ApiClient (single source of truth for Authorization)
// - ยิงไป payroll_service ผ่าน ApiConfig.payrollBaseUrl
// - ไม่อ่าน token จาก SharedPreferences หลาย key อีกต่อไป
// - ApiClient จะ sanitize token + Render-safe timeout ให้แล้ว
// - แยก error 409/401/403 ให้ชัด
//
// ✅ IMPORTANT (FIX ตามที่ท่านสรุป):
// - ใช้ employeeId = staffId (stf_...)
// - รองรับ endpoint ใหม่:
//   - POST /payroll-close/close-month/:employeeId/:month
// - และ fallback endpoint เก่า:
//   - POST /payroll-close/close-month
//
// ✅ NEW (เพิ่มอย่างเดียว — ไม่กระทบของเก่า):
// - รองรับส่ง OT meta เพิ่มเติมเพื่อให้แสดงในสลิปได้ละเอียดขึ้น (optional)
//   - otHours / otMinutes / otItems
// - ยังใช้ otPay เดิมได้เหมือนเดิม 100%
//
import 'api_client.dart';
import 'api_config.dart';

class PayrollCloseApi {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static bool _looksLikeStaffId(String v) => v.trim().startsWith('stf_');

  /// ✅ Payroll Close API (ปิดงวดเงินจริง)
  ///
  /// ✅ NEW preferred:
  /// POST /payroll-close/close-month/:employeeId/:month
  ///
  /// ✅ Fallback legacy:
  /// POST /payroll-close/close-month
  static Future<Map<String, dynamic>> closeMonth({
    required String clinicId,
    required String employeeId, // ✅ ต้องเป็น staffId (stf_...)
    required String month, // yyyy-MM
    required double grossBase,

    // --------------------
    // Earnings
    // --------------------
    double otPay = 0,

    /// ✅ NEW (optional): OT ชั่วโมงรวม (ใช้โชว์ในสลิป)
    double? otHours,

    /// ✅ NEW (optional): OT นาทีรวม (เผื่อ backend ใช้คำนวณ/โชว์)
    int? otMinutes,

    /// ✅ NEW (optional): รายการ OT รายวัน/รายช่วง (เผื่อทำ breakdown ในสลิป)
    /// รูปแบบแนะนำ (ตัวอย่าง):
    /// [
    ///   {"date":"2026-03-01","minutes":120,"multiplier":2.0,"amount":300},
    /// ]
    List<Map<String, dynamic>>? otItems,

    double bonus = 0,
    double otherAllowance = 0,
    double otherDeduction = 0,

    // --------------------
    // Deductions
    // --------------------
    double ssoEmployeeMonthly = 0,
    double pvdEmployeeMonthly = 0,

    bool auth = true,
  }) async {
    try {
      final cid = _s(clinicId);
      final eid = _s(employeeId);
      final m = _s(month);

      if (cid.isEmpty) throw Exception('400: clinicId required');
      if (eid.isEmpty) throw Exception('400: employeeId required');
      if (m.isEmpty) throw Exception('400: month required');

      // ✅ guard กันส่งเลข/employeeCode เข้าระบบ OT/close-month
      if (!_looksLikeStaffId(eid)) {
        throw Exception('400: employeeId must be staffId (stf_...)');
      }

      // ✅ body base (ของเดิม)
      final body = <String, dynamic>{
        'clinicId': cid,
        'employeeId': eid,
        'month': m,
        'grossBase': grossBase,
        'otPay': otPay,
        'bonus': bonus,
        'otherAllowance': otherAllowance,
        'otherDeduction': otherDeduction,
        'ssoEmployeeMonthly': ssoEmployeeMonthly,
        'pvdEmployeeMonthly': pvdEmployeeMonthly,
      };

      // ✅ NEW: ส่งเฉพาะเมื่อมีค่า เพื่อกัน backend strict
      if (otHours != null && otHours > 0) body['otHours'] = otHours;
      if (otMinutes != null && otMinutes > 0) body['otMinutes'] = otMinutes;
      if (otItems != null && otItems.isNotEmpty) body['otItems'] = otItems;

      // =========================================================
      // ✅ Preferred: POST /payroll-close/close-month/:employeeId/:month
      // =========================================================
      try {
        return await _client.post(
          '/payroll-close/close-month/$eid/$m',
          auth: auth,
          body: body,
        );
      } catch (e1) {
        // ถ้าเป็น error สิทธิ์/ปิดซ้ำ ให้โยนทันที ไม่ต้อง fallback
        final msg1 = e1.toString();
        if (msg1.contains('API Error (409)') ||
            msg1.contains('API Error (401)') ||
            msg1.contains('API Error (403)')) {
          throw e1;
        }

        // =========================================================
        // ✅ Fallback legacy: POST /payroll-close/close-month
        // =========================================================
        return await _client.post(
          '/payroll-close/close-month',
          auth: auth,
          body: body,
        );
      }
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

      // ✅ เคส validate ฝั่ง client
      if (msg.contains('400: employeeId must be staffId')) {
        throw Exception('400: employeeId ต้องเป็น staffId (stf_...)');
      }

      rethrow;
    }
  }
}