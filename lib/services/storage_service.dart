import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee_model.dart';

class StorageService {
  // 🔑 key หลัก
  static const String _key = 'employees_data';

  // =========================
  // SAVE
  // =========================
  static Future<void> saveEmployees(List<EmployeeModel> employees) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final encoded = json.encode(
        employees.map((e) => e.toMap()).toList(),
      );
      await prefs.setString(_key, encoded);
    } catch (e) {
      // ไม่ throw เพื่อไม่ให้แอปเด้ง
      // (ถ้าจะ log ภายหลังค่อยเพิ่ม)
    }
  }

  // =========================
  // LOAD (SAFE)
  // =========================
  static Future<List<EmployeeModel>> loadEmployees() async {
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
            // Map<String, dynamic> แบบปลอดภัย
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
      // ❌ JSON พัง → ไม่เด้ง
      return [];
    }
  }

  // =========================
  // CLEAR
  // =========================
  static Future<void> clearData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
