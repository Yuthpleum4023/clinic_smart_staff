// lib/app/app_context_resolver.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clinic_smart_staff/app/app_context.dart';

class AppContextResolver {
  static const _kClinicId = 'app_clinic_id';
  static const _kUserId = 'app_user_id';
  static const _kRole = 'app_role';

  // ---------------------------
  // role helpers
  // ---------------------------
  static String _norm(String s) => s.trim();
  static String _normRole(String s) => s.toLowerCase().trim();

  static bool _isClinicRole(String role) {
    final r = _normRole(role);
    return r == 'clinic' || r == 'admin';
  }

  static bool _isHelperRole(String role) {
    final r = _normRole(role);
    return r == 'helper' || r == 'employee';
  }

  /// ✅ Normalize + Validate context after loading/saving
  /// - clinic/admin ต้องมี userId+clinicId ครบ ไม่งั้น clear
  /// - helper/employee ต้องมี userId และบังคับ clinicId = ''
  /// - role อื่น/ว่าง => clear
  static void _applyValidated({
    required String clinicId,
    required String userId,
    required String role,
  }) {
    final cid = _norm(clinicId);
    final uid = _norm(userId);
    final r = _normRole(role);

    if (_isClinicRole(r)) {
      if (uid.isNotEmpty && cid.isNotEmpty) {
        // ✅ clinic ready
        AppContext.clinicId = cid;
        AppContext.userId = uid;
        AppContext.role = r;
        return;
      }
      // ❌ clinic role แต่ข้อมูลไม่ครบ => clear ทั้งหมด (กันเด้งเข้า MyClinic)
      AppContext.clear();
      return;
    }

    if (_isHelperRole(r)) {
      if (uid.isNotEmpty) {
        // ✅ helper ready (ไม่ควรมี clinicId)
        AppContext.clinicId = '';
        AppContext.userId = uid;
        AppContext.role = r;
        return;
      }
      AppContext.clear();
      return;
    }

    // role ว่าง/ไม่รู้จัก => ถือว่าไม่พร้อม
    AppContext.clear();
  }

  /// เรียกครั้งเดียวตอน login / enter MyClinic / app start
  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final clinicId = (prefs.getString(_kClinicId) ?? '');
    final userId = (prefs.getString(_kUserId) ?? '');
    final role = (prefs.getString(_kRole) ?? '');

    _applyValidated(
      clinicId: clinicId,
      userId: userId,
      role: role,
    );

    // ✅ ถ้า validate แล้วกลายเป็น clear/normalize ให้ sync กลับ prefs เพื่อกันค้าง
    await _syncBackToPrefs(prefs);
  }

  /// บันทึก context ลง prefs + ใส่เข้า AppContext
  ///
  /// NOTE: คง signature เดิมเพื่อไม่ให้ไฟล์อื่นพัง
  /// - ถ้า role เป็น helper/employee -> clinicId จะถูกบังคับเป็น ''
  /// - ถ้า role เป็น clinic/admin -> ต้องส่ง clinicId+userId ครบ
  static Future<void> save({
    required String clinicId,
    required String userId,
    String role = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final r = _normRole(role);

    // normalize ตาม role
    String cid = _norm(clinicId);
    final uid = _norm(userId);

    if (_isHelperRole(r)) {
      cid = ''; // helper ไม่เก็บ clinicId
    }

    await prefs.setString(_kClinicId, cid);
    await prefs.setString(_kUserId, uid);
    await prefs.setString(_kRole, r);

    _applyValidated(
      clinicId: cid,
      userId: uid,
      role: r,
    );

    // sync เผื่อถูก clear/normalize
    await _syncBackToPrefs(prefs);
  }

  /// เพิ่ม convenience (ไม่บังคับใช้): เซฟแบบ clinic
  static Future<void> saveClinic({
    required String clinicId,
    required String userId,
    String role = 'clinic',
  }) {
    return save(clinicId: clinicId, userId: userId, role: role);
  }

  /// เพิ่ม convenience (ไม่บังคับใช้): เซฟแบบ helper
  static Future<void> saveHelper({
    required String userId,
    String role = 'helper',
  }) {
    return save(clinicId: '', userId: userId, role: role);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kClinicId);
    await prefs.remove(_kUserId);
    await prefs.remove(_kRole);

    AppContext.clear();
  }

  /// ✅ Helper: ดึง clinicId แบบใช้ได้ทันที (ผ่าน validate แล้ว)
  static Future<String> requireClinicId() async {
    if (AppContext.clinicId.trim().isNotEmpty) return AppContext.clinicId.trim();
    await loadFromPrefs();
    return AppContext.clinicId.trim();
  }

  /// ✅ Helper: ดึง userId แบบใช้ได้ทันที (ผ่าน validate แล้ว)
  static Future<String> requireUserId() async {
    if (AppContext.userId.trim().isNotEmpty) return AppContext.userId.trim();
    await loadFromPrefs();
    return AppContext.userId.trim();
  }

  // ----------------------------------------------------------
  // internal: sync current AppContext back to prefs
  // ----------------------------------------------------------
  static Future<void> _syncBackToPrefs(SharedPreferences prefs) async {
    // ถ้า AppContext ถูก clear => เคลียร์ prefs
    if (AppContext.role.trim().isEmpty &&
        AppContext.userId.trim().isEmpty &&
        AppContext.clinicId.trim().isEmpty) {
      await prefs.remove(_kClinicId);
      await prefs.remove(_kUserId);
      await prefs.remove(_kRole);
      return;
    }

    // ถ้า helper => clinicId ต้องเป็น ''
    final r = _normRole(AppContext.role);
    final cid = _isHelperRole(r) ? '' : _norm(AppContext.clinicId);

    await prefs.setString(_kClinicId, cid);
    await prefs.setString(_kUserId, _norm(AppContext.userId));
    await prefs.setString(_kRole, r);
  }
}
