// lib/api/payroll_close_api.dart
//
// ✅ FINAL — USE ApiClient (single source of truth for Authorization)
// - ยิงไป payroll_service ผ่าน ApiConfig.payrollBaseUrl
// - ApiClient จะ sanitize token + Render-safe timeout ให้แล้ว
// - แยก error 409/401/403 ให้ชัด
//
// ✅ IMPORTANT:
// - ใช้ employeeId = staffId
// - รองรับ endpoint:
//   - POST /payroll-close/close-month/:employeeId/:month
//   - POST /payroll-close/close-month
//   - ✅ NEW: POST /payroll-close/recalculate/:employeeId/:month
//
// ✅ NEW PRODUCTION:
// - recalculateClosedMonth()
// - ใช้สำหรับ admin คำนวณงวดที่ปิดแล้วใหม่
// - backend จะ rollback YTD + ลบงวดเดิม + close ใหม่
//

import 'api_client.dart';
import 'api_config.dart';

class PayrollCloseApi {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  static String _s(dynamic v) => (v ?? '').toString().trim();

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

  static String _normalizeGrossBaseMode(String v) {
    final x = v.trim().toUpperCase();
    if (x == 'POST_DEDUCTION') return 'POST_DEDUCTION';
    if (x == 'AUTO') return 'AUTO';
    return 'PRE_DEDUCTION';
  }

  static Never _mapAndThrowPayrollCloseError(Object e) {
    final msg = e.toString();

    print('[PAYROLL_CLOSE][ERROR][FINAL] $msg');

    if (msg.contains('API Error (409)')) {
      throw Exception('409: month already closed');
    }

    if (msg.contains('API Error (401)')) {
      throw Exception('401: unauthorized (token หมดอายุ/ไม่ถูกต้อง)');
    }

    if (msg.contains('API Error (403)')) {
      throw Exception('403: forbidden (ไม่มีสิทธิ์ดำเนินการ)');
    }

    if (msg.contains('API Error (404)')) {
      throw Exception('404: ไม่พบงวดเงินเดือนที่ปิดแล้ว');
    }

    if (msg.contains('400: month must be yyyy-MM')) {
      throw Exception('400: month ต้องอยู่ในรูปแบบ yyyy-MM');
    }

    if (msg.contains('400: employeeId must be valid staffId')) {
      throw Exception('400: employeeId ต้องเป็น staffId ที่ถูกต้อง');
    }

    throw e;
  }

  /// ✅ Payroll Close API (ปิดงวดเงินจริง)
  ///
  /// Preferred:
  /// POST /payroll-close/close-month/:employeeId/:month
  ///
  /// Fallback legacy:
  /// POST /payroll-close/close-month
  static Future<Map<String, dynamic>> closeMonth({
    required String clinicId,
    required String employeeId,
    required String month, // yyyy-MM
    required double grossBase,

    // Earnings
    double otPay = 0,
    double? otHours,
    int? otMinutes,
    List<Map<String, dynamic>>? otItems,
    double bonus = 0,
    double otherAllowance = 0,
    double otherDeduction = 0,

    // Deductions
    double ssoEmployeeMonthly = 0,
    double pvdEmployeeMonthly = 0,

    // Tax
    String taxMode = 'WITHHOLDING',

    // Gross base meaning
    String grossBaseMode = 'PRE_DEDUCTION',

    /// optional: userId ของ "พนักงานจริง"
    String? employeeUserId,

    bool auth = true,
  }) async {
    try {
      final cid = _s(clinicId);
      final eid = _s(employeeId);
      final m = _s(month);
      final normalizedTaxMode = _normalizeTaxMode(taxMode);
      final normalizedGrossBaseMode = _normalizeGrossBaseMode(grossBaseMode);
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
        'grossBaseMode': normalizedGrossBaseMode,
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

      final preferredPath = '/payroll-close/close-month/$eid/$m';
      final fallbackPath = '/payroll-close/close-month';

      print('[PAYROLL_CLOSE][REQUEST] route=$preferredPath');
      print('[PAYROLL_CLOSE][REQUEST][BODY] $body');

      try {
        final res = await _client.post(
          preferredPath,
          auth: auth,
          body: body,
        );

        print('[PAYROLL_CLOSE][RESPONSE][PREFERRED] $res');
        return res;
      } catch (e1) {
        final msg1 = e1.toString();

        print('[PAYROLL_CLOSE][ERROR][PREFERRED] $msg1');

        if (msg1.contains('API Error (409)') ||
            msg1.contains('API Error (401)') ||
            msg1.contains('API Error (403)')) {
          rethrow;
        }

        print('[PAYROLL_CLOSE][FALLBACK] route=$fallbackPath');
        print('[PAYROLL_CLOSE][FALLBACK][BODY] $body');

        final res = await _client.post(
          fallbackPath,
          auth: auth,
          body: body,
        );

        print('[PAYROLL_CLOSE][RESPONSE][FALLBACK] $res');
        return res;
      }
    } catch (e) {
      _mapAndThrowPayrollCloseError(e);
    }
  }

