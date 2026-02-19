// lib/screens/auth/auth_gate_screen.dart
//
// ✅ FINAL / STABLE VERSION — MATCH main.dart (Named Routes ONLY)
// - ใช้ AuthApi.me()
// - โหลด/เซฟ clinicId,userId,role เข้า AppContext
// - redirect ครั้งเดียว
// - ✅ FIX: ใช้ pushNamedAndRemoveUntil (ไม่ใช้ MaterialPageRoute)
// - ✅ FIX: navigate หลังเฟรม (post-frame) กัน build scope crash
//

import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/api/auth_api.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

import 'package:clinic_smart_staff/screens/auth/login_screen.dart';
import 'package:clinic_smart_staff/app/app_context_resolver.dart';

// ✅ route names จาก main.dart
import 'package:clinic_smart_staff/main.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // ✅ เริ่มหลังเฟรมแรก
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _boot();
    });
  }

  // ------------------------------
  // Helpers: extract context from /me
  // ------------------------------
  String _pickString(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty || s == 'null') return '';
    return s;
  }

  String _extractClinicId(Map<String, dynamic> me) {
    final direct = _pickString(me['clinicId']);
    if (direct.isNotEmpty) return direct;

    final clinic = me['clinic'];
    if (clinic is String) return _pickString(clinic);
    if (clinic is Map) {
      final m = Map<String, dynamic>.from(clinic);
      return _pickString(m['id'] ?? m['_id'] ?? m['clinicId']);
    }

    final clinics = me['clinics'];
    if (clinics is List && clinics.isNotEmpty) {
      final first = clinics.first;
      if (first is String) return _pickString(first);
      if (first is Map) {
        final m = Map<String, dynamic>.from(first);
        return _pickString(m['id'] ?? m['_id'] ?? m['clinicId']);
      }
    }

    return '';
  }

  String _extractUserId(Map<String, dynamic> me) {
    final id1 = _pickString(me['userId']);
    if (id1.isNotEmpty) return id1;

    final id2 = _pickString(me['id']);
    if (id2.isNotEmpty) return id2;

    final id3 = _pickString(me['_id']);
    if (id3.isNotEmpty) return id3;

    final user = me['user'];
    if (user is Map) {
      final m = Map<String, dynamic>.from(user);
      return _pickString(m['id'] ?? m['_id'] ?? m['userId']);
    }

    return '';
  }

  String _extractRole(Map<String, dynamic> me) {
    final r1 = _pickString(me['role']);
    if (r1.isNotEmpty) return r1;

    final roles = me['roles'];
    if (roles is List && roles.isNotEmpty) {
      return _pickString(roles.first);
    }

    return '';
  }

  // ----------------------------------------------------------
  // Navigation helpers (Named Routes ONLY)
  // ----------------------------------------------------------
  void _scheduleNamedNav(String routeName) {
    if (_navigated || !mounted) return;
    _navigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        routeName,
        (_) => false,
      );
    });
  }

  Future<void> _boot() async {
    if (_navigated) return;

    try {
      // 1) มี token ไหม
      final token = await AuthStorage.getToken();
      if (!mounted) return;

      if (token == null || token.isEmpty) {
        _goLogin();
        return;
      }

      // 2) ยิง /me
      final dynamic rawMe = await AuthApi.me();
      if (!mounted) return;

      // 3) โหลด context
      if (rawMe is Map) {
        final me = Map<String, dynamic>.from(rawMe);

        final clinicId = _extractClinicId(me);
        final userId = _extractUserId(me);
        final role = _extractRole(me);

        if (clinicId.isNotEmpty && userId.isNotEmpty) {
          await AppContextResolver.save(
            clinicId: clinicId,
            userId: userId,
            role: role,
          );
          if (!mounted) return;
        } else {
          await AppContextResolver.loadFromPrefs();
          if (!mounted) return;
        }
      } else {
        await AppContextResolver.loadFromPrefs();
        if (!mounted) return;
      }

      // 4) ผ่าน = ไป Home/My (ตามโครง main.dart)
      _goHome();
    } catch (_) {
      // error = logout
      try {
        await AuthStorage.clearToken();
      } catch (_) {}
      try {
        await AppContextResolver.clear();
      } catch (_) {}

      if (!mounted) return;
      _goLogin();
    }
  }

  void _goLogin() {
    _scheduleNamedNav(AppRoutes.authGate == AppRoutes.login
        ? AppRoutes.login
        : AppRoutes.login);
  }

  void _goHome() {
    // ตอนนี้ main.dart วาง placeholder ไว้ที่ /home
    // ถ้าคุณอยากแยก clinic/helper ภายหลัง ค่อยมาปรับตรงนี้
    _scheduleNamedNav(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    // Gate = loading อย่างเดียว
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
