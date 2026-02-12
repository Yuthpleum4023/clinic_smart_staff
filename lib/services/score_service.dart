import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_payroll/models/staff_score_model.dart';
import 'package:clinic_payroll/api/api_config.dart';

class ScoreService {
  // ===============================
  // Base URL (ใช้ scoreBaseUrl)
  // ===============================
  static String get _base {
    final b = ApiConfig.scoreBaseUrl; // ✅ FIX: จาก baseUrl -> scoreBaseUrl
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  // ===============================
  // Auth token
  // ===============================
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
    ]) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  static Future<Map<String, String>> _headers() async {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final t = await _getToken();
    if (t != null && t.isNotEmpty) {
      h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  // ===============================
  // Helpers
  // ===============================
  static Map<String, dynamic> _decode(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    } catch (_) {
      return {'raw': body};
    }
  }

  static Exception _httpError(int code, String body) {
    final m = _decode(body);
    final msg = (m['message'] ?? m['error'] ?? 'HTTP $code').toString();
    return Exception('ScoreService error ($code): $msg');
  }

  // ======================================================
  // GET /staff/:staffId/score
  // ======================================================
  static Future<StaffScore> getStaffScore(String staffId) async {
    final sid = staffId.trim();
    if (sid.isEmpty) {
      throw Exception('staffId is required');
    }

    final path = ApiConfig.staffScore(sid);
    final uri = Uri.parse('$_base$path');

    final resp = await http.get(uri, headers: await _headers());

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final map = _decode(resp.body);
      return StaffScore.fromMap(map);
    }

    throw _httpError(resp.statusCode, resp.body);
  }

  // ======================================================
  // POST /events/attendance
  // ======================================================
  static Future<Map<String, dynamic>> postAttendanceEvent({
    required String clinicId,
    required String staffId,
    String shiftId = '',
    required String status, // completed|late|cancelled_early|no_show
    int minutesLate = 0,
  }) async {
    final uri = Uri.parse('$_base${ApiConfig.attendanceEvent}');

    final body = {
      'clinicId': clinicId,
      'staffId': staffId,
      'shiftId': shiftId,
      'status': status,
      'minutesLate': minutesLate,
    };

    final resp = await http.post(
      uri,
      headers: await _headers(),
      body: json.encode(body),
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return _decode(resp.body);
    }

    throw _httpError(resp.statusCode, resp.body);
  }
}
