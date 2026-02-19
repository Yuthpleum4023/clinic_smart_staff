// lib/services/clinic_shift_need_service.dart
//
// ✅ FINAL — USE ApiClient ONLY (single source of truth for Authorization)
// - ตัดการอ่าน token จาก SharedPreferences หลาย key (กัน jwt malformed)
// - ตัด payrollBaseUrl override จาก prefs (กันยิงผิด env)
// - ใช้ ApiConfig.payrollBaseUrl เท่านั้น
// - ใช้ ApiClient (sanitize token + Render-safe timeout) ทุก request
//
import 'package:flutter/foundation.dart';

import 'package:clinic_smart_staff/models/clinic_shift_need_model.dart';
import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';

class ClinicShiftNeedService {
  // --------------------------------------------------------------------------
  // ✅ Logging helper
  // --------------------------------------------------------------------------
  static void _log(String msg) {
    if (kDebugMode) {
      debugPrint('🧩 [ShiftNeedService] $msg');
    }
  }

  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  static List<ClinicShiftNeed> _decodeListFromAny(dynamic decoded) {
    dynamic listAny = decoded;

    if (decoded is Map) {
      if (decoded['items'] is List) listAny = decoded['items'];
      else if (decoded['data'] is List) listAny = decoded['data'];
      else if (decoded['results'] is List) listAny = decoded['results'];
      else if (decoded['need'] is List) listAny = decoded['need'];
    }

    if (listAny is! List) return [];

    final result = <ClinicShiftNeed>[];
    for (final item in listAny) {
      if (item is Map) {
        try {
          result.add(ClinicShiftNeed.fromMap(Map<String, dynamic>.from(item)));
        } catch (e) {
          _log('decode item failed: $e item=$item');
        }
      }
    }

    result.sort((a, b) {
      final d = a.date.compareTo(b.date);
      if (d != 0) return d;
      return a.start.compareTo(b.start);
    });

    return result;
  }

  // --------------------------------------------------------------------------
  // ✅ Public APIs (ใช้โดย screens)
  // --------------------------------------------------------------------------

  /// ✅ โหลดรายการประกาศงาน (Admin: listClinicNeeds)
  /// GET /shift-needs
  static Future<List<ClinicShiftNeed>> loadAll(String clinicId) async {
    _log('GET ${ApiConfig.payrollBaseUrl}/shift-needs');

    final decoded = await _client.get('/shift-needs', auth: true);
    final list = _decodeListFromAny(decoded);

    final filtered = list.where((x) {
      final cid = x.clinicId.trim();
      return cid.isEmpty ? true : cid == clinicId;
    }).toList();

    _log('parsed items=${list.length} filtered=${filtered.length}');
    return filtered;
  }

  /// ✅ สร้างประกาศงาน (Admin: createNeed)
  /// POST /shift-needs
  static Future<void> add(String clinicId, ClinicShiftNeed need) async {
    final payload = need.toMap();
    payload['clinicId'] = clinicId;

    // normalize rate -> hourlyRate (ให้ตรง shiftNeedController.js)
    if (payload['hourlyRate'] == null ||
        (payload['hourlyRate'] is num && (payload['hourlyRate'] as num) <= 0)) {
      if (payload['rate'] != null) {
        payload['hourlyRate'] = payload['rate'];
      }
    }
    if (payload['hourlyRate'] == null && payload['hourly_rate'] != null) {
      payload['hourlyRate'] = payload['hourly_rate'];
    }

    _log('POST ${ApiConfig.payrollBaseUrl}/shift-needs payload=$payload');

    await _client.post(
      '/shift-needs',
      auth: true,
      body: payload,
    );
  }

  /// ✅ เปิดดูผู้สมัคร
  /// GET /shift-needs/:id/applicants
  static Future<List<dynamic>> loadApplicants(String needId) async {
    final sid = needId.trim();
    if (sid.isEmpty) return [];

    _log('GET ${ApiConfig.payrollBaseUrl}/shift-needs/$sid/applicants');

    final decoded = await _client.get(
      '/shift-needs/$sid/applicants',
      auth: true,
    );

    if (decoded is Map && decoded['applicants'] is List) {
      return List<dynamic>.from(decoded['applicants']);
    }

    // บาง backend อาจคืน list ตรง ๆ
    final data = decoded['data'];
    if (data is List) return data;

    return [];
  }

  /// ✅ “ยกเลิกประกาศงาน”
  /// PATCH /shift-needs/:id/cancel
  static Future<void> removeById(String clinicId, String id) async {
    final sid = id.trim();
    if (sid.isEmpty) return;

    _log('PATCH ${ApiConfig.payrollBaseUrl}/shift-needs/$sid/cancel');

    // backend บางตัวคืน 200/204 body ว่าง → ApiClient.patch รองรับแล้ว
    await _client.patch(
      '/shift-needs/$sid/cancel',
      auth: true,
    );
  }

  static Future<void> update(String clinicId, ClinicShiftNeed need) async {
    throw Exception('update ไม่รองรับ (backend ยังไม่มี PUT/PATCH สำหรับแก้ไขประกาศงาน)');
  }

  static Future<void> clear(String clinicId) async {
    throw Exception('clear ไม่รองรับในโหมด backend');
  }
}
