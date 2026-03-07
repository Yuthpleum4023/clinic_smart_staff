import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee_model.dart';

class StorageService {
  // 🔑 key หลัก
  static const String _key = 'employees_data';

  // ✅ NEW: schema version กัน cache เก่าไม่มี staffId
  static const String _versionKey = 'employees_data_version';
  static const int _currentVersion = 2;

  // =========================
  // ENSURE VERSION
  // =========================
  static Future<void> _ensureVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getInt(_versionKey) ?? 0;

    if (savedVersion < _currentVersion) {
      // ✅ ล้าง cache เก่าที่ schema ไม่ตรง
      await prefs.remove(_key);
      await prefs.setInt(_versionKey, _currentVersion);
    }
  }

  // =========================
  // SAVE
  // =========================
  static Future<void> saveEmployees(List<EmployeeModel> employees) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      await prefs.setInt(_versionKey, _currentVersion);

      final encoded = json.encode(
        employees.map((e) => e.toMap()).toList(),
      );
      await prefs.setString(_key, encoded);
    } catch (e) {
      // ไม่ throw เพื่อไม่ให้แอปเด้ง
    }
  }

  // =========================
  // LOAD (SAFE)
  // =========================
  static Future<List<EmployeeModel>> loadEmployees() async {
    await _ensureVersion();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = json.decode(raw);

      if (decoded is! List) return [];

      final List<EmployeeModel> result = [];

      for (final item in decoded) {
        if (item is Map) {
          try {
            final map = Map<String, dynamic>.from(item);
            final emp = EmployeeModel.fromMap(map);
            result.add(emp);
          } catch (_) {
            // ❌ record นี้พัง → ข้าม
          }
        }
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  // =========================
  // CLEAR
  // =========================
  static Future<void> clearData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_versionKey);
  }
}