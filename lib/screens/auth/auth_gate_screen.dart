// lib/screens/auth/auth_gate_screen.dart
//
// ✅ FINAL / STABLE — Multi-role READY (NO UNKNOWN ROUTES)
// - ใช้ AuthApi.me()
// - save clinicId,userId,role + ✅ activeRole + ✅ roles[] ลง prefs (กันฟีเจอร์หาย)
// - redirect ครั้งเดียว
// - ✅ Named Routes ONLY
// - ✅ navigate หลังเฟรม กัน build scope crash
//
// IMPORTANT:
// - ไม่อ้าง AppRoutes.helperHome/clinicHome เพื่อกันแดง (เพราะบางโปรเจกต์ไม่มี)
// - เดินทางไป AppRoutes.home เสมอ แล้วให้ HomeScreen แยก flow ตาม role เอง
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/auth_api.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';
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

  // prefs keys (เพิ่มเอง ไม่ชนของเดิม)
  static const String _kActiveRole = 'app_active_role';
  static const String _kRolesJson = 'app_roles_json';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  // ------------------------------
  // Helpers
  // ------------------------------
  String _pickString(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty || s == 'null') return '';
    return s;
  }

  List<String> _pickStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => _pickString(e)).where((e) => e.isNotEmpty).toList();
    }
    return const [];
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

  /// ✅ IMPORTANT (multi-role):
  /// priority: activeRole > role > roles[0]
  String _extractEffectiveRole(Map<String, dynamic> me) {
    final a = _pickString(me['activeRole']);
    if (a.isNotEmpty) return a;

    final r = _pickString(me['role']);
    if (r.isNotEmpty) return r;

    final roles = me['roles'];
    if (roles is List && roles.isNotEmpty) {
      return _pickString(roles.first);
    }

    return '';
  }

  List<String> _extractRolesAll(Map<String, dynamic> me) {
    final roles = _pickStringList(me['roles']);
    final legacy = _pickString(me['role']);
    final active = _pickString(me['activeRole']);

    final set = <String>{};
    for (final r in roles) {
      set.add(r);
    }
    if (legacy.isNotEmpty) set.add(legacy);
    if (active.isNotEmpty) set.add(active);

    return set.toList();
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

  void _goLogin() => _scheduleNamedNav(AppRoutes.login);
  void _goHome() => _scheduleNamedNav(AppRoutes.home);

  Future<void> _boot() async {
    if (_navigated) return;

    try {
      // 1) มี token ไหม
      final token = await AuthStorage.getToken();
      if (!mounted) return;

      if (token == null || token.trim().isEmpty) {
        _goLogin();
        return;
      }

      // 2) ยิง /me
      final dynamic rawMe = await AuthApi.me();
      if (!mounted) return;

      // 3) normalize + save context (กันฟีเจอร์หาย)
      Map<String, dynamic> me;
      if (rawMe is Map) {
        me = Map<String, dynamic>.from(rawMe);
      } else {
        // fallback โหลดจาก prefs
        await AppContextResolver.loadFromPrefs();
        if (!mounted) return;
        _goHome();
        return;
      }

      final clinicId = _extractClinicId(me);
      final userId = _extractUserId(me);

      final effectiveRole = _extractEffectiveRole(me);
      final rolesAll = _extractRolesAll(me);

      // ✅ save to AppContextResolver (ของเดิม)
      if (clinicId.isNotEmpty && userId.isNotEmpty) {
        await AppContextResolver.save(
          clinicId: clinicId,
          userId: userId,
          role: effectiveRole,
        );
      } else {
        await AppContextResolver.loadFromPrefs();
      }
      if (!mounted) return;

      // ✅ save extra multi-role info
      final prefs = await SharedPreferences.getInstance();
      if (effectiveRole.isNotEmpty) {
        await prefs.setString(_kActiveRole, effectiveRole);
      }
      await prefs.setString(_kRolesJson, jsonEncode(rolesAll));

      // 4) ไป home เสมอ แล้วให้ HomeScreen ตัดสินใจตาม role
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

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}