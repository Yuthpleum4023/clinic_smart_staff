// lib/services/helper_availability_service.dart
//
// ✅ HelperAvailabilityService — FINAL (Backward compatible + per-helper key)
// - เดิม: เก็บรวมใน key เดียว = helper_availability_list
// - ใหม่: เก็บแยกต่อ helper = helper_availability_list_{helperId}
// - ✅ Migration อัตโนมัติ: ถ้ามีข้อมูลใน key เก่า จะย้ายไป key ใหม่ตาม helperId แล้วลบ key เก่า
// - ✅ API เดิมยังใช้ได้: loadAll/loadByHelper/add/update/remove
// - ✅ เพิ่ม export สำหรับส่งให้คลินิก/ดีบัก: exportByHelperMonth()
//
// หมายเหตุ:
// - ตอนนี้ยังเป็น local-only (SharedPreferences) ตามไฟล์เดิมคุณ
// - ถ้าจะ sync backend (ให้คลินิกเห็นจริง) ผมจะเพิ่มอีกไฟล์ API ทีหลัง
//

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/helper_availability_model.dart';

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
  // Decode helpers
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
      // ถ้าข้อมูลเก่าพัง/ว่าง ก็ลบทิ้งเพื่อกันโหลดซ้ำ
      await prefs.remove(_legacyKey);
      return;
    }

    // แยกตาม helperId
    final Map<String, List<HelperAvailability>> byHelper = {};
    for (final item in legacyList) {
      final hid = item.helperId.trim();
      if (hid.isEmpty) continue;
      byHelper.putIfAbsent(hid, () => []);
      byHelper[hid]!.add(item);
    }

    // เขียนลง key ใหม่
    for (final entry in byHelper.entries) {
      final k = _keyForHelper(entry.key);
      // merge กับของเดิม (ถ้ามี)
      final existingRaw = prefs.getString(k) ?? '';
      final existing = _decodeList(existingRaw);

      // merge by id (กันซ้ำ)
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

    // ลบ key เก่า เพื่อไม่ migrate ซ้ำ
    await prefs.remove(_legacyKey);
  }

  // -----------------------------
  // Public APIs
  // -----------------------------

  /// โหลดทั้งหมด (รวมทุก helper ที่เคยมีในเครื่อง)
  /// - จะพยายาม migrate ก่อน
  static Future<List<HelperAvailability>> loadAll() async {
    await _migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();

    // หา keys ที่ขึ้นต้นด้วย prefix
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList();
    final List<HelperAvailability> out = [];

    for (final k in keys) {
      final raw = prefs.getString(k) ?? '';
      out.addAll(_decodeList(raw));
    }

    return out;
  }

  /// โหลดของ helper คนเดียว
  static Future<List<HelperAvailability>> loadByHelper(String helperId) async {
    await _migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyForHelper(helperId)) ?? '';
    final list = _decodeList(raw);
    list.sort((a, b) => (a.date + a.start).compareTo(b.date + b.start));
    return list;
  }

  /// บันทึกทั้งหมด “ของ helper คนเดียว”
  static Future<void> saveByHelper(String helperId, List<HelperAvailability> list) async {
    await _migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForHelper(helperId), _encodeList(list));
  }

  /// เพิ่มรายการ (ใช้ item.helperId เป็นตัวกำหนด key)
  static Future<void> add(HelperAvailability item) async {
    final hid = item.helperId.trim();
    if (hid.isEmpty) return;

    final list = await loadByHelper(hid);
    list.add(item);
    await saveByHelper(hid, list);
  }

  /// ลบรายการด้วย id (ต้องรู้ helperId เพื่อไม่ต้อง scan ทั้งหมด)
  static Future<void> removeById(String id, {required String helperId}) async {
    final list = await loadByHelper(helperId);
    list.removeWhere((e) => e.id == id);
    await saveByHelper(helperId, list);
  }

  /// Update รายการด้วย id
  static Future<void> update(HelperAvailability updated) async {
    final hid = updated.helperId.trim();
    if (hid.isEmpty) return;

    final list = await loadByHelper(hid);
    final idx = list.indexWhere((e) => e.id == updated.id);
    if (idx >= 0) list[idx] = updated;
    await saveByHelper(hid, list);
  }

  // -----------------------------
  // ✅ Export utilities (สำหรับส่งให้คลินิก / ดีบัก / เตรียม sync)
  // -----------------------------

  /// export ข้อมูล helper (เฉพาะเดือน) เป็น JSON string
  /// - monthKey: "YYYY-MM" เช่น "2026-02"
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

  /// สำหรับกรณีต้อง “ล้างข้อมูลผู้ช่วยคนนี้” (ใช้ตอน logout/สลับบัญชี)
  static Future<void> clearHelper(String helperId) async {
    await _migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForHelper(helperId));
  }
}
