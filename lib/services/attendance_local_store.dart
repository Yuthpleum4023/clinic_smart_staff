import 'package:shared_preferences/shared_preferences.dart';

class AttendanceLocalStore {
  static const _kOpenSessionId = 'open_attendance_session_id';

  static Future<void> setOpenSessionId(String id) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kOpenSessionId, id);
  }

  static Future<String?> getOpenSessionId() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kOpenSessionId);
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  static Future<void> clearOpenSessionId() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kOpenSessionId);
  }
}