// lib/screens/helper/helper_home_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_payroll/screens/auth/auth_gate_screen.dart';
import 'package:clinic_payroll/screens/home_screen.dart';

import 'package:clinic_payroll/api/api_config.dart';

class HelperHomeScreen extends StatefulWidget {
  final String clinicId;
  final String userId;

  /// อาจส่งมาว่างได้ (เช่นจาก Home/My shell)
  final String staffId;

  const HelperHomeScreen({
    super.key,
    required this.clinicId,
    required this.userId,
    required this.staffId,
  });

  @override
  State<HelperHomeScreen> createState() => _HelperHomeScreenState();
}

class _HelperHomeScreenState extends State<HelperHomeScreen> {
  bool _loading = true;
  String _err = '';

  String _clinicId = '';
  String _userId = '';
  String _staffId = '';

  static const _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
  ];

  // context keys (ตาม AuthGate ที่เราเซฟไว้)
  static const _kRole = 'app_role';
  static const _kClinicId = 'app_clinic_id';
  static const _kUserId = 'app_user_id';
  static const _kStaffId = 'app_staff_id';

  @override
  void initState() {
    super.initState();
    _clinicId = widget.clinicId;
    _userId = widget.userId;
    _staffId = widget.staffId.trim();
    _boot();
  }

  // -------------------- Token helpers --------------------
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = prefs.getString(k);
      if (v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'null') {
        return v.trim();
      }
    }
    return null;
  }

  Future<void> _clearAllAuth() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      await prefs.remove(k);
    }
    // ล้าง context ให้สะอาด (กัน role ค้าง)
    for (final k in [_kRole, _kClinicId, _kUserId, _kStaffId]) {
      await prefs.remove(k);
    }
  }

  // -------------------- /me --------------------
  Uri _u(String path) => Uri.parse('${ApiConfig.authBaseUrl}$path');

  Future<Map<String, dynamic>> _me(String token) async {
    final res = await http.get(
      _u(ApiConfig.me), // '/me'
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('me failed: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) return data;
    throw Exception('me response invalid');
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _err = '';
    });

    try {
      // 1) ถ้ามี staffId ส่งมาแล้ว ใช้เลย
      if (_staffId.isNotEmpty) {
        await _saveStaffId(_staffId);
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      // 2) ลองดึง staffId จาก prefs ก่อน (เร็ว)
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_kStaffId) ?? '').trim();
      if (saved.isNotEmpty) {
        _staffId = saved;
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      // 3) ยังไม่มี -> call /me เพื่อดึง staffId จริง
      final token = await _getToken();
      if (token == null) throw Exception('no token');

      final data = await _me(token);
      final userMap = (data['user'] is Map)
          ? (data['user'] as Map).cast<String, dynamic>()
          : data.cast<String, dynamic>();

      final staffId =
          (userMap['staffId'] ?? userMap['staff_id'] ?? '').toString().trim();
      final clinicId =
          (userMap['clinicId'] ?? userMap['clinic_id'] ?? '').toString().trim();
      final userId = (userMap['userId'] ??
              userMap['_id'] ??
              userMap['id'] ??
              '')
          .toString()
          .trim();

      if (staffId.isEmpty) {
        throw Exception('ไม่พบ staffId ใน /me (ต้องให้ backend ใส่ staffId ให้บัญชีผู้ช่วย)');
      }

      _staffId = staffId;
      if (clinicId.isNotEmpty) _clinicId = clinicId;
      if (userId.isNotEmpty) _userId = userId;

      await _saveStaffId(_staffId);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveStaffId(String staffId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStaffId, staffId);
  }

  // -------------------- Navigation --------------------
  Future<void> _logout() async {
    await _clearAllAuth();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGateScreen()),
      (route) => false,
    );
  }

  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _goHome(),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'กลับหน้า Home',
            icon: const Icon(Icons.home),
            onPressed: _goHome,
          ),
          title: const Text('Helper'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'รีเฟรช',
              onPressed: _boot,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'ออกจากระบบ',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_err.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'โหลดข้อมูลผู้ช่วยไม่สำเร็จ',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _err,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _boot,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('ลองใหม่'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _goHome,
                                    icon: const Icon(Icons.home),
                                    label: const Text('กลับ Home'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  Card(
                    child: ListTile(
                      title: const Text('งานว่าง'),
                      subtitle: const Text('รายการ ShiftNeed ที่คลินิกประกาศ'),
                      leading: const Icon(Icons.work_outline),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _snack('TODO: ผูกหน้า Open Needs จาก payroll_service');
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      title: const Text('งานของฉัน'),
                      subtitle: const Text('Shifts ที่รับแล้ว/ประวัติ'),
                      leading: const Icon(Icons.assignment_turned_in_outlined),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _snack('TODO: ผูกหน้า My Shifts');
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      title: const Text('ตารางเวลาว่างของฉัน'),
                      subtitle: const Text('HelperAvailability (local storage)'),
                      leading: const Icon(Icons.calendar_month),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _snack('TODO: ผูก HelperAvailabilityScreen');
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'clinicId=$_clinicId\nuserId=$_userId\nstaffId=${_staffId.isEmpty ? "-" : _staffId}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
      ),
    );
  }
}
