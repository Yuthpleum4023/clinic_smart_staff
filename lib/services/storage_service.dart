import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee_model.dart';

class StorageService {
  // 🔑 legacy key (ของเก่า)
  static const String _legacyKey = 'employees_data';

  // ✅ version
  static const String _versionKey = 'employees_data_version';
  static const int _currentVersion = 4;

  // =========================
  // OPTIONAL instance helpers
  // =========================
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();

    final candidates = <String>[
      (prefs.getString('auth_token') ?? '').trim(),
      (prefs.getString('token') ?? '').trim(),
      (prefs.getString('jwtToken') ?? '').trim(),
      (prefs.getString('authToken') ?? '').trim(),
      (prefs.getString('userToken') ?? '').trim(),
      (prefs.getString('jwt_token') ?? '').trim(),
    ].where((e) => e.isNotEmpty).toList();

    return candidates.isNotEmpty ? candidates.first : null;
  }

  Future<String?> getClinicId() async {
    final prefs = await SharedPreferences.getInstance();

    final candidates = <String>[
      (prefs.getString('app_clinic_id') ?? '').trim(),
      (prefs.getString('clinicId') ?? '').trim(),
      (prefs.getString('clinic_id') ?? '').trim(),
      (prefs.getString('selected_clinic_id') ?? '').trim(),
      (prefs.getString('currentClinicId') ?? '').trim(),
      (prefs.getString('myClinicId') ?? '').trim(),
      (prefs.getString('appClinicId') ?? '').trim(),
    ].where((e) => e.isNotEmpty).toList();

    return candidates.isNotEmpty ? candidates.first : null;
  }

  Future<void> updateEmployee(EmployeeModel employee) async {
    await upsertEmployee(employee);
  }

  // =========================
  // INTERNAL HELPERS
  // =========================
  static Future<String?> _getClinicIdStatic() async {
    final prefs = await SharedPreferences.getInstance();

    final candidates = <String>[
      (prefs.getString('app_clinic_id') ?? '').trim(),
      (prefs.getString('clinicId') ?? '').trim(),
      (prefs.getString('clinic_id') ?? '').trim(),
      (prefs.getString('selected_clinic_id') ?? '').trim(),
      (prefs.getString('currentClinicId') ?? '').trim(),
      (prefs.getString('myClinicId') ?? '').trim(),
      (prefs.getString('appClinicId') ?? '').trim(),
    ].where((e) => e.isNotEmpty).toList();

    return candidates.isNotEmpty ? candidates.first : null;
  }

  static String _keyForClinic(String clinicId) {
    final c = clinicId.trim();
    return c.isEmpty ? _legacyKey : 'employees_data_$c';
  }

  static Future<String> _resolveActiveKey() async {
    final clinicId = await _getClinicIdStatic();
    if (clinicId == null || clinicId.trim().isEmpty) {
      return _legacyKey;
    }
    return _keyForClinic(clinicId);
  }

  // =========================
  // ENSURE VERSION
  // =========================
  static Future<void> _ensureVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getInt(_versionKey) ?? 0;

    if (savedVersion < _currentVersion) {
      // ✅ schema เก่า incompatible -> clear legacy cache เก่า
      await prefs.remove(_legacyKey);
      await prefs.setInt(_versionKey, _currentVersion);
    }
  }

  // =========================
  // SAVE ALL
  // =========================
  static Future<void> saveEmployees(List<EmployeeModel> employees) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      await prefs.setInt(_versionKey, _currentVersion);

      final key = await _resolveActiveKey();
      final encoded = json.encode(
        employees.map((e) => e.toMap()).toList(),
      );

      await prefs.setString(key, encoded);
    } catch (_) {
      // ไม่ throw เพื่อไม่ให้แอปเด้ง
    }
  }

  // =========================
  // LOAD ALL (SAFE)
  // =========================
  static Future<List<EmployeeModel>> loadEmployees() async {
    await _ensureVersion();

    final prefs = await SharedPreferences.getInstance();
    final key = await _resolveActiveKey();

    String raw = prefs.getString(key) ?? '';

    // ✅ fallback: ถ้า key ตาม clinic ยังไม่มีข้อมูล
    // และมี legacy cache เก่า -> อ่านของเก่าชั่วคราว
    if (raw.isEmpty && key != _legacyKey) {
      raw = prefs.getString(_legacyKey) ?? '';
    }

    if (raw.isEmpty) return [];

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
  // FIND
  // =========================
  static Future<EmployeeModel?> findEmployeeById(String id) async {
    final target = id.trim();
    if (target.isEmpty) return null;

    final list = await loadEmployees();
    for (final e in list) {
      if (e.id.trim() == target) return e;
    }
    return null;
  }

  static Future<EmployeeModel?> findEmployeeByLinkedUserId(
    String linkedUserId,
  ) async {
    final target = linkedUserId.trim();
    if (target.isEmpty) return null;

    final list = await loadEmployees();
    for (final e in list) {
      if (e.linkedUserId.trim() == target) return e;
    }
    return null;
  }

  // =========================
  // ADD
  // =========================
  static Future<void> addEmployee(EmployeeModel employee) async {
    final list = await loadEmployees();
    list.add(employee);
    await saveEmployees(list);
  }

  // =========================
  // UPDATE BY ID
  // =========================
  static Future<bool> updateEmployeeById(
    String id,
    EmployeeModel updated,
  ) async {
    final target = id.trim();
    if (target.isEmpty) return false;

    final list = await loadEmployees();
    final index = list.indexWhere((e) => e.id.trim() == target);

    if (index < 0) return false;

    list[index] = updated;
    await saveEmployees(list);
    return true;
  }

  // =========================
  // UPSERT
  // =========================
  static Future<void> upsertEmployee(EmployeeModel employee) async {
    final list = await loadEmployees();
    final index = list.indexWhere((e) => e.id.trim() == employee.id.trim());

    if (index >= 0) {
      list[index] = employee;
    } else {
      list.add(employee);
    }

    await saveEmployees(list);
  }

  // =========================
  // DELETE BY ID
  // =========================
  static Future<bool> deleteEmployeeById(String id) async {
    final target = id.trim();
    if (target.isEmpty) return false;

    final list = await loadEmployees();
    final before = list.length;

    list.removeWhere((e) => e.id.trim() == target);

    if (list.length == before) return false;

    await saveEmployees(list);
    return true;
  }

  // =========================
  // DELETE BY LINKED USER
  // =========================
  static Future<bool> deleteEmployeeByLinkedUserId(String linkedUserId) async {
    final target = linkedUserId.trim();
    if (target.isEmpty) return false;

    final list = await loadEmployees();
    final before = list.length;

    list.removeWhere((e) => e.linkedUserId.trim() == target);

    if (list.length == before) return false;

    await saveEmployees(list);
    return true;
  }

  // =========================
  // EXISTS CHECKS
  // =========================
  static Future<bool> existsEmployeeId(String id) async {
    final target = id.trim();
    if (target.isEmpty) return false;

    final list = await loadEmployees();
    return list.any((e) => e.id.trim() == target);
  }

  static Future<bool> existsLinkedUserId(
    String linkedUserId, {
    String? exceptEmployeeId,
  }) async {
    final target = linkedUserId.trim();
    if (target.isEmpty) return false;

    final exceptId = (exceptEmployeeId ?? '').trim();
    final list = await loadEmployees();

    return list.any((e) {
      if (exceptId.isNotEmpty && e.id.trim() == exceptId) return false;
      return e.linkedUserId.trim() == target;
    });
  }

  // =========================
  // CLEAR
  // =========================
  static Future<void> clearData() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _resolveActiveKey();

    await prefs.remove(key);

    // ✅ ไม่ลบทุกคลินิกทิ้งทั้งเครื่อง
    // ลบเฉพาะ active clinic
    if (key == _legacyKey) {
      await prefs.remove(_legacyKey);
    }
  }
}