// lib/services/helper_availability_service.dart
//
// ✅ HelperAvailabilityService — FINAL (Local + Remote API) — Backward compatible
// - ✅ Local-only เดิมยังอยู่ครบ: loadAll/loadByHelper/add/update/remove/export/clearHelper
// - ✅ เพิ่ม Remote API (payroll_service):
//    - addRemote()            -> POST   /availabilities
//    - listMyRemote()         -> GET    /availabilities/me
//    - listOpenRemote(date)   -> GET    /availabilities/open?date=YYYY-MM-DD   (admin only)
//
// NOTE:
// - Remote จะใช้ token เป็น source of truth (staffId/fullName/phone เติมจาก backend)
// - ตอนนี้เน้นให้ยิงจริงก่อน (ยังไม่ sync local<->remote)
//

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../models/helper_availability_model.dart';
import '../api/api_config.dart';
import '../services/auth_storage.dart';

class HelperAvailabilityService {
  // -----------------------------
  // OLD KEY (backward compatible)
  // -----------------------------
  static const String _legacyKey = 'helper_availability_list';

  // -----------------------------
  // NEW KEY PREFIX (per helper)
  // -----------------------------
  static const String _keyPrefix = 'helper_availability_list_';
  static String _keyForHelper(String helperId) => '$_keyPrefix$helperId';

  // -----------------------------
  // Decode helpers (local)
  // -----------------------------
  static List<HelperAvailability> _decodeList(String raw) {
    if (raw.isEmpty) return [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => HelperAvailability.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _encodeList(List<HelperAvailability> list) {
    final data = list.map((e) => e.toMap()).toList();
    return json.encode(data);
  }

  // -----------------------------
  // ✅ Migration: legacy -> per-helper keys
  // -----------------------------
  static Future<void> _migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    final legacy = prefs.getString(_legacyKey);
    if (legacy == null || legacy.isEmpty) return;

    final legacyList = _decodeList(legacy);
    if (legacyList.isEmpty) {
      await prefs.remove(_legacyKey);
      return;
    }

    final Map<String, List<HelperAvailability>> byHelper = {};
    for (final item in legacyList) {
      final hid = item.helperId.trim();
      if (hid.isEmpty) continue;
      byHelper.putIfAbsent(hid, () => []);
      byHelper[hid]!.add(item);
    }

    for (final entry in byHelper.entries) {
      final k = _keyForHelper(entry.key);
      final existingRaw = prefs.getString(k) ?? '';
      final existing = _decodeList(existingRaw);

      final Map<String, HelperAvailability> map = {
        for (final e in existing) e.id: e,
      };
      for (final e in entry.value) {
        map[e.id] = e;
      }

      final merged = map.values.toList()
        ..sort((a, b) => (a.date + a.start).compareTo(b.date + b.start));

      await prefs.setString(k, _encodeList(merged));
    }

    await prefs.remove(_legacyKey);
  }

  // -----------------------------
  // Public APIs (LOCAL)
  // -----------------------------
  static Future<List<HelperAvailability>> loadAll() async {
    await _migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();

    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList();
    final List<HelperAvailability> out = [];

    for (final k in keys) {
      final raw = prefs.getString(k) ?? '';
      out.addAll(_decodeList(raw));
    }

    return out;
  }

  static Future<List<HelperAvailability>> loadByHelper(String helperId) async {
    await _migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyForHelper(helperId)) ?? '';
    final list = _decodeList(raw);
    list.sort((a, b) => (a.date + a.start).compareTo(b.date + b.start));
    return list;
  }

  static Future<void> saveByHelper(String helperId, List<HelperAvailability> list) async {
    await _migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForHelper(helperId), _encodeList(list));
  }

  static Future<void> add(HelperAvailability item) async {
    final hid = item.helperId.trim();
    if (hid.isEmpty) return;

    final list = await loadByHelper(hid);
    list.add(item);
    await saveByHelper(hid, list);
  }

  static Future<void> removeById(String id, {required String helperId}) async {
    final list = await loadByHelper(helperId);
    list.removeWhere((e) => e.id == id);
    await saveByHelper(helperId, list);
  }

  static Future<void> update(HelperAvailability updated) async {
    final hid = updated.helperId.trim();
    if (hid.isEmpty) return;

    final list = await loadByHelper(hid);
    final idx = list.indexWhere((e) => e.id == updated.id);
    if (idx >= 0) list[idx] = updated;
    await saveByHelper(hid, list);
  }

  static Future<String> exportByHelperMonth({
    required String helperId,
    required String monthKey,
  }) async {
    final list = await loadByHelper(helperId);
    final filtered = list.where((e) => e.date.startsWith(monthKey)).toList();
    final data = filtered.map((e) => e.toMap()).toList();
    return json.encode({
      'helperId': helperId,
      'month': monthKey,
      'items': data,
    });
  }

  static Future<void> clearHelper(String helperId) async {
    await _migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForHelper(helperId));
  }

  // ======================================================================
  // REMOTE API (payroll_service)
  // ======================================================================

  static String _basePayroll() {
    final b = ApiConfig.payrollBaseUrl.trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  static Future<String> _requireToken() async {
    // ⚠️ ถ้าโปรเจกต์ท่านชื่อเมธอดต่าง (เช่น readToken()) บอกผม เดี๋ยวปรับ
    final token = (await AuthStorage.getToken())?.trim() ?? '';
    if (token.isEmpty) throw Exception('unauthorized: missing token');
    return token;
  }

  static Map<String, dynamic> _decodeJson(http.Response r) {
    try {
      return json.decode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return {'message': r.body};
    }
  }

  static Exception _httpError(http.Response r) {
    final body = _decodeJson(r);
    final msg = (body['message'] ?? body['error'] ?? 'request failed').toString();
    return Exception('${r.statusCode}: $msg');
  }

  /// ✅ POST /availabilities
  /// backend จะเติม staffId/fullName/phone จาก token ให้เอง
  static Future<Map<String, dynamic>> addRemote({
    required String date, // YYYY-MM-DD
    required String start, // HH:mm
    required String end, // HH:mm
    required String role,
    String note = '',
  }) async {
    final token = await _requireToken();
    final url = Uri.parse('${_basePayroll()}/availabilities');

    final payload = {
      'date': date,
      'start': start,
      'end': end,
      'role': role,
      'note': note,
    };

    final r = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(payload),
    );

    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw _httpError(r);
    }

    final body = _decodeJson(r);
    final av = (body['availability'] ?? body['item'] ?? body);

    if (av is Map) return Map<String, dynamic>.from(av);
    return Map<String, dynamic>.from(body);
  }

  /// ✅ GET /availabilities/me
  static Future<List<Map<String, dynamic>>> listMyRemote() async {
    final token = await _requireToken();
    final url = Uri.parse('${_basePayroll()}/availabilities/me');

    final r = await http.get(url, headers: {'Authorization': 'Bearer $token'});

    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw _httpError(r);
    }

    final body = _decodeJson(r);
    final items = (body['items'] ?? body['availabilities'] ?? []) as List;
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// ✅ GET /availabilities/open?date=YYYY-MM-DD  (admin only)
  static Future<List<Map<String, dynamic>>> listOpenRemote({
    required String date,
  }) async {
    final token = await _requireToken();
    final url = Uri.parse('${_basePayroll()}/availabilities/open?date=$date');

    final r = await http.get(url, headers: {'Authorization': 'Bearer $token'});

    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw _httpError(r);
    }

    final body = _decodeJson(r);
    final items = (body['items'] ?? []) as List;
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}