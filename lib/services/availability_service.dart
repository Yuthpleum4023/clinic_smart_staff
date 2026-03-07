// lib/services/availability_service.dart
//
// ✅ FINAL — USE ApiClient ONLY
// ใช้ payrollBaseUrl เพราะ route อยู่ที่ payroll_service: /availabilities
//
// Default endpoints (ปรับได้จุดเดียว):
// - list open (clinic view):   GET  /availabilities/open   (fallback -> /availabilities)
// - my list (helper view):     GET  /availabilities/me     (fallback -> /availabilities/my)
// - create/upsert (helper):    POST /availabilities
//
// Response รองรับหลายแบบ:
// - { items:[...] } / { data:[...] } / { availabilities:[...] } / [ ... ]
//
import 'package:flutter/foundation.dart';
import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/models/availability_model.dart';

class AvailabilityService {
  static void _log(String msg) {
    if (kDebugMode) debugPrint('📅 [AvailabilityService] $msg');
  }

  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  // -------------------------
  // ✅ Paths (ปรับตรงนี้จุดเดียว)
  // -------------------------
  static const String _base = '/availabilities';
  static const String _open = '/availabilities/open';
  static const String _me = '/availabilities/me';
  static const String _myAlt = '/availabilities/my';

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return List<dynamic>.from(decoded);
    if (decoded is! Map) return const [];

    if (decoded['items'] is List) return List<dynamic>.from(decoded['items']);
    if (decoded['data'] is List) return List<dynamic>.from(decoded['data']);
    if (decoded['results'] is List) return List<dynamic>.from(decoded['results']);
    if (decoded['availabilities'] is List) {
      return List<dynamic>.from(decoded['availabilities']);
    }

    // nested: data.items
    final data = decoded['data'];
    if (data is Map && data['items'] is List) return List<dynamic>.from(data['items']);
    if (data is Map && data['availabilities'] is List) {
      return List<dynamic>.from(data['availabilities']);
    }

    return const [];
  }

  static List<Availability> _toModels(dynamic decoded) {
    final list = _extractList(decoded);
    final out = <Availability>[];
    for (final it in list) {
      if (it is Map) {
        out.add(Availability.fromMap(Map<String, dynamic>.from(it)));
      }
    }
    return out;
  }

  // ======================================================
  // ✅ Clinic view: โหลด “ตารางว่างผู้ช่วย” (open)
  // ======================================================
  static Future<List<Availability>> listOpenForClinic() async {
    _log('GET ${ApiConfig.payrollBaseUrl}$_open');
    try {
      final decoded = await _client.get(_open, auth: true);
      return _toModels(decoded);
    } catch (e) {
      // fallback เผื่อ backend ยังไม่ได้ทำ /open
      _log('fallback GET ${ApiConfig.payrollBaseUrl}$_base because: $e');
      final decoded = await _client.get(_base, auth: true);
      return _toModels(decoded);
    }
  }

  // ======================================================
  // ✅ Helper view: โหลดตารางว่างของตัวเอง
  // ======================================================
  static Future<List<Availability>> listMine() async {
    _log('GET ${ApiConfig.payrollBaseUrl}$_me');
    try {
      final decoded = await _client.get(_me, auth: true);
      return _toModels(decoded);
    } catch (e) {
      // fallback เผื่อ backend ใช้ /my
      _log('fallback GET ${ApiConfig.payrollBaseUrl}$_myAlt because: $e');
      final decoded = await _client.get(_myAlt, auth: true);
      return _toModels(decoded);
    }
  }

  // ======================================================
  // ✅ Helper: สร้าง/บันทึกตารางว่าง
  // ======================================================
  static Future<dynamic> createAvailability(Availability a) async {
    final body = a.toCreatePayload();
    _log('POST ${ApiConfig.payrollBaseUrl}$_base body=$body');
    return _client.post(
      _base,
      auth: true,
      body: body,
    );
  }

  // ======================================================
  // ✅ Helper/Admin: ยกเลิก/ลบ availability
  // (ถ้า backend ไม่มี route นี้ ยังไม่ใช้ก็ได้)
  // ======================================================
  static Future<dynamic> cancelById(String id) async {
    final sid = id.trim();
    if (sid.isEmpty) throw Exception('availability id ว่าง');
    final path = '$_base/$sid/cancel';
    _log('PATCH ${ApiConfig.payrollBaseUrl}$path');
    return _client.patch(path, auth: true);
  }
}