// lib/api/api_config.dart
//
// ============================================================
// API CONFIG (FINAL CLEAN VERSION)
// รองรับ:
// - Render Production
// - Local DEV
// - Helper Marketplace
// - TrustScore
// - Payroll
// - Attendance / OT
//
// Run production mode from debug:
// flutter run --dart-define=FORCE_PROD=true
// ============================================================

class ApiConfig {
  // ============================================================
  // ENV SWITCH
  // ============================================================

  /// บังคับใช้ PROD แม้รัน debug
  static const bool forceProd = bool.fromEnvironment(
    'FORCE_PROD',
    defaultValue: false,
  );

  /// true เฉพาะตอน build release
  static const bool _isRelease = bool.fromEnvironment(
    'dart.vm.product',
    defaultValue: false,
  );

  /// สถานะ production
  static bool get isProd => forceProd || _isRelease;

  // ============================================================
  // DEV HOST (Mac LAN IP)
  // ============================================================

  static const String _devHost = String.fromEnvironment(
    'DEV_HOST',
    defaultValue: '192.168.1.38',
  );

  // ============================================================
  // BASE URLS
  // ============================================================

  /// AUTH USER SERVICE
  static String get authBaseUrl => isProd
      ? 'https://auth-user-service-afwu.onrender.com'
      : 'http://$_devHost:3101';

  /// PAYROLL SERVICE
  static String get payrollBaseUrl => isProd
      ? 'https://payroll-service-808t.onrender.com'
      : 'http://$_devHost:3102';

  /// SCORE SERVICE
  static String get scoreBaseUrl => isProd
      ? 'https://score-service-rrng.onrender.com'
      : 'http://$_devHost:3103';

  /// STAFF SERVICE
  static String get staffBaseUrl => isProd
      ? 'https://staff-service-xg6p.onrender.com'
      : 'http://$_devHost:3104';

  // ============================================================
  // DEBUG HELPERS
  // ============================================================

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

  // ============================================================
  // AUTH ENDPOINTS
  // ============================================================

  static const String login = '/login';
  static const String me = '/me';

  // ============================================================
  // SHIFT / PAYROLL
  // ============================================================

  static const String shifts = '/shifts';
  static String shiftStatus(String id) => '/shifts/$id/status';

  static const String payrollTax = '/payroll/tax';
  static const String payrollClose = '/payroll/close';

  static const String payslipPreview = '/payslip/preview';
  static const String payslipDownload = '/payslip/download';

  // ============================================================
  // ATTENDANCE
  // ============================================================

  static const String attendanceCheckIn = '/attendance/check-in';
  static const String attendanceCheckOut = '/attendance/check-out';
  static const String attendanceMySessions = '/attendance/my-sessions';

  // ============================================================
  // OVERTIME
  // ============================================================

  static const String overtimeMy = '/overtime/my';
  static String overtimeApprove(String id) => '/overtime/$id/approve';

  // ============================================================
  // TRUST SCORE
  // ============================================================

  static String staffScore(String staffId) => '/score/staff/$staffId/score';

  static const String trustScore = '/score/trustscore';

  static const String attendanceEvent = '/events/attendance';

  // ============================================================
  // STAFF SERVICE
  // ============================================================

  static const String staffSearch = '/staff/search';

  static const String staffDropdown = '/api/employees/dropdown';

  static const String staffDropdownProxy = '/api/staff/dropdown';

  // ============================================================
  // HELPER MARKETPLACE
  // ============================================================

  /// Global helper search
  static const String helperSearch = '/helpers/search';

  /// Helper trust score
  static String helperScoreByUserId(String userId) =>
      '/helpers/$userId/score';

  /// Helper recommendations
  static const String helperRecommendations = '/recommendations';
}