  /// ✅ Recalculate / Re-close payroll month
  ///
  /// ใช้กรณี:
  /// - admin เผลอปิดงวดก่อนสิ้นเดือน
  /// - มีการ scan / OT / allowance / deduction เปลี่ยนหลังปิดงวด
  ///
  /// Backend จะ:
  /// 1) rollback TaxYTD จาก PayrollClose เดิม
  /// 2) ลบ PayrollClose เดิม
  /// 3) closeMonth ใหม่จากข้อมูลล่าสุด
  ///
  /// POST /payroll-close/recalculate/:employeeId/:month
  static Future<Map<String, dynamic>> recalculateClosedMonth({
    required String employeeId,
    required String month, // yyyy-MM

    /// optional: ถ้าไม่ส่ง backend จะใช้ค่าจาก PayrollClose เดิม
    double? grossBase,
    double? bonus,
    double? otherAllowance,
    double? otherDeduction,
    double? ssoEmployeeMonthly,
    double? pvdEmployeeMonthly,

    /// ถ้าไม่ส่ง backend จะใช้ taxMode เดิม
    String? taxMode,

    /// ถ้าไม่ส่ง backend จะใช้ grossBaseMode เดิม
    String? grossBaseMode,

    /// ปกติไม่ต้องส่ง เพื่อให้ backend คำนวณ OT ใหม่จาก approved OT ล่าสุด
    double? otPay,

    String? employeeUserId,

    bool auth = true,
  }) async {
    try {
      final eid = _s(employeeId);
      final m = _s(month);

      if (eid.isEmpty) {
        throw Exception('400: employeeId required');
      }

      if (!_looksLikeStaffId(eid)) {
        throw Exception('400: employeeId must be valid staffId');
      }

      if (m.isEmpty) {
        throw Exception('400: month required');
      }

      if (!_isYm(m)) {
        throw Exception('400: month must be yyyy-MM');
      }

      final body = <String, dynamic>{};

      if (grossBase != null) body['grossBase'] = grossBase;
      if (bonus != null) body['bonus'] = bonus;
      if (otherAllowance != null) body['otherAllowance'] = otherAllowance;
      if (otherDeduction != null) body['otherDeduction'] = otherDeduction;
      if (ssoEmployeeMonthly != null) {
        body['ssoEmployeeMonthly'] = ssoEmployeeMonthly;
      }
      if (pvdEmployeeMonthly != null) {
        body['pvdEmployeeMonthly'] = pvdEmployeeMonthly;
      }
      if (otPay != null) body['otPay'] = otPay;

      final normalizedTaxMode = _s(taxMode);
      if (normalizedTaxMode.isNotEmpty) {
        body['taxMode'] = _normalizeTaxMode(normalizedTaxMode);
      }

      final normalizedGrossBaseMode = _s(grossBaseMode);
      if (normalizedGrossBaseMode.isNotEmpty) {
        body['grossBaseMode'] = _normalizeGrossBaseMode(normalizedGrossBaseMode);
      }

      final empUserId = _s(employeeUserId);
      if (empUserId.isNotEmpty) {
        body['employeeUserId'] = empUserId;
      }

      final path = '/payroll-close/recalculate/$eid/$m';

      print('[PAYROLL_RECALCULATE][REQUEST] route=$path');
      print('[PAYROLL_RECALCULATE][REQUEST][BODY] $body');

      final res = await _client.post(
        path,
        auth: auth,
        body: body,
      );

      print('[PAYROLL_RECALCULATE][RESPONSE] $res');
      return res;
    } catch (e) {
      final msg = e.toString();

      print('[PAYROLL_RECALCULATE][ERROR][FINAL] $msg');

      if (msg.contains('API Error (404)')) {
        throw Exception('404: ไม่พบงวดเงินเดือนที่ปิดแล้ว');
      }

      if (msg.contains('API Error (401)')) {
        throw Exception('401: unauthorized (token หมดอายุ/ไม่ถูกต้อง)');
      }

      if (msg.contains('API Error (403)')) {
        throw Exception('403: forbidden (ไม่มีสิทธิ์คำนวณงวดใหม่)');
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