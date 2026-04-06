// lib/screens/auth/auth_gate_screen.dart
//
// ✅ FINAL / HARDENED — Multi-role READY + NO STALE PREFS
// ✅ PATCH: helper อนุญาตให้ clinicId ว่างได้
// - ใช้ AuthApi.me() เป็น source หลัก
// - ไม่ fallback ไป loadFromPrefs() เมื่อ /me ไม่ครบ
// - clear context เก่าเมื่อ session/use context ไม่สมบูรณ์
// - redirect ครั้งเดียว
// - Named Routes ONLY
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/auth_api.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';
import 'package:clinic_smart_staff/app/app_context_resolver.dart';
import 'package:clinic_smart_staff/main.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  bool _navigated = false;

  static const String _kClinicId = 'app_clinic_id';
  static const String _kUserId = 'app_user_id';
  static const String _kRole = 'app_role';
  static const String _kActiveRole = 'app_active_role';
  static const String _kRolesJson = 'app_roles_json';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

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
      if (r.isNotEmpty) set.add(r);
    }
    if (legacy.isNotEmpty) set.add(legacy);
    if (active.isNotEmpty) set.add(active);

    return set.toList();
  }

  Future<void> _clearContextPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kClinicId);
    await prefs.remove(_kUserId);
    await prefs.remove(_kRole);
    await prefs.remove(_kActiveRole);
    await prefs.setString(_kRolesJson, jsonEncode(const <String>[]));
  }

  Future<void> _hardClearSession() async {
    try {
      await AuthStorage.clearToken();
    } catch (_) {}

    try {
      await AppContextResolver.clear();
    } catch (_) {}

    try {
      await _clearContextPrefs();
    } catch (_) {}
  }

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
      final token = await AuthStorage.getToken();
      if (!mounted) return;

      if (token == null || token.trim().isEmpty) {
        await _hardClearSession();
        if (!mounted) return;
        _goLogin();
        return;
      }

      final dynamic rawMe = await AuthApi.me();
      if (!mounted) return;

      if (rawMe is! Map) {
        await _hardClearSession();
        if (!mounted) return;
        _goLogin();
        return;
      }

      final me = Map<String, dynamic>.from(rawMe);

      final clinicId = _extractClinicId(me);
      final userId = _extractUserId(me);
      final effectiveRole = _extractEffectiveRole(me);
      final rolesAll = _extractRolesAll(me);

      final isHelper =
          effectiveRole == 'helper' || rolesAll.contains('helper');

      // ✅ helper อนุญาตให้ clinicId ว่างได้
      if (userId.isEmpty) {
        await _hardClearSession();
        if (!mounted) return;
        _goLogin();
        return;
      }

      if (!isHelper && clinicId.isEmpty) {
        await _hardClearSession();
        if (!mounted) return;
        _goLogin();
        return;
      }
            await AppContextResolver.save(
        clinicId: clinicId,
        userId: userId,
        role: effectiveRole,
      );

      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_kClinicId, clinicId);
      await prefs.setString(_kUserId, userId);

      if (effectiveRole.isNotEmpty) {
        await prefs.setString(_kRole, effectiveRole);
        await prefs.setString(_kActiveRole, effectiveRole);
      } else {
        await prefs.remove(_kRole);
        await prefs.remove(_kActiveRole);
      }

      await prefs.setString(_kRolesJson, jsonEncode(rolesAll));

      if (!mounted) return;
      _goHome();
    } catch (_) {
      await _hardClearSession();
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