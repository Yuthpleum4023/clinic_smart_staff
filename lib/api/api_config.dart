// lib/api/api_config.dart
//
// ✅ FINAL — RENDER PRODUCTION CONFIG (FORCE_PROD supported)
// - PROD → ยิง Render 100%
// - DEV → ยิงเข้า Mac LAN ได้
// - รองรับ auth / payroll / score / staff
//
// ✅ NEW:
// - รัน debug แต่ให้ยิง Render ได้ด้วย:
//   flutter run --dart-define=FORCE_PROD=true
//

class ApiConfig {
  // =========================
  // ENV switch
  // =========================

  /// ✅ FORCE PROD even in debug (set by CLI)
  static const bool forceProd = bool.fromEnvironment(
    'FORCE_PROD',
    defaultValue: false,
  );

  /// ✅ true only in release mode (flutter build --release)
  static const bool _isRelease = bool.fromEnvironment(
    'dart.vm.product',
    defaultValue: false,
  );

  /// ✅ final prod flag
  static bool get isProd => forceProd || _isRelease;

  // =========================
  // DEV HOST (LAN IP ของ Mac)
  // =========================
  static const String _devHost = String.fromEnvironment(
    'DEV_HOST',
    defaultValue: '192.168.1.38',
  );

  // =========================
  // Base URLs
  // =========================

  /// ✅ AUTH USER SERVICE (3101)
  static String get authBaseUrl => isProd
      ? 'https://auth-user-service-afwu.onrender.com'
      : 'http://$_devHost:3101';

  /// ✅ PAYROLL SERVICE (3102)
  static String get payrollBaseUrl => isProd
      ? 'https://payroll-service-808t.onrender.com'
      : 'http://$_devHost:3102';

  /// ✅ SCORE SERVICE (3103)
  static String get scoreBaseUrl => isProd
      ? 'https://score-service-rrng.onrender.com'
      : 'http://$_devHost:3103';

  /// ✅ STAFF SERVICE (3104)
  static String get staffBaseUrl => isProd
      ? 'https://staff-service-xg6p.onrender.com'
      : 'http://$_devHost:3104';

  // =========================
  // Debug Helpers (สำคัญมาก)
  // =========================

  static String get debugAuth =>
      'AUTH → $authBaseUrl (isProd=$isProd forceProd=$forceProd release=$_isRelease)';

  static String get debugPayroll =>
      'PAYROLL → $payrollBaseUrl (isProd=$isProd forceProd=$forceProd release=$_isRelease)';

  static String get debugScore =>
      'SCORE → $scoreBaseUrl (isProd=$isProd forceProd=$forceProd release=$_isRelease)';

  static String get debugStaff =>
      'STAFF → $staffBaseUrl (isProd=$isProd forceProd=$forceProd release=$_isRelease)';

  static String get debugAll =>
      'MODE=${isProd ? 'PROD' : 'DEV'} (forceProd=$forceProd release=$_isRelease)\n'
      '$debugAuth\n'
      '$debugPayroll\n'
      '$debugScore\n'
      '$debugStaff';

  // =========================
  // Auth endpoints
  // =========================
  static const String me = '/me';
  static const String login = '/login';

  // =========================
  // Shift / Payroll endpoints
  // =========================
  static const String shifts = '/shifts';
  static String shiftStatus(String id) => '/shifts/$id/status';

  // =========================
  // Score endpoints
  // =========================
  static String staffScore(String staffId) => '/score/staff/$staffId/score';

  static const String trustScore = '/score/trustscore';
  static const String attendanceEvent = '/score/events/attendance';

  // =========================
  // Staff endpoints
  // =========================
  static const String staffSearch = '/staff/search';
}
