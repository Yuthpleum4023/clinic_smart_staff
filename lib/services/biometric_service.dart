import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  // -----------------------------
  // ✅ Internal helpers
  // -----------------------------
  bool _isFingerprintOnlyType(BiometricType t) {
    // ✅ รองรับหลายเวอร์ชันของ local_auth โดยไม่อ้าง touchID ตรงๆ
    // - Android: fingerprint
    // - iOS: ถ้าเป็น TouchID บางเวอร์ชันอาจยังรายงานเป็น fingerprint
    // - ถ้าเป็น FaceID-only: มักรายงานเป็น face / strong / weak (เราจะไม่อนุญาต)
    return t == BiometricType.fingerprint;
  }

  String _friendlyBioError(String code) {
    final c = code.toLowerCase().trim();

    if (c.contains('notenrolled')) {
      return 'ยังไม่ได้ตั้งค่าลายนิ้วมือในเครื่อง';
    }
    if (c.contains('passcodenotset')) {
      return 'กรุณาตั้งรหัสล็อกหน้าจอก่อนใช้งาน';
    }
    if (c.contains('notavailable')) {
      return 'เครื่องนี้ยังไม่รองรับการยืนยันตัวตนด้วยลายนิ้วมือ';
    }
    if (c.contains('lockedout')) {
      return 'สแกนผิดหลายครั้ง ระบบล็อกชั่วคราว — ปลดล็อกด้วยรหัสหน้าจอก่อนแล้วลองใหม่';
    }
    if (c.contains('permanentlylockedout')) {
      return 'ระบบล็อกเพื่อความปลอดภัย — กรุณาปลดล็อกด้วยรหัสหน้าจอ/ตั้งค่าชีวมิติใหม่';
    }
    if (c.contains('usercanceled') || c.contains('usercancel')) {
      return 'ยกเลิกการยืนยันตัวตน';
    }
    if (c.contains('authentication_failed')) {
      return 'ยืนยันตัวตนไม่ผ่าน กรุณาลองใหม่';
    }
    if (c.contains('biometric_only_not_supported')) {
      return 'อุปกรณ์นี้ไม่รองรับโหมดชีวมิติอย่างเดียว';
    }

    return 'ยืนยันตัวตนไม่สำเร็จ (BIO ERROR: $code)';
  }

  Future<List<BiometricType>> _getTypesSafe() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const <BiometricType>[];
    }
  }

  // -----------------------------
  // ✅ Public API
  // -----------------------------
  Future<bool> canUseBiometric() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;

      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;

      final types = await _getTypesSafe();

      // ✅ Fingerprint-only
      return types.any(_isFingerprintOnlyType);
    } catch (_) {
      return false;
    }
  }

  /// ✅ Fingerprint-only verify
  /// - ถ้าเครื่องมีแต่ FaceID/อย่างอื่น (ไม่มี fingerprint) -> return false
  /// - reason default: ลายนิ้วมือเท่านั้น
  Future<bool> verify({String reason = 'ยืนยันตัวตนด้วยลายนิ้วมือ'}) async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;

      final types = await _getTypesSafe();
      final hasFingerprint = types.any(_isFingerprintOnlyType);

      // ❌ ไม่อนุญาต FaceID
      if (!hasFingerprint) return false;

      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
      return ok;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  // ✅ Optional: ถ้าหน้า UI อยากเอา error message ไปแสดงเอง (ไม่บังคับใช้)
  Future<String?> verifyWithMessage({
    String reason = 'ยืนยันตัวตนด้วยลายนิ้วมือ',
  }) async {
    try {
      final ok = await verify(reason: reason);
      return ok ? null : 'ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่';
    } on PlatformException catch (e) {
      return _friendlyBioError(e.code);
    } catch (_) {
      return 'ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่';
    }
  }
}