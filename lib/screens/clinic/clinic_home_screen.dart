// lib/screens/clinic_home_screen.dart
//
// ✅ FIXED (MY CLINIC DASHBOARD) + ADD HELPER AVAILABILITIES — PROD CLEAN
// - ✅ หน้านี้คือ "My Clinic"
// - ✅ ใช้ Theme (ไม่ hardcode สี)
// - ✅ เพิ่มเมนู "ตารางว่างผู้ช่วย"
// - ✅ PROD CLEAN: ไม่โชว์ clinicId/userId ใน UI และไม่ snack คำเทคนิค
// - ✅ PIN dialog: แสดง error ใน dialog (ไม่เด้ง snack)
//
// หมายเหตุ: ยัง clear token/prefs เหมือนเดิมตอน logout

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/screens/auth/auth_gate_screen.dart';

// ✅ existing screens
import 'package:clinic_smart_staff/screens/clinic_shift_need_screen.dart';
import 'package:clinic_smart_staff/screens/clinic_invites_screen.dart';
import 'package:clinic_smart_staff/screens/trustscore_lookup_screen.dart';

// ✅ NEW SCREEN
import 'package:clinic_smart_staff/screens/clinic/clinic_availabilities_screen.dart';

// ✅ ใช้ AuthService verify PIN
import 'package:clinic_smart_staff/services/auth_service.dart';

// ✅ Local payroll screen
import 'package:clinic_smart_staff/screens/home_screen.dart'
    show LocalPayrollScreen;

// ✅ Clinic Admin Settings
import 'package:clinic_smart_staff/screens/clinic/clinic_admin_setting_service.dart';

class ClinicHomeScreen extends StatefulWidget {
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
      _snack('ไม่พบข้อมูลคลินิก (ลอง logout/login ใหม่)');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicShiftNeedScreen(clinicId: cid),
      ),
    );
  }

  Future<void> _openInvites() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClinicInvitesScreen()),
    );
  }

  /// ✅ NEW: ตารางว่างผู้ช่วย
  Future<void> _openAvailabilities() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ClinicAvailabilitiesScreen(),
      ),
    );
  }

  Future<void> _openTrustScoreWithPin() async {
    final ok = await _askClinicPinAndVerify();
    if (ok != true) return;

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TrustScoreLookupScreen()),
    );
  }

  // ✅ PIN dialog แบบโปรดักชัน: error อยู่ใน dialog (ไม่ snack เด้งๆ)
  Future<bool?> _askClinicPinAndVerify() async {
    final ctrl = TextEditingController();
    bool loading = false;
    String errText = '';

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            Future<void> verify() async {
              final pin = ctrl.text.trim();
              if (pin.isEmpty) {
                setSt(() => errText = 'กรุณากรอก PIN');
                return;
              }

              setSt(() {
                loading = true;
                errText = '';
              });

              try {
                final ok = await AuthService.verifyPin(pin);

                if (!ctx.mounted) return;

                if (ok) {
                  Navigator.pop(ctx, true);
                } else {
                  setSt(() => errText = 'PIN ไม่ถูกต้อง');
                }
              } catch (_) {
                if (!ctx.mounted) return;
                setSt(() => errText = 'ตรวจสอบ PIN ไม่สำเร็จ');
              } finally {
                if (ctx.mounted) setSt(() => loading = false);
              }
            }

            return AlertDialog(
              title: const Text('ยืนยัน PIN คลินิก'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('กรุณาใส่ PIN เพื่อเข้าดู TrustScore'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => verify(),
                  ),
                  if (errText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      errText,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx, false),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
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

  Future<void> _openClinicAdmin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ClinicAdminSettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Clinic'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _bootstrap,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ✅ ลบการ์ดโชว์ clinicId/userId ออก (PROD CLEAN)

          const Text(
            'ตลาดแรงงาน / ผู้ช่วย',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('ประกาศงานว่าง'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openShiftNeed,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_available),
              title: const Text('ตารางว่างผู้ช่วย'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openAvailabilities,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('เชิญผู้ช่วย'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openInvites,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: const Text('TrustScore'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openTrustScoreWithPin,
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'เครื่องมือคลินิก',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Payroll (Local)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openLocalPayroll,
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'ตั้งค่าคลินิก',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Clinic Admin'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openClinicAdmin,
            ),
          ),
        ],
      ),
    );
  }
}