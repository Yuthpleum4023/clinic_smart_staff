// lib/services/clinic_shift_need_service.dart
import 'dart:convert';
import 'dart:convert' show base64, utf8;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_payroll/models/clinic_shift_need_model.dart';
import 'package:clinic_payroll/api/api_config.dart';

class ClinicShiftNeedService {
  // --------------------------------------------------------------------------
  // ✅ CONFIG / PREF KEYS
  // --------------------------------------------------------------------------

  static const List<String> _payrollUrlKeys = [
    'payrollBaseUrl',
    'payroll_base_url',
    'PAYROLL_BASE_URL',
    'api_payroll_base_url',
  ];

  static const List<String> _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
    'accessToken',
    'access_token',
  ];

  // --------------------------------------------------------------------------
  // ✅ Logging helper
  // --------------------------------------------------------------------------
  static void _log(String msg) {
    if (kDebugMode) {
      debugPrint('🧩 [ShiftNeedService] $msg');
    }
  }

  // --------------------------------------------------------------------------
  // ✅ Helpers
  // --------------------------------------------------------------------------

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  /// ✅ RESET baseUrl ที่เคยถูกเซฟค้างไว้ (กัน prefs ทับ DEV_HOST)
  static Future<void> resetSavedPayrollBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _payrollUrlKeys) {
      await prefs.remove(k);
    }
    _log('resetSavedPayrollBaseUrl: removed ${_payrollUrlKeys.join(", ")}');
  }

  /// ✅ DEV: ใช้ ApiConfig.payrollBaseUrl เท่านั้น (ห้าม prefs ทับ)
  /// ✅ PROD: ค่อยอนุญาตให้ override ผ่าน prefs ได้ (ถ้าคุณต้องการ)
  static Future<String> _getPayrollBaseUrl() async {
    // ---------- 1) เอาจาก ApiConfig ก่อนเสมอ ----------
    String raw = ApiConfig.payrollBaseUrl;

    // ---------- 2) ถ้าเป็น PROD ค่อยยอมให้ prefs override (optional) ----------
    // ถ้าคุณไม่ต้องการ override ใน prod ด้วย ให้ลบ block นี้ทิ้งได้
    if (ApiConfig.isProd) {
      final prefs = await SharedPreferences.getInstance();
      for (final k in _payrollUrlKeys) {
        final v = prefs.getString(k);
        if (v != null && v.trim().isNotEmpty && v != 'null') {
          raw = v.trim();
          break;
        }
      }
    }

    var base = raw.trim();

    // ตัด trailing slash
    base = base.replaceAll(RegExp(r'\/+$'), '');

    // กัน baseUrl ที่คนชอบเก็บเป็น .../api หรือ .../payroll หรือ .../shift-needs
    base = _stripSuffix(base, '/api');
    base = _stripSuffix(base, '/payroll');
    base = _stripSuffix(base, '/shift-needs');
    base = _stripSuffix(base, '/shift_needs');

    _log('baseUrl(raw)=$raw');
    _log('baseUrl(sanitized)=$base');

    return base;
  }

  static String _stripSuffix(String base, String suffix) {
    if (base.toLowerCase().endsWith(suffix.toLowerCase())) {
      return base.substring(0, base.length - suffix.length).replaceAll(RegExp(r'\/+$'), '');
    }
    return base;
  }

  static Future<Map<String, String>> _headers({required bool auth}) async {
    final h = <String, String>{
      'Content-Type': 'application/json',
    };

    if (auth) {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        throw Exception('no token (กรุณา login ก่อน)');
      }
      h['Authorization'] = 'Bearer $token';
    }

    return h;
  }

  /// join url แบบกัน double slash
  static Uri _u(String baseUrl, String path) {
    final b = baseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$b$p');
  }

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

  static Exception _httpError(String action, http.Response res) {
    try {
      final j = json.decode(res.body);
      if (j is Map && j['message'] != null) {
        return Exception('$action failed: ${res.statusCode} ${j['message']}');
      }
    } catch (_) {}
    return Exception('$action failed: ${res.statusCode} ${res.reasonPhrase ?? ''} body=${res.body}');
  }

  static String _shortToken(String t) {
    if (t.length <= 18) return t;
    return '${t.substring(0, 8)}...${t.substring(t.length - 6)}';
  }

  // --------------------------------------------------------------------------
  // ✅ Public APIs (ใช้โดย screens)
  // --------------------------------------------------------------------------

  /// ✅ โหลดรายการประกาศงาน (Admin: listClinicNeeds)
  /// GET /shift-needs
  static Future<List<ClinicShiftNeed>> loadAll(String clinicId) async {
    final baseUrl = await _getPayrollBaseUrl();
    final headers = await _headers(auth: true);
    final url = _u(baseUrl, '/shift-needs');

    _log('GET $url');
    _log('headers: auth=${headers.containsKey('Authorization') ? "yes" : "no"}');
    if (headers['Authorization'] != null) {
      _log('Authorization: Bearer ${_shortToken(headers['Authorization']!.replaceFirst("Bearer ", ""))}');
    }

    final res = await http.get(url, headers: headers);

    _log('response status=${res.statusCode}');
    _log('response body=${res.body}');

    if (res.statusCode == 200) {
      final decoded = json.decode(res.body);
      final list = _decodeListFromAny(decoded);

      final filtered = list.where((x) {
        final cid = x.clinicId.trim();
        return cid.isEmpty ? true : cid == clinicId;
      }).toList();

      _log('parsed items=${list.length} filtered=${filtered.length}');
      return filtered;
    }

    if (res.statusCode == 401) {
      throw Exception('Missing token / Unauthorized (กรุณา login ใหม่)');
    }

    throw _httpError('loadAll', res);
  }

  /// ✅ สร้างประกาศงาน (Admin: createNeed)
  /// POST /shift-needs
  static Future<void> add(String clinicId, ClinicShiftNeed need) async {
    final baseUrl = await _getPayrollBaseUrl();
    final headers = await _headers(auth: true);
    final url = _u(baseUrl, '/shift-needs');

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

    _log('POST $url');
    _log('payload=${json.encode(payload)}');

    final res = await http.post(
      url,
      headers: headers,
      body: json.encode(payload),
    );

    _log('response status=${res.statusCode}');
    _log('response body=${res.body}');

    if (res.statusCode == 200 || res.statusCode == 201) return;

    if (res.statusCode == 401) {
      throw Exception('Missing token / Unauthorized (กรุณา login ใหม่)');
    }

    throw _httpError('createNeed', res);
  }

  /// ✅ เปิดดูผู้สมัคร
  /// GET /shift-needs/:id/applicants
  static Future<List<dynamic>> loadApplicants(String needId) async {
    final baseUrl = await _getPayrollBaseUrl();
    final headers = await _headers(auth: true);
    final url = _u(baseUrl, '/shift-needs/$needId/applicants');

    _log('GET $url');

    final res = await http.get(url, headers: headers);

    _log('response status=${res.statusCode}');
    _log('response body=${res.body}');

    if (res.statusCode == 200) {
      final decoded = json.decode(res.body);
      if (decoded is Map && decoded['applicants'] is List) {
        return List<dynamic>.from(decoded['applicants']);
      }
      if (decoded is List) return decoded;
      return [];
    }

    if (res.statusCode == 401) {
      throw Exception('Missing token / Unauthorized (กรุณา login ใหม่)');
    }

    throw _httpError('loadApplicants', res);
  }

  /// ✅ “ยกเลิกประกาศงาน”
  /// PATCH /shift-needs/:id/cancel
  static Future<void> removeById(String clinicId, String id) async {
    final baseUrl = await _getPayrollBaseUrl();
    final headers = await _headers(auth: true);

    final sid = id.trim();
    if (sid.isEmpty) return;

    final url = _u(baseUrl, '/shift-needs/$sid/cancel');
    _log('PATCH $url');

    final res = await http.patch(url, headers: headers);

    _log('response status=${res.statusCode}');
    _log('response body=${res.body}');

    if (res.statusCode == 200 || res.statusCode == 204) return;

    if (res.statusCode == 401) {
      throw Exception('Missing token / Unauthorized (กรุณา login ใหม่)');
    }

    throw _httpError('cancelNeed', res);
  }

  static Future<void> update(String clinicId, ClinicShiftNeed need) async {
    throw Exception('update ไม่รองรับ (backend ยังไม่มี PUT/PATCH สำหรับแก้ไขประกาศงาน)');
  }

  static Future<void> clear(String clinicId) async {
    throw Exception('clear ไม่รองรับในโหมด backend');
  }
}
