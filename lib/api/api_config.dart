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

  // ✅ Payroll close / tax / slip (เพิ่มไว้ให้ OT โผล่ในสลิปชัวร์)
  // NOTE: ชื่อ path อาจจะตรงกับที่คุณใช้จริงอยู่แล้วใน service อื่น
  //       ถ้าคุณมีชื่อ path อื่น เดี๋ยวเราจะ map ให้ตรงในไฟล์ api/service ถัดไป
  static const String payrollTax = '/payroll/tax';
  static const String payrollClose = '/payroll/close';
  static const String payslipPreview = '/payslip/preview';
  static const String payslipDownload = '/payslip/download';

  // =========================
  // Attendance / OT endpoints (เพิ่มไว้ใช้คู่กับ fingerprint)
  // =========================
  // attendance: check-in / check-out / sessions
  static const String attendanceCheckIn = '/attendance/check-in';
  static const String attendanceCheckOut = '/attendance/check-out';
  static const String attendanceMySessions = '/attendance/my-sessions';

  // overtime: approve / list
  static const String overtimeMy = '/overtime/my';
  static String overtimeApprove(String overtimeId) => '/overtime/$overtimeId/approve';

  // =========================
  // Score endpoints
  // =========================
  static String staffScore(String staffId) => '/score/staff/$staffId/score';

  static const String trustScore = '/score/trustscore';

  // ✅ FIX: eventRoutes mount เป็น /events -> POST /events/attendance
  static const String attendanceEvent = '/events/attendance';

  // =========================
  // Staff endpoints
  // =========================
  static const String staffSearch = '/staff/search';

  // ✅ NEW: staff dropdown (โดยตรงจาก staff_service)
  static const String staffDropdown = '/api/employees/dropdown';

  // ✅ NEW: staff dropdown ผ่าน payroll_service proxy (ถ้าคุณทำ proxy ไว้แล้ว)
  static const String staffDropdownProxy = '/api/staff/dropdown';
}