// lib/api/trust_score_api.dart
//
// ✅ PRODUCTION TrustScoreApi
// ------------------------------------------------------
// ✅ Search helper by name / phone / keyword
// ✅ Get score by either:
//    - stf_xxx via /score/staff/:staffId/score
//    - usr_xxx via /helpers/:userId/score
//
// ✅ Important production fix:
//    Some UI flows call getStaffScore(staffId: sid)
//    even when sid is actually usr_xxx.
//    This file now auto-detects usr_xxx and routes to helper score endpoint.
// ------------------------------------------------------

import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';

class _StatusTry {
  final String primary;
  const _StatusTry(this.primary);
}

class TrustScoreApi {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.scoreBaseUrl);

  // ======================================================
  // Helpers
  // ======================================================

  static const Set<String> _allowedStatuses = <String>{
    'completed',
    'late',
    'no_show',
    'cancelled_early',
  };

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static bool _looksLikeStaffId(String v) {
    final x = v.trim();
    return x.startsWith('stf_') && x.length >= 6;
  }

  static bool _looksLikeUserId(String v) {
    final x = v.trim();
    return x.startsWith('usr_') && x.length >= 6;
  }

  static bool _looksLikeAnyScoreId(String v) {
    return _looksLikeStaffId(v) || _looksLikeUserId(v);
  }

  static _StatusTry _normalizeStatusTry(String status) {
    final s = status.trim().toLowerCase();

    if (s == 'done' ||
        s == 'complete' ||
        s == 'completed' ||
        s == 'finish' ||
        s == 'finished' ||
        s == 'success' ||
        s == 'ok') {
      return const _StatusTry('completed');
    }

    if (s == 'late' || s == 'delay' || s == 'delayed') {
      return const _StatusTry('late');
    }

    if (s == 'no_show' ||
        s == 'noshow' ||
        s == 'absent' ||
        s == 'no-show' ||
        s == 'no show' ||
        s == 'missing') {
      return const _StatusTry('no_show');
    }

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

    if (!_allowedStatuses.contains(s)) {
      throw Exception(
        'Invalid attendance status "$status". Allowed: completed | late | no_show | cancelled_early',
      );
    }

    return _StatusTry(s);
  }

  static List<Map<String, dynamic>> _extractList(dynamic decoded) {
    dynamic listAny = decoded;

    if (decoded is Map) {
      if (decoded['items'] is List) {
        listAny = decoded['items'];
      } else if (decoded['data'] is List) {
        listAny = decoded['data'];
      } else if (decoded['results'] is List) {
        listAny = decoded['results'];
      } else if (decoded['helpers'] is List) {
        listAny = decoded['helpers'];
      } else if (decoded['staff'] is List) {
        listAny = decoded['staff'];
      }
    }

    if (listAny is! List) return <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];
    for (final it in listAny) {
      if (it is Map) {
        out.add(Map<String, dynamic>.from(it));
      }
    }

    return out;
  }

  static Map<String, dynamic> _asMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  // ======================================================
  // Search helpers by name / phone / keyword
  // IMPORTANT:
  // use helper search endpoint, not staff search
  // ======================================================
  static Future<List<Map<String, dynamic>>> searchHelpers({
    required String q,
    int limit = 20,
    bool auth = true,
  }) async {
    final query = q.trim();
    if (query.isEmpty) return [];

    final safeLimit = limit <= 0 ? 20 : limit.clamp(1, 50);
    final path =
        '/helpers/search?q=${Uri.encodeComponent(query)}&limit=$safeLimit';

    final decoded = await _client.get(path, auth: auth);
    return _extractList(decoded);
  }

  // ======================================================
  // Legacy staff search
  // Keep for compatibility. Internally uses helper search.
  // ======================================================
  static Future<List<Map<String, dynamic>>> searchStaff({
    required String q,
    int limit = 20,
    bool auth = true,
  }) async {
    return searchHelpers(q: q, limit: limit, auth: auth);
  }

  // ======================================================
  // Get score by staffId / userId
  //
  // ✅ Production fix:
  // Some screens call getStaffScore(staffId: sid), but sid can be usr_xxx.
  // If sid is usr_xxx, route to /helpers/:userId/score automatically.
  // ======================================================
  static Future<Map<String, dynamic>> getStaffScore({
    required String staffId,
    bool auth = true,
  }) async {
    final id = staffId.trim();

    if (id.isEmpty) {
      throw Exception('staffId is required');
    }

    if (_looksLikeUserId(id)) {
      return getHelperScoreByUserId(userId: id, auth: auth);
    }

    return _asMap(
      await _client.get(
        ApiConfig.staffScore(id),
        auth: auth,
      ),
    );
  }

  // ======================================================
  // Get helper score by userId
  // ======================================================
  static Future<Map<String, dynamic>> getHelperScoreByUserId({
    required String userId,
    bool auth = true,
  }) async {
    final uid = userId.trim();

    if (uid.isEmpty) {
      throw Exception('userId is required');
    }

    return _asMap(
      await _client.get(
        '/helpers/${Uri.encodeComponent(uid)}/score',
        auth: auth,
      ),
    );
  }

  // ======================================================
  // Get score by either usr_xxx / stf_xxx
  // ======================================================
  static Future<Map<String, dynamic>> getScoreByIdentity({
    required String id,
    bool auth = true,
  }) async {
    final x = id.trim();

    if (x.isEmpty) {
      throw Exception('id is required');
    }

    if (_looksLikeUserId(x)) {
      return getHelperScoreByUserId(userId: x, auth: auth);
    }

    return getStaffScore(staffId: x, auth: auth);
  }

  // ======================================================
  // Lookup score by input
  // - staffId -> staff score
  // - userId -> helper score
  // - name/phone -> search helper first, then fetch score by picked id
  // ======================================================
  static Future<Map<String, dynamic>> lookupStaffScore({
    required String input,
    bool auth = true,
    int searchLimit = 20,
  }) async {
    final raw = input.trim();

    if (raw.isEmpty) {
      throw Exception('กรุณากรอกชื่อผู้ช่วย เบอร์ หรือ staffId');
    }

    if (_looksLikeStaffId(raw)) {
      final score = await getStaffScore(staffId: raw, auth: auth);
      return {
        'ok': true,
        'mode': 'staffId',
        'staffId': raw,
        'score': score,
      };
    }

    if (_looksLikeUserId(raw)) {
      final score = await getHelperScoreByUserId(userId: raw, auth: auth);
      return {
        'ok': true,
        'mode': 'userId',
        'userId': raw,
        'score': score,
      };
    }

    final candidates = await searchHelpers(
      q: raw,
      limit: searchLimit,
      auth: auth,
    );

    if (candidates.isEmpty) {
      throw Exception('ไม่พบผู้ช่วยที่ตรงกับข้อมูล');
    }

    Map<String, dynamic>? picked;
    final q = raw.toLowerCase();

    // 1) prefer exact-ish fullName/name/phone match
    for (final c in candidates) {
      final fullName = _s(c['fullName']).toLowerCase();
      final name = _s(c['name']).toLowerCase();
      final phone = _s(c['phone']).toLowerCase();

      if (fullName == q || name == q || phone == q) {
        picked = c;
        break;
      }
    }

    // 2) fallback to first candidate
    picked ??= candidates.first;

    final pickedUserId = _s(picked['userId']);
    final pickedStaffId = _s(picked['staffId']);

    Map<String, dynamic> score;
    String mode;

    if (_looksLikeUserId(pickedUserId)) {
      score = await getHelperScoreByUserId(
        userId: pickedUserId,
        auth: auth,
      );
      mode = 'search_userId';
    } else if (_looksLikeAnyScoreId(pickedStaffId)) {
      score = await getStaffScore(
        staffId: pickedStaffId,
        auth: auth,
      );
      mode = _looksLikeUserId(pickedStaffId)
          ? 'search_staffId_as_userId'
          : 'search_staffId';
    } else {
      throw Exception('ค้นหาเจอแล้ว แต่ข้อมูลผู้ช่วยไม่ครบ (ไม่มี userId/staffId)');
    }

    return {
      'ok': true,
      'mode': mode,
      'query': raw,
      'picked': picked,
      'staffId': pickedStaffId,
      'userId': pickedUserId,
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

    return _asMap(
      await _client.post(
        ApiConfig.attendanceEvent,
        auth: auth,
        body: {
          'clinicId': cid,
          'staffId': sid,
          'shiftId': shiftId.trim(),
          'status': stTry.primary,
          'minutesLate': (minutesLate < 0) ? 0 : minutesLate,
          'occurredAt': when,
        },
      ),
    );
  }
}