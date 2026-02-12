import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/holiday_model.dart';

class HolidayService {
  static const String _key = 'holiday_list';

  // =========================
  // Load
  // =========================
  static Future<List<Holiday>> loadHolidays() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return [];

      final List<Holiday> result = [];

      for (final item in decoded) {
        if (item is Map) {
          try {
            final map = Map<String, dynamic>.from(item);
            result.add(Holiday.fromMap(map));
          } catch (_) {
            // ❌ record พัง → ข้าม
          }
        }
      }

      return result;
    } catch (_) {
      // ❌ JSON พัง → ไม่เด้ง
      return [];
    }
  }

  // =========================
  // Save
  // =========================
  static Future<void> saveHolidays(List<Holiday> holidays) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final data = holidays.map((e) => e.toMap()).toList();
      await prefs.setString(_key, json.encode(data));
    } catch (_) {
      // ไม่ throw เพื่อกันแอปเด้ง
    }
  }

  // =========================
  // Utils
  // =========================
  /// ใช้เช็คว่าเป็นวันหยุดนักขัตฤกษ์ไหม (yyyy-MM-dd)
  static Future<bool> isHoliday(String yyyyMmDd) async {
    final holidays = await loadHolidays();
    return holidays.any((h) => h.date == yyyyMmDd);
  }

  /// (optional) ล้างวันหยุดทั้งหมด
  static Future<void> clearHolidays() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
