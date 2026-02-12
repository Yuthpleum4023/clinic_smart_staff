// lib/app_context/app_context.dart
//
// ✅ FIX: กันเด้งเข้า My Clinic ผิด
// - เดิม isReady เช็กแค่ clinicId+userId => ถ้ามีค่าเก่าค้าง จะ "พร้อม" ทันที
// - ใหม่: isReady จะพิจารณาตาม role ด้วย (clinic/helper)
// - ยัง backward compatible: ใช้ static fields เดิมได้เหมือนเดิม

class AppContext {
  // ---------------------------
  // Backward-compatible fields
  // ---------------------------
  static String clinicId = '';
  static String userId = '';
  static String role = ''; // 'clinic' | 'admin' | 'employee' | 'helper' | ฯลฯ

  // ---------------------------
  // Normalization helpers
  // ---------------------------
  static String get roleNormalized => role.toLowerCase().trim();

  static bool get isClinicRole {
    final r = roleNormalized;
    // รองรับชื่อ role ที่คุณอาจใช้หลายแบบ
    return r == 'clinic' || r == 'admin';
  }

  static bool get isHelperRole {
    final r = roleNormalized;
    return r == 'helper' || r == 'employee';
  }

  // ---------------------------
  // ✅ Readiness (สำคัญมาก)
  // ---------------------------

  /// ✅ พร้อมสำหรับเข้าหน้า Clinic (My Clinic)
  /// ต้องมี userId + clinicId และ role ต้องเป็น clinic/admin
  static bool get isClinicReady =>
      userId.trim().isNotEmpty &&
      clinicId.trim().isNotEmpty &&
      isClinicRole;

  /// ✅ พร้อมสำหรับเข้าหน้า Helper
  /// ต้องมี userId และ role ต้องเป็น helper/employee
  static bool get isHelperReady =>
      userId.trim().isNotEmpty &&
      isHelperRole;

  /// ✅ พร้อมสำหรับเข้า “หน้าหลังล็อกอิน”
  /// - ถ้า role เป็น clinic/admin => ต้อง isClinicReady
  /// - ถ้า role เป็น helper/employee => ต้อง isHelperReady
  /// - ถ้า role ว่าง/ไม่รู้จัก => ถือว่าไม่พร้อม (บังคับกลับ Login/Home)
  static bool get isReady {
    if (isClinicRole) return isClinicReady;
    if (isHelperRole) return isHelperReady;
    return false;
  }

  // ---------------------------
  // Setters (ช่วยให้ตั้งค่าไม่หลวม)
  // ---------------------------
  static void setClinic({
    required String userIdValue,
    required String clinicIdValue,
    String roleValue = 'clinic',
  }) {
    userId = userIdValue.trim();
    clinicId = clinicIdValue.trim();
    role = roleValue.trim();
  }

  static void setHelper({
    required String userIdValue,
    String roleValue = 'helper',
  }) {
    userId = userIdValue.trim();
    clinicId = ''; // helper ไม่ควรมี clinicId ใน context นี้
    role = roleValue.trim();
  }

  // ---------------------------
  // Clear
  // ---------------------------
  static void clear() {
    clinicId = '';
    userId = '';
    role = '';
  }

  // ---------------------------
  // Debug (ช่วยไล่สาเหตุเด้งผิด)
  // ---------------------------
  static String debugString() {
    return 'AppContext{role=$role, userId=$userId, clinicId=$clinicId, isReady=$isReady, isClinicReady=$isClinicReady, isHelperReady=$isHelperReady}';
  }
}
