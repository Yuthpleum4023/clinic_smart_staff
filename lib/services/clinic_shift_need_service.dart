// lib/services/clinic_shift_need_service.dart
//
// ✅ FINAL — USE ApiClient ONLY (single source of truth for Authorization)
// - ตัดการอ่าน token จาก SharedPreferences หลาย key (กัน jwt malformed)
// - ตัด payrollBaseUrl override จาก prefs (กันยิงผิด env)
// - ใช้ ApiConfig.payrollBaseUrl เท่านั้น
// - ใช้ ApiClient (sanitize token + Render-safe timeout) ทุก request
//
// ✅ FIX (สำคัญ): loadApplicants() รองรับ response หลายรูปแบบ
// - { applicants: [...] }
// - { items: [...] }
// - { data: [...] }
// - { data: { applicants: [...] } }
// - { result: { applicants: [...] } }
// - [ ... ]  (backend คืน list ตรง ๆ)
// และกัน crash กรณี decoded เป็น List / String / อื่น ๆ
//
// ✅ NEW:
// - approveApplicant(): POST /shift-needs/:id/approve (override path ได้)
// - submitEventScore(): POST /score/event (override path ได้)
// - createAttendanceEvent(): POST /score/attendance-events (override path ได้)  ✅ ตรง schema AttendanceEvent
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

  // --------------------------------------------------------------------------
  // ✅ Decode ShiftNeeds list (robust)
  // --------------------------------------------------------------------------
  static List<ClinicShiftNeed> _decodeListFromAny(dynamic decoded) {
    dynamic listAny = decoded;

    if (decoded is Map) {
      if (decoded['items'] is List) listAny = decoded['items'];
      else if (decoded['data'] is List) listAny = decoded['data'];
      else if (decoded['results'] is List) listAny = decoded['results'];
      else if (decoded['need'] is List) listAny = decoded['need'];
      else if (decoded['needs'] is List) listAny = decoded['needs'];
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
  // ✅ Applicants decoder (robust)
  // --------------------------------------------------------------------------
  static List<dynamic> _extractApplicantsAny(dynamic decoded) {
    // 1) backend คืน list ตรง ๆ
    if (decoded is List) return List<dynamic>.from(decoded);

    // 2) ป้องกัน non-map
    if (decoded is! Map) return [];

    // 3) รูปแบบมาตรฐาน
    if (decoded['applicants'] is List) {
      return List<dynamic>.from(decoded['applicants']);
    }

    // 4) บาง backend คืนเป็น items/data/results
    if (decoded['items'] is List) return List<dynamic>.from(decoded['items']);
    if (decoded['data'] is List) return List<dynamic>.from(decoded['data']);
    if (decoded['results'] is List) return List<dynamic>.from(decoded['results']);

    // 5) nested: data.applicants / result.applicants
    final data = decoded['data'];
    if (data is Map && data['applicants'] is List) {
      return List<dynamic>.from(data['applicants']);
    }
    final result = decoded['result'];
    if (result is Map && result['applicants'] is List) {
      return List<dynamic>.from(result['applicants']);
    }

    return [];
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

    final applicants = _extractApplicantsAny(decoded);
    _log('applicants=${applicants.length}');
    return applicants;
  }

  /// ✅ รับผู้สมัคร (approveApplicant)
  ///
  /// ⚠️ Backend ของท่านตอนนี้ controller คือ approveApplicant(req,res)
  /// แต่ "route" อาจจะเป็น:
  /// - POST /shift-needs/:id/approve
  /// - POST /shift-needs/:id/approve-applicant
  /// - POST /shift-needs/:id/applicants/approve
  ///
  /// ✅ ดังนั้นให้ override pathBuilder ได้
  ///
  /// default: POST /shift-needs/:id/approve   body: { staffId }
  static Future<dynamic> approveApplicant({
    required String needId,
    required String staffId,
    String Function(String needId)? pathBuilder,
  }) async {
    final sid = needId.trim();
    final st = staffId.trim();
    if (sid.isEmpty) throw Exception('needId ว่าง');
    if (st.isEmpty) throw Exception('staffId ว่าง');

    final path = (pathBuilder ?? ((id) => '/shift-needs/$id/approve'))(sid);

    _log('POST ${ApiConfig.payrollBaseUrl}$path body={staffId:$st}');

    final decoded = await _client.post(
      path,
      auth: true,
      body: {'staffId': st},
    );

    return decoded;
  }

  /// ✅ ส่งคะแนน Event (แบบ "rating 4 ช่อง") เพื่อไปคำนวณ TrustScore
  ///
  /// default: POST /score/event
  /// body ยืดหยุ่นตาม backend ท่าน (ส่งมาเป็น map ตรง ๆ)
  static Future<dynamic> submitEventScore({
    String path = '/score/event',
    required Map<String, dynamic> body,
  }) async {
    final p = path.trim().isEmpty ? '/score/event' : path.trim();

    _log('POST ${ApiConfig.payrollBaseUrl}$p body=$body');

    final decoded = await _client.post(
      p,
      auth: true,
      body: body,
    );

    return decoded;
  }

  /// ✅ Attendance Event (4 status) ตาม schema AttendanceEvent
  ///
  /// default: POST /score/attendance-events
  ///
  /// body:
  /// {
  ///  clinicId, staffId, shiftId,
  ///  status: completed|late|no_show|cancelled_early,
  ///  minutesLate,
  ///  occurredAt (ISO)
  /// }
  static Future<dynamic> createAttendanceEvent({
    String path = '/score/attendance-events',
    required String clinicId,
    required String staffId,
    required String shiftId,
    required String status,
    int minutesLate = 0,
    DateTime? occurredAt,
  }) async {
    final cid = clinicId.trim();
    final sid = staffId.trim();
    final shid = shiftId.trim();

    if (cid.isEmpty) throw Exception('clinicId ว่าง');
    if (sid.isEmpty) throw Exception('staffId ว่าง');
    if (shid.isEmpty) throw Exception('shiftId ว่าง');

    const allowed = {'completed', 'late', 'no_show', 'cancelled_early'};
    final st = status.trim();
    if (!allowed.contains(st)) {
      throw Exception('status ไม่ถูกต้อง: $st');
    }

    final when = (occurredAt ?? DateTime.now()).toUtc();

    final body = <String, dynamic>{
      'clinicId': cid,
      'staffId': sid,
      'shiftId': shid,
      'status': st,
      'minutesLate': (st == 'late') ? (minutesLate < 0 ? 0 : minutesLate) : 0,
      'occurredAt': when.toIso8601String(),
    };

    final p = path.trim().isEmpty ? '/score/attendance-events' : path.trim();

    _log('POST ${ApiConfig.payrollBaseUrl}$p body=$body');

    final decoded = await _client.post(
      p,
      auth: true,
      body: body,
    );

    return decoded;
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
    throw Exception(
      'update ไม่รองรับ (backend ยังไม่มี PUT/PATCH สำหรับแก้ไขประกาศงาน)',
    );
  }

  static Future<void> clear(String clinicId) async {
    throw Exception('clear ไม่รองรับในโหมด backend');
  }
}