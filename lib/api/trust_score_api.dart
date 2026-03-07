// lib/api/trust_score_api.dart
//
// ✅ SUPER STABLE — TrustScore API (HARD MATCHED WITH BACKEND)
// - ใช้ ApiClient (Authorization source of truth)
// - Backend รับ status: completed | late | no_show | cancelled_early (ONLY)
// - ✅ Normalize alias ทั้งหมดให้ปลอดภัย + WHITELIST กันค่าหลุด
// - ✅ postAttendanceEvent ส่ง occurredAt (required)
// - ❌ ไม่มี fallback status (กัน request เพี้ยน)
//

import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';

class _StatusTry {
  final String primary;
  const _StatusTry(this.primary);
}

class TrustScoreApi {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.scoreBaseUrl);

  // ======================================================
  // helpers
  // ======================================================

  static const Set<String> _allowedStatuses = <String>{
    'completed',
    'late',
    'no_show',
    'cancelled_early',
  };

  static bool _looksLikeStaffId(String s) {
    final v = s.trim();
    return v.startsWith('stf_') && v.length >= 6;
  }

  static _StatusTry _normalizeStatusTry(String status) {
    final s = status.trim().toLowerCase();

    // ✅ Completed aliases
    if (s == 'done' ||
        s == 'complete' ||
        s == 'completed' ||
        s == 'finish' ||
        s == 'finished' ||
        s == 'success' ||
        s == 'ok') {
      return const _StatusTry('completed');
    }

    // ✅ Late aliases
    if (s == 'late' || s == 'delay' || s == 'delayed') {
      return const _StatusTry('late');
    }

    // ✅ No show aliases
    if (s == 'no_show' ||
        s == 'noshow' ||
        s == 'absent' ||
        s == 'no-show' ||
        s == 'no show' ||
        s == 'missing') {
      return const _StatusTry('no_show');
    }

    // ✅ Cancel early aliases (IMPORTANT)
    if (s == 'cancelled_early' ||
        s == 'canceled_early' ||
        s == 'cancel_early' ||
        s == 'cancel before start' ||
        s == 'cancel_before_start' ||
        s == 'cancelled_before_start' ||
        s == 'cancelled before start' ||
        s == 'cancel' ||
        s == 'canceled' ||
        s == 'cancelled') {
      return const _StatusTry('cancelled_early');
    }

    // ✅ HARD WHITELIST:
    // ถ้าค่าไม่อยู่ใน 4 ตัวนี้ ให้ default ไป "completed" หรือจะ throw ก็ได้
    // ผมเลือก "throw" เพื่อให้ dev เจอเร็ว ไม่ปล่อยให้ backend 400 เงียบ ๆ
    if (!_allowedStatuses.contains(s)) {
      throw Exception(
        'Invalid attendance status "$status". Allowed: completed | late | no_show | cancelled_early',
      );
    }

    return _StatusTry(s);
  }

  // ======================================================
  // Search staff
  // ======================================================
  static Future<List<Map<String, dynamic>>> searchStaff({
    required String q,
    int limit = 20,
    bool auth = true,
  }) async {
    final query = q.trim();
    if (query.isEmpty) return [];

    final path =
        '/score/staff/search?q=${Uri.encodeComponent(query)}&limit=$limit';

    final decoded = await _client.get(path, auth: auth);

    dynamic listAny = decoded;

    if (decoded is Map) {
      if (decoded['items'] is List) listAny = decoded['items'];
      else if (decoded['data'] is List) listAny = decoded['data'];
      else if (decoded['results'] is List) listAny = decoded['results'];
      else if (decoded['staff'] is List) listAny = decoded['staff'];
    }

    if (listAny is! List) return [];

    final out = <Map<String, dynamic>>[];
    for (final it in listAny) {
      if (it is Map) {
        out.add(Map<String, dynamic>.from(it));
      }
    }
    return out;
  }

  // ======================================================
  // Get score
  // ======================================================
  static Future<Map<String, dynamic>> getStaffScore({
    required String staffId,
    bool auth = true,
  }) async {
    return _client.get(
      ApiConfig.staffScore(staffId.trim()),
      auth: auth,
    );
  }

  // ======================================================
  // Lookup score
  // ======================================================
  static Future<Map<String, dynamic>> lookupStaffScore({
    required String input,
    bool auth = true,
    int searchLimit = 20,
  }) async {
    final raw = input.trim();

    if (raw.isEmpty) {
      throw Exception('กรุณากรอกชื่อ/เบอร์/หรือ staffId');
    }

    if (_looksLikeStaffId(raw)) {
      final score = await getStaffScore(staffId: raw, auth: auth);
      return {
        'ok': true,
        'staffId': raw,
        'score': score,
      };
    }

    final candidates = await searchStaff(q: raw, limit: searchLimit, auth: auth);

    if (candidates.isEmpty) {
      throw Exception('ไม่พบผู้ช่วยจากคำค้น: "$raw"');
    }

    String pickedStaffId = '';
    for (final c in candidates) {
      final sid = (c['staffId'] ?? c['id'] ?? '').toString().trim();
      if (_looksLikeStaffId(sid)) {
        pickedStaffId = sid;
        break;
      }
    }

    if (pickedStaffId.isEmpty) {
      throw Exception('ค้นหาเจอ แต่ไม่มี staffId');
    }

    final score = await getStaffScore(staffId: pickedStaffId, auth: auth);

    return {
      'ok': true,
      'staffId': pickedStaffId,
      'score': score,
      'candidates': candidates,
    };
  }

  // ======================================================
  // POST Attendance Event
  // ======================================================
  static Future<Map<String, dynamic>> postAttendanceEvent({
    required String clinicId,
    required String staffId,
    required String status,
    String shiftId = '',
    int minutesLate = 0,
    DateTime? occurredAt,
    bool auth = true,
  }) async {
    final cid = clinicId.trim();
    final sid = staffId.trim();

    if (cid.isEmpty) throw Exception('clinicId is required');
    if (sid.isEmpty) throw Exception('staffId is required');

    final stTry = _normalizeStatusTry(status);

    final when = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();

    return _client.post(
      ApiConfig.attendanceEvent,
      auth: auth,
      body: {
        'clinicId': cid,
        'staffId': sid,
        'shiftId': shiftId.trim(),
        'status': stTry.primary, // ✅ guaranteed allowed
        'minutesLate': (minutesLate < 0) ? 0 : minutesLate,
        'occurredAt': when, // ✅ REQUIRED
      },
    );
  }
}