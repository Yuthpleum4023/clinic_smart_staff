// lib/screens/clinic_home_screen.dart
//
// ✅ FIXED (MY CLINIC DASHBOARD) + NO BLUE (USE THEME)
// - ✅ หน้านี้คือ "My Clinic" (ไม่ใช่ Home ซ้อน Home)
// - ✅ อ่าน clinicId/userId จาก prefs keys ใหม่: app_clinic_id / app_user_id
// - ✅ TrustScore ต้องผ่าน PIN คลินิกก่อน (ตาม requirement)
// - ✅ Payroll(Local) เปิดไปหน้า LocalPayrollScreen (ไม่ย้อนกลับไป Home รวม)
// - ✅ FIX FLOW: Clinic Admin (Settings) -> ไปหน้า ClinicAdminSettingsScreen ได้จริง
// - ✅ FIX UI: ไม่ hardcode สีฟ้า -> ใช้ Theme สีม่วงทั้งระบบ
//

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/screens/auth/auth_gate_screen.dart';

// ✅ existing screens
import 'package:clinic_smart_staff/screens/clinic_shift_need_screen.dart';
import 'package:clinic_smart_staff/screens/clinic_invites_screen.dart';
import 'package:clinic_smart_staff/screens/trustscore_lookup_screen.dart';

// ✅ ใช้ AuthService verify PIN
import 'package:clinic_smart_staff/services/auth_service.dart';

// ✅ Local payroll screen
import 'package:clinic_smart_staff/screens/home_screen.dart' show LocalPayrollScreen;

// ✅ Clinic Admin Settings (ของคุณมีอยู่แล้ว)
import 'package:clinic_smart_staff/screens/clinic/clinic_admin_setting_service.dart';

class ClinicHomeScreen extends StatefulWidget {
  /// optional: ถ้าหน้าอื่นส่งมา
  final String? clinicId;
  final String? userId;

  const ClinicHomeScreen({
    super.key,
    this.clinicId,
    this.userId,
  });

  @override
  State<ClinicHomeScreen> createState() => _ClinicHomeScreenState();
}

class _ClinicHomeScreenState extends State<ClinicHomeScreen> {
  String _clinicId = '';
  String _userId = '';
  bool _loading = true;

  static const _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
  ];

  // ✅ keys ใหม่จาก AuthGate
  static const _kClinicId = 'app_clinic_id';
  static const _kUserId = 'app_user_id';
  static const _kRole = 'app_role';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();

    // ใช้ค่าที่ส่งมาก่อน ถ้าไม่มีค่อยอ่านจาก prefs
    final cid = (widget.clinicId ?? '').trim().isNotEmpty
        ? widget.clinicId!.trim()
        : (prefs.getString(_kClinicId) ?? '').trim();

    final uid = (widget.userId ?? '').trim().isNotEmpty
        ? widget.userId!.trim()
        : (prefs.getString(_kUserId) ?? '').trim();

    if (!mounted) return;
    setState(() {
      _clinicId = cid;
      _userId = uid;
      _loading = false;
    });
  }

  void _goAuthGateClearStack() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGateScreen()),
      (route) => false,
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      await prefs.remove(k);
    }
    // ล้าง role/context กันค้าง
    for (final k in [_kClinicId, _kUserId, _kRole]) {
      await prefs.remove(k);
    }
    _goAuthGateClearStack();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------
  // ✅ Navigation targets
  // ------------------------------
  Future<void> _openLocalPayroll() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LocalPayrollScreen()),
    );
  }

  Future<void> _openShiftNeed() async {
    final cid = _clinicId.trim();
    if (cid.isEmpty) {
      _snack('ไม่พบ clinicId (ลอง logout/login ใหม่)');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClinicShiftNeedScreen(clinicId: cid)),
    );
  }

  Future<void> _openInvites() async {
    if (_userId.trim().isEmpty) {
      _snack('ไม่พบ userId (ลอง logout/login ใหม่)');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClinicInvitesScreen()),
    );
  }

  // ✅ TrustScore ต้องผ่าน PIN
  Future<void> _openTrustScoreWithPin() async {
    final ok = await _askClinicPin();
    if (ok != true) return;

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TrustScoreLookupScreen()),
    );
  }

  Future<bool?> _askClinicPin() async {
    final ctrl = TextEditingController();
    bool loading = false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            Future<void> verify() async {
              final pin = ctrl.text.trim();
              if (pin.isEmpty) return;

              setSt(() => loading = true);
              try {
                final ok = await AuthService.verifyPin(pin);
                if (!ctx.mounted) return;
                if (ok) {
                  Navigator.pop(ctx, true);
                } else {
                  _snack('PIN คลินิกไม่ถูกต้อง');
                }
              } finally {
                if (ctx.mounted) setSt(() => loading = false);
              }
            }

            return AlertDialog(
              title: const Text('ยืนยันตัวตนคลินิก'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('กรุณาใส่ PIN คลินิกเพื่อเข้าดู TrustScore'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'PIN คลินิก',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => verify(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx, false),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: loading ? null : verify,
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ยืนยัน'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ✅ Clinic Admin -> เปิดหน้า Settings จริง
  Future<void> _openClinicAdmin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClinicAdminSettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cid = _clinicId.trim();
    final uid = _userId.trim();

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Clinic'),
        // ✅ ไม่ hardcode สีฟ้า -> ใช้ Theme (ม่วง) ของแอป
        // backgroundColor / foregroundColor ไม่ต้องใส่
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _bootstrap,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'ออกจากระบบ',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ------------------------------
          // ✅ Context card
          // ------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'แดชบอร์ดคลินิก',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'clinicId: ${cid.isEmpty ? "-" : cid}\nuserId: ${uid.isEmpty ? "-" : uid}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ------------------------------
          // ✅ ภายในคลินิก
          // ------------------------------
          const Text('ภายในคลินิก',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const Icon(Icons.people_alt_outlined),
              title: const Text('Payroll (Local)'),
              subtitle: const Text('เพิ่มพนักงาน • ดูรายละเอียด • พิมพ์สลิป PDF'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openLocalPayroll,
            ),
          ),

          const SizedBox(height: 14),

          // ------------------------------
          // ✅ ตลาดแรงงาน / ผู้ช่วย
          // ------------------------------
          const Text('ตลาดแรงงาน / ผู้ช่วย',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('ประกาศงานว่าง (ShiftNeed)'),
              subtitle: Text('สำหรับคลินิก • clinicId: ${cid.isEmpty ? "-" : cid}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openShiftNeed,
            ),
          ),
          const SizedBox(height: 10),

          Card(
            child: ListTile(
              leading: const Icon(Icons.person_add_alt_1),
              title: const Text('เชิญผู้ช่วย (Invites)'),
              subtitle: Text('สำหรับคลินิก • userId: ${uid.isEmpty ? "-" : uid}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openInvites,
            ),
          ),
          const SizedBox(height: 10),

          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: const Text('ดู TrustScore ผู้ช่วย'),
              subtitle: const Text('ต้องยืนยัน PIN คลินิกก่อน'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openTrustScoreWithPin,
            ),
          ),

          const SizedBox(height: 14),

          // ------------------------------
          // ✅ Clinic Admin (Settings)
          // ------------------------------
          const Text('ตั้งค่าคลินิก',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Clinic Admin (Settings)'),
              subtitle: const Text('ตั้ง PIN • SSO%'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openClinicAdmin,
            ),
          ),
        ],
      ),
    );
  }
}
