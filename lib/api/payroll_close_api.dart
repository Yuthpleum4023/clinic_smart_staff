// lib/api/payroll_close_api.dart
//
// ✅ PRODUCTION — Backend-only payroll API client
//
// หลักการ:
// - Flutter ส่งเฉพาะ input / intent
// - Backend เป็นผู้คำนวณเงินเดือน / OT / SSO / ภาษี / Net Pay ทั้งหมด
//
// Flutter ส่งได้:
// - clinicId, employeeId, month
// - bonus
// - otherAllowance / commission
// - otherDeduction / รายการหัก
// - pvdEmployeeMonthly
// - taxMode
// - employeeUserId
// - grossBase เป็น fallback ชั่วคราวเท่านั้น หาก staff_service ยังไม่มี salary
//
// Flutter ไม่ส่งเป็นยอดจริง:
// - otPay
// - ssoEmployeeMonthly
// - grossMonthly
// - withheldTaxMonthly
// - netPay
//
// ✅ Endpoints:
// - POST /payroll-close/preview/:employeeId/:month
// - POST /payroll-close/close-month/:employeeId/:month
// - POST /payroll-close/recalculate/:employeeId/:month
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

    if (x == 'NO_WITHHOLDING' || x == 'NONE' || x == 'NO_TAX') {
      return 'NO_WITHHOLDING';
    }

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

    // ignore: avoid_print
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
      throw Exception('404: ไม่พบข้อมูลงวดเงินเดือน');
    }

    if (msg.contains('400: month must be yyyy-MM')) {
      throw Exception('400: month ต้องอยู่ในรูปแบบ yyyy-MM');
    }

    if (msg.contains('400: employeeId must be valid staffId')) {
      throw Exception('400: employeeId ต้องเป็น staffId ที่ถูกต้อง');
    }

    throw e;
  }

  static Map<String, dynamic> _buildInputBody({
    required String clinicId,
    required String employeeId,
    required String month,

    // fallback only; backend prefers staff_service
    double? grossBase,
    String grossBaseMode = 'PRE_DEDUCTION',

    // accounting inputs
    double? bonus,
    double? otherAllowance,
    double? otherDeduction,
    double? pvdEmployeeMonthly,

    // tax
    String taxMode = 'WITHHOLDING',
    String? employeeUserId,

    // future part-time raw work inputs, if caller has them
    double? regularWorkHours,
    int? regularWorkMinutes,
    List<Map<String, dynamic>>? workItems,
  }) {
    final body = <String, dynamic>{
      'clinicId': clinicId,
      'employeeId': employeeId,
      'month': month,
      'taxMode': _normalizeTaxMode(taxMode),
      'grossBaseMode': _normalizeGrossBaseMode(grossBaseMode),
    };

    // ✅ grossBase เป็น fallback ชั่วคราวเท่านั้น
    // backend จะใช้ staff_service salary ก่อน
    if (grossBase != null && grossBase >= 0) {
      body['grossBase'] = grossBase;
    }

    // ✅ input ที่ admin กรอก/ปรับได้ ส่งได้
    if (bonus != null) body['bonus'] = bonus;
    if (otherAllowance != null) body['otherAllowance'] = otherAllowance;
    if (otherDeduction != null) body['otherDeduction'] = otherDeduction;
    if (pvdEmployeeMonthly != null) {
      body['pvdEmployeeMonthly'] = pvdEmployeeMonthly;
    }

    final empUserId = _s(employeeUserId);
    if (empUserId.isNotEmpty) {
      body['employeeUserId'] = empUserId;
    }

    // ✅ สำหรับ part-time ในอนาคต: ส่งชั่วโมง/นาทีดิบให้ backend คำนวณ
    if (regularWorkHours != null && regularWorkHours > 0) {
      body['regularWorkHours'] = regularWorkHours;
    }

    if (regularWorkMinutes != null && regularWorkMinutes > 0) {
      body['regularWorkMinutes'] = regularWorkMinutes;
    }

    if (workItems != null && workItems.isNotEmpty) {
      body['workItems'] = workItems;
    }

    return body;
  }

  static void _validateCommon({
    required String clinicId,
    required String employeeId,
    required String month,
  }) {
    if (clinicId.trim().isEmpty) {
      throw Exception('400: clinicId required');
    }

    if (employeeId.trim().isEmpty) {
      throw Exception('400: employeeId required');
    }

    if (!_looksLikeStaffId(employeeId)) {
      throw Exception('400: employeeId must be valid staffId');
    }

    if (month.trim().isEmpty) {
      throw Exception('400: month required');
    }

    if (!_isYm(month)) {
      throw Exception('400: month must be yyyy-MM');
    }
  }

  /// ✅ Backend Payroll Preview
  ///
  /// Flutter ใช้อันนี้เพื่อ "แสดงผล" เท่านั้น
  /// เงินเดือน / OT / SSO / ภาษี / Net Pay คำนวณจาก backend
  ///
  /// POST /payroll-close/preview/:employeeId/:month
  static Future<Map<String, dynamic>> previewMonth({
    required String clinicId,
    required String employeeId,
    required String month,

    // fallback only; backend prefers staff_service
    double? grossBase,

    // accounting inputs
    double bonus = 0,
    double otherAllowance = 0,
    double otherDeduction = 0,
    double pvdEmployeeMonthly = 0,

    // tax
    String taxMode = 'WITHHOLDING',
    String grossBaseMode = 'PRE_DEDUCTION',
    String? employeeUserId,

    // future part-time raw work inputs
    double? regularWorkHours,
    int? regularWorkMinutes,
    List<Map<String, dynamic>>? workItems,

    bool auth = true,
  }) async {
    try {
      final cid = _s(clinicId);
      final eid = _s(employeeId);
      final m = _s(month);

      _validateCommon(clinicId: cid, employeeId: eid, month: m);

      final body = _buildInputBody(
        clinicId: cid,
        employeeId: eid,
        month: m,
        grossBase: grossBase,
        grossBaseMode: grossBaseMode,
        bonus: bonus,
        otherAllowance: otherAllowance,
        otherDeduction: otherDeduction,
        pvdEmployeeMonthly: pvdEmployeeMonthly,
        taxMode: taxMode,
        employeeUserId: employeeUserId,
        regularWorkHours: regularWorkHours,
        regularWorkMinutes: regularWorkMinutes,
        workItems: workItems,
      );

      final preferredPath = '/payroll-close/preview/$eid/$m';
      final fallbackPath = '/payroll-close/preview';

      // ignore: avoid_print
      print('[PAYROLL_PREVIEW][REQUEST] route=$preferredPath');
      // ignore: avoid_print
      print('[PAYROLL_PREVIEW][REQUEST][BODY] $body');

      try {
        final res = await _client.post(
          preferredPath,
          auth: auth,
          body: body,
        );

        // ignore: avoid_print
        print('[PAYROLL_PREVIEW][RESPONSE][PREFERRED] $res');
        return res;
      } catch (e1) {
        final msg1 = e1.toString();

        // ignore: avoid_print
        print('[PAYROLL_PREVIEW][ERROR][PREFERRED] $msg1');

        if (msg1.contains('API Error (401)') ||
            msg1.contains('API Error (403)')) {
          rethrow;
        }

        // ignore: avoid_print
        print('[PAYROLL_PREVIEW][FALLBACK] route=$fallbackPath');
        // ignore: avoid_print
        print('[PAYROLL_PREVIEW][FALLBACK][BODY] $body');

        final res = await _client.post(
          fallbackPath,
          auth: auth,
          body: body,
        );

        // ignore: avoid_print
        print('[PAYROLL_PREVIEW][RESPONSE][FALLBACK] $res');
        return res;
      }
    } catch (e) {
      _mapAndThrowPayrollCloseError(e);
    }
  }

  /// ✅ Close payroll month
  ///
  /// Backend เป็นผู้คำนวณยอดเงินจริงทั้งหมด
  ///
  /// Preferred:
  /// POST /payroll-close/close-month/:employeeId/:month
  ///
  /// Fallback:
  /// POST /payroll-close/close-month
  static Future<Map<String, dynamic>> closeMonth({
    required String clinicId,
    required String employeeId,
    required String month,

    // เดิม required grossBase — เก็บไว้เพื่อ compatibility
    // แต่ backend จะใช้เป็น fallback เท่านั้น
    required double grossBase,

    // ❌ compatibility only: ไม่ส่งไปเป็นยอดจริงแล้ว
    double otPay = 0,
    double? otHours,
    int? otMinutes,
    List<Map<String, dynamic>>? otItems,
    double ssoEmployeeMonthly = 0,

    // ✅ inputs ที่ส่งได้
    double bonus = 0,
    double otherAllowance = 0,
    double otherDeduction = 0,
    double pvdEmployeeMonthly = 0,

    String taxMode = 'WITHHOLDING',
    String grossBaseMode = 'PRE_DEDUCTION',
    String? employeeUserId,

    // future part-time raw work inputs
    double? regularWorkHours,
    int? regularWorkMinutes,
    List<Map<String, dynamic>>? workItems,

    bool auth = true,
  }) async {
    try {
      final cid = _s(clinicId);
      final eid = _s(employeeId);
      final m = _s(month);

      _validateCommon(clinicId: cid, employeeId: eid, month: m);

      final body = _buildInputBody(
        clinicId: cid,
        employeeId: eid,
        month: m,
        grossBase: grossBase,
        grossBaseMode: grossBaseMode,
        bonus: bonus,
        otherAllowance: otherAllowance,
        otherDeduction: otherDeduction,
        pvdEmployeeMonthly: pvdEmployeeMonthly,
        taxMode: taxMode,
        employeeUserId: employeeUserId,
        regularWorkHours: regularWorkHours,
        regularWorkMinutes: regularWorkMinutes,
        workItems: workItems,
      );

      // ✅ สำคัญ:
      // ไม่ส่ง otPay / ssoEmployeeMonthly / netPay / tax จาก Flutter
      // backend จะคำนวณ OT จาก approved OT และ SSO จาก clinic policy เอง
      if (otPay > 0 || ssoEmployeeMonthly > 0 || otHours != null || otMinutes != null) {
        // ignore: avoid_print
        print(
          '[PAYROLL_CLOSE][INFO] computed Flutter values ignored: '
          'otPay=$otPay sso=$ssoEmployeeMonthly otHours=$otHours otMinutes=$otMinutes',
        );
      }

      if (otItems != null && otItems.isNotEmpty) {
        // ignore: avoid_print
        print(
          '[PAYROLL_CLOSE][INFO] otItems ignored here. '
          'Manual OT should be sent through overtime API before closing payroll.',
        );
      }

      final preferredPath = '/payroll-close/close-month/$eid/$m';
      final fallbackPath = '/payroll-close/close-month';

      // ignore: avoid_print
      print('[PAYROLL_CLOSE][REQUEST] route=$preferredPath');
      // ignore: avoid_print
      print('[PAYROLL_CLOSE][REQUEST][BODY] $body');

      try {
        final res = await _client.post(
          preferredPath,
          auth: auth,
          body: body,
        );

        // ignore: avoid_print
        print('[PAYROLL_CLOSE][RESPONSE][PREFERRED] $res');
        return res;
      } catch (e1) {
        final msg1 = e1.toString();

        // ignore: avoid_print
        print('[PAYROLL_CLOSE][ERROR][PREFERRED] $msg1');

        if (msg1.contains('API Error (409)') ||
            msg1.contains('API Error (401)') ||
            msg1.contains('API Error (403)')) {
          rethrow;
        }

        // ignore: avoid_print
        print('[PAYROLL_CLOSE][FALLBACK] route=$fallbackPath');
        // ignore: avoid_print
        print('[PAYROLL_CLOSE][FALLBACK][BODY] $body');

        final res = await _client.post(
          fallbackPath,
          auth: auth,
          body: body,
        );

        // ignore: avoid_print
        print('[PAYROLL_CLOSE][RESPONSE][FALLBACK] $res');
        return res;
      }
    } catch (e) {
      _mapAndThrowPayrollCloseError(e);
    }
  }

  /// ✅ Recalculate / Re-close payroll month
  ///
  /// ใช้กับปุ่ม admin:
  /// “คำนวณงวดนี้ใหม่”
  ///
  /// ใช้กรณี:
  /// - admin ปิดงวดก่อนสิ้นเดือน
  /// - พนักงาน scan เพิ่มหลังปิดงวด
  /// - มี OT / allowance / deduction เปลี่ยนหลังปิดงวด
  ///
  /// Backend จะ:
  /// 1) rollback TaxYTD จาก PayrollClose เดิม
  /// 2) ลบ PayrollClose เดิม
  /// 3) closeMonth ใหม่จากข้อมูลล่าสุด
  ///
  /// POST /payroll-close/recalculate/:employeeId/:month
  static Future<Map<String, dynamic>> recalculateClosedMonth({
    required String employeeId,
    required String month,

    // optional: ถ้าไม่ส่ง backend จะใช้ค่าจาก PayrollClose เดิม
    double? grossBase,
    double? bonus,
    double? otherAllowance,
    double? otherDeduction,
    double? pvdEmployeeMonthly,

    // ❌ compatibility only: ไม่ส่งเป็นยอดจริง
    double? ssoEmployeeMonthly,
    double? otPay,

    String? taxMode,
    String? grossBaseMode,
    String? employeeUserId,

    // future part-time raw work inputs
    double? regularWorkHours,
    int? regularWorkMinutes,
    List<Map<String, dynamic>>? workItems,

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

      // ✅ fallback/input ที่ส่งได้
      if (grossBase != null && grossBase >= 0) {
        body['grossBase'] = grossBase;
      }

      if (bonus != null) body['bonus'] = bonus;
      if (otherAllowance != null) body['otherAllowance'] = otherAllowance;
      if (otherDeduction != null) body['otherDeduction'] = otherDeduction;

      if (pvdEmployeeMonthly != null) {
        body['pvdEmployeeMonthly'] = pvdEmployeeMonthly;
      }

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

      if (regularWorkHours != null && regularWorkHours > 0) {
        body['regularWorkHours'] = regularWorkHours;
      }

      if (regularWorkMinutes != null && regularWorkMinutes > 0) {
        body['regularWorkMinutes'] = regularWorkMinutes;
      }

      if (workItems != null && workItems.isNotEmpty) {
        body['workItems'] = workItems;
      }

      // ✅ สำคัญ:
      // ไม่ส่ง otPay / ssoEmployeeMonthly ให้ backend เชื่อเป็นยอดจริง
      if ((otPay ?? 0) > 0 || (ssoEmployeeMonthly ?? 0) > 0) {
        // ignore: avoid_print
        print(
          '[PAYROLL_RECALCULATE][INFO] computed Flutter values ignored: '
          'otPay=$otPay ssoEmployeeMonthly=$ssoEmployeeMonthly',
        );
      }

      final path = '/payroll-close/recalculate/$eid/$m';

      // ignore: avoid_print
      print('[PAYROLL_RECALCULATE][REQUEST] route=$path');
      // ignore: avoid_print
      print('[PAYROLL_RECALCULATE][REQUEST][BODY] $body');

      final res = await _client.post(
        path,
        auth: auth,
        body: body,
      );

      // ignore: avoid_print
      print('[PAYROLL_RECALCULATE][RESPONSE] $res');
      return res;
    } catch (e) {
      final msg = e.toString();

      // ignore: avoid_print
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