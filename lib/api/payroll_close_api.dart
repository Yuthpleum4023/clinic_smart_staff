// lib/api/payroll_close_api.dart
//
// ✅ FINAL — USE ApiClient (single source of truth for Authorization)
// - ยิงไป payroll_service ผ่าน ApiConfig.payrollBaseUrl
// - ไม่อ่าน token จาก SharedPreferences หลาย key อีกต่อไป
// - ApiClient จะ sanitize token + Render-safe timeout ให้แล้ว
// - แยก error 409/401/403 ให้ชัด
//
// ✅ IMPORTANT:
// - ใช้ employeeId = staffId
// - staffId จริงอาจเป็น:
//   1) Mongo _id string จาก staff_service
//   2) legacy stf_...
// - รองรับ endpoint ใหม่:
//   - POST /payroll-close/close-month/:employeeId/:month
// - และ fallback endpoint เก่า:
//   - POST /payroll-close/close-month
//
// ✅ NEW:
// - รองรับส่ง OT meta เพิ่มเติมเพื่อให้แสดงในสลิปได้ละเอียดขึ้น (optional)
//   - otHours / otMinutes / otItems
// - รองรับส่ง taxMode ไป backend
//   - WITHHOLDING
//   - NO_WITHHOLDING
// - รองรับส่ง employeeUserId แบบ optional เพื่อช่วย backend คำนวณภาษีแม่นขึ้น
// - validate month format = yyyy-MM
//

import 'api_client.dart';
import 'api_config.dart';

class PayrollCloseApi {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  static String _s(dynamic v) => (v ?? '').toString().trim();

  /// ✅ ปัจจุบันระบบรองรับทั้ง Mongo _id และ legacy stf_...
  /// ดังนั้นฝั่ง client เช็กแค่ว่าไม่ว่างก็พอ
  static bool _looksLikeStaffId(String v) {
    return v.trim().isNotEmpty;
  }

  static bool _isYm(String v) {
    return RegExp(r'^\d{4}-\d{2}$').hasMatch(v.trim());
  }

  static String _normalizeTaxMode(String v) {
    final x = v.trim().toUpperCase();
    if (x == 'NO_WITHHOLDING') return 'NO_WITHHOLDING';
    return 'WITHHOLDING';
  }

  /// ✅ Payroll Close API (ปิดงวดเงินจริง)
  ///
  /// ✅ Preferred:
  /// POST /payroll-close/close-month/:employeeId/:month
  ///
  /// ✅ Fallback legacy:
  /// POST /payroll-close/close-month
  static Future<Map<String, dynamic>> closeMonth({
    required String clinicId,
    required String employeeId,
    required String month, // yyyy-MM
    required double grossBase,

    // --------------------
    // Earnings
    // --------------------
    double otPay = 0,

    /// ✅ optional: OT ชั่วโมงรวม
    double? otHours,

    /// ✅ optional: OT นาทีรวม
    int? otMinutes,

    /// ✅ optional: รายการ OT ย่อย
    List<Map<String, dynamic>>? otItems,

    double bonus = 0,
    double otherAllowance = 0,
    double otherDeduction = 0,

    // --------------------
    // Deductions
    // --------------------
    double ssoEmployeeMonthly = 0,
    double pvdEmployeeMonthly = 0,

    // --------------------
    // Tax
    // --------------------
    String taxMode = 'WITHHOLDING',

    /// ✅ optional: userId ของ "พนักงานจริง"
    /// backend จะใช้ตัวนี้คุย auth tax service ได้แม่นขึ้น
    String? employeeUserId,

    bool auth = true,
  }) async {
    try {
      final cid = _s(clinicId);
      final eid = _s(employeeId);
      final m = _s(month);
      final normalizedTaxMode = _normalizeTaxMode(taxMode);
      final empUserId = _s(employeeUserId);

      if (cid.isEmpty) {
        throw Exception('400: clinicId required');
      }
      if (eid.isEmpty) {
        throw Exception('400: employeeId required');
      }
      if (m.isEmpty) {
        throw Exception('400: month required');
      }
      if (!_isYm(m)) {
        throw Exception('400: month must be yyyy-MM');
      }
      if (!_looksLikeStaffId(eid)) {
        throw Exception('400: employeeId must be valid staffId');
      }

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
        'taxMode': normalizedTaxMode,
      };

      if (empUserId.isNotEmpty) {
        body['employeeUserId'] = empUserId;
      }

      if (otHours != null && otHours > 0) {
        body['otHours'] = otHours;
      }

      if (otMinutes != null && otMinutes > 0) {
        body['otMinutes'] = otMinutes;
      }

      if (otItems != null && otItems.isNotEmpty) {
        body['otItems'] = otItems;
      }

      try {
        return await _client.post(
          '/payroll-close/close-month/$eid/$m',
          auth: auth,
          body: body,
        );
      } catch (e1) {
        final msg1 = e1.toString();

        if (msg1.contains('API Error (409)') ||
            msg1.contains('API Error (401)') ||
            msg1.contains('API Error (403)')) {
          rethrow;
        }

        return await _client.post(
          '/payroll-close/close-month',
          auth: auth,
          body: body,
        );
      }
    } catch (e) {
      final msg = e.toString();

      if (msg.contains('API Error (409)')) {
        throw Exception('409: month already closed');
      }

      if (msg.contains('API Error (401)')) {
        throw Exception('401: unauthorized (token หมดอายุ/ไม่ถูกต้อง)');
      }

      if (msg.contains('API Error (403)')) {
        throw Exception('403: forbidden (ไม่มีสิทธิ์ปิดงวด)');
      }

      if (msg.contains('400: month must be yyyy-MM')) {
        throw Exception('400: month ต้องอยู่ในรูปแบบ yyyy-MM');
      }

      if (msg.contains('400: employeeId must be valid staffId')) {
        throw Exception('400: employeeId ต้องเป็น staffId ที่ถูกต้อง');
      }

      rethrow;
    }
  }
}