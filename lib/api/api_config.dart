// lib/api/api_config.dart
//
// ✅ FULL FILE (FIXED for Docker + Real Device)
// - DEV: ใช้ IP Mac ของคุณ (มือถือยิงเข้าได้) => 192.168.1.38 ✅
// - PROD: ใช้ Render URLs ตามเดิม
// - override ได้ด้วย --dart-define=DEV_HOST=xxx.xxx.xxx.xxx
//
// วิธีรัน (override IP แบบไม่ต้องแก้ไฟล์):
// flutter run --dart-define=DEV_HOST=192.168.1.38
//
// ✅ IMPORTANT FIX:
// score_service ของคุณ mount routes ไว้ที่ /score
// ดังนั้น endpoint ต้องเป็น /score/... ทั้งหมด
//

class ApiConfig {
  // =========================
  // ENV switch
  // =========================
  static const bool isProd = bool.fromEnvironment(
    'dart.vm.product',
    defaultValue: false,
  );

  // =========================
  // DEV HOST (LAN IP ของ Mac)
  // =========================
  // ✅ default: IP ของคุณจาก ipconfig getifaddr en0
  // ✅ override ได้ด้วย --dart-define=DEV_HOST=...
  static const String _devHost = String.fromEnvironment(
    'DEV_HOST',
    defaultValue: '192.168.1.38',
  );

  // =========================
  // Base URLs
  // =========================

  /// auth_service
  static String get authBaseUrl => isProd
      ? 'https://auth-service-xxxx.onrender.com'
      : 'http://$_devHost:3101';

  /// score_service
  static String get scoreBaseUrl => isProd
      ? 'https://score-service-xxxx.onrender.com'
      : 'http://$_devHost:3103';

  /// payroll / shift_service
  static String get payrollBaseUrl => isProd
      ? 'https://payroll-service-xxxx.onrender.com'
      : 'http://$_devHost:3102';

  // =========================
  // Auth endpoints
  // =========================
  static const String me = '/me';

  // =========================
  // Shift endpoints
  // =========================
  static const String shifts = '/shifts';
  static String shiftStatus(String id) => '/shifts/$id/status';

  // =========================
  // Score endpoints (MOUNTED UNDER /score)
  // =========================

  /// Canonical:
  /// GET /score/staff/:staffId/score
  static String staffScore(String staffId) => '/score/staff/$staffId/score';

  /// Alias TrustScore:
  /// GET /score/trustscore?staffId=xxx
  static const String trustScore = '/score/trustscore';

  /// Attendance events:
  /// POST /score/events/attendance
  static const String attendanceEvent = '/score/events/attendance';
}
