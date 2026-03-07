// lib/services/score_service.dart
//
// ✅ FINAL — USE ApiClient ONLY (single source of truth for Authorization)
// - ใช้ ApiClient ที่ sanitize token + Render-safe timeout
// - ใช้ ApiConfig.scoreBaseUrl + endpoint จาก ApiConfig (mount /score)
//
// ✅ FIX: postAttendanceEvent ไม่ต้องส่ง clinicId จากหน้าจอแล้ว
// - service จะหา clinicId ให้เอง (prefs -> jwt fallback)
// - ส่ง occurredAt ให้ตรง model AttendanceEventSchema (required)
//
// AttendanceEventSchema:
// - clinicId (required)
// - staffId (required)
// - shiftId (optional)
// - status: completed | late | no_show | cancelled_early
// - minutesLate (optional)
// - occurredAt (required)
//
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/models/staff_score_model.dart';

class ScoreService {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.scoreBaseUrl);

  // ======================================================
  // Helpers
  // ======================================================
  static const _clinicIdKeys = [
    'app_clinic_id',
    'clinicId',
    'clinic_id',
    'clnId',
  ];

  static const _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
    'accessToken',
    'access_token',
  ];

  static Future<String?> _getClinicIdFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _clinicIdKeys) {
      final v = prefs.getString(k);
      if (v != null && v.trim().isNotEmpty && v != 'null') return v.trim();
    }
    return null;
  }

  static Future<String?> _getTokenFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  static String? _clinicIdFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;

      String normalize(String s) {
        var out = s.replaceAll('-', '+').replaceAll('_', '/');
        while (out.length % 4 != 0) {
          out += '=';
        }
        return out;
      }

      final payload = utf8.decode(base64Decode(normalize(parts[1])));
      final map = jsonDecode(payload);

      if (map is Map) {
        final cid = (map['clinicId'] ?? map['clinic_id'] ?? '').toString().trim();
        if (cid.isNotEmpty && cid != 'null') return cid;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  static Future<String> _requireClinicId() async {
    final fromPrefs = await _getClinicIdFromPrefs();
    if (fromPrefs != null) return fromPrefs;

    final token = await _getTokenFromPrefs();
    if (token != null) {
      final fromJwt = _clinicIdFromJwt(token);
      if (fromJwt != null) return fromJwt;
    }

    throw Exception('หา clinicId ไม่เจอ (ลองกลับหน้า Home แล้วเข้าใหม่ / หรือเช็คว่า token มี clinicId)');
  }

  // ======================================================
  // GET /score/staff/:staffId/score   (ตาม ApiConfig.staffScore)
  // ======================================================
  static Future<StaffScore> getStaffScore(String staffId) async {
    final sid = staffId.trim();
    if (sid.isEmpty) {
      throw Exception('staffId is required');
    }

    final decoded = await _client.get(
      ApiConfig.staffScore(sid),
      auth: true,
    );

    final dynamic payload = (decoded is Map)
        ? (decoded['data'] ?? decoded['score'] ?? decoded)
        : decoded;

    if (payload is Map<String, dynamic>) {
      return StaffScore.fromMap(payload);
    }
    if (payload is Map) {
      return StaffScore.fromMap(Map<String, dynamic>.from(payload));
    }
    throw Exception('Invalid staff score response: ${payload.runtimeType}');
  }

  // ======================================================
  // POST /score/events/attendance   (ตาม ApiConfig.attendanceEvent)
  // ======================================================
  static Future<Map<String, dynamic>> postAttendanceEvent({
    // ❌ ไม่ต้องส่ง clinicId แล้ว (service หาให้เอง)
    required String staffId,
    String shiftId = '',
    required String status, // completed|late|no_show|cancelled_early
    int minutesLate = 0,
    DateTime? occurredAt, // ✅ required by schema
    bool auth = true,
  }) async {
    final sid = staffId.trim();
    if (sid.isEmpty) throw Exception('staffId is required');

    // ✅ normalize status to match enum
    final st = status.trim().toLowerCase();
    const allowed = {'completed', 'late', 'no_show', 'cancelled_early'};
    if (!allowed.contains(st)) {
      throw Exception('invalid status: $status (allowed: $allowed)');
    }

    final cid = await _requireClinicId();
    final shid = shiftId.trim();
    final mins = (minutesLate < 0) ? 0 : minutesLate;

    return _client.post(
      ApiConfig.attendanceEvent,
      auth: auth,
      body: <String, dynamic>{
        'clinicId': cid,
        'staffId': sid,
        'shiftId': shid,
        'status': st,
        'minutesLate': mins,
        'occurredAt': (occurredAt ?? DateTime.now()).toIso8601String(),
      },
    );
  }
}