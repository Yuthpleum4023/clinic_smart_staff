import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/screens/auth/auth_gate_screen.dart';

// Existing screens
import 'package:clinic_smart_staff/screens/clinic_shift_need_screen.dart';
import 'package:clinic_smart_staff/screens/clinic_invites_screen.dart';
import 'package:clinic_smart_staff/screens/trustscore_lookup_screen.dart';

// New clinic screens
import 'package:clinic_smart_staff/screens/clinic/clinic_availabilities_screen.dart';
import 'package:clinic_smart_staff/screens/clinic/clinic_attendance_approval_screen.dart';
import 'package:clinic_smart_staff/screens/clinic/clinic_attendance_settings_screen.dart';
import 'package:clinic_smart_staff/screens/clinic/clinic_location_settings_screen.dart';

// ✅ แดชบอร์ดการลงเวลา
import 'package:clinic_smart_staff/screens/admin/attendance_dashboard_screen.dart';

// ✅ Social security receipts
import 'package:clinic_smart_staff/screens/social_security_receipt_list_screen.dart';

// Auth / services
import 'package:clinic_smart_staff/services/auth_service.dart';

// Local payroll
import 'package:clinic_smart_staff/screens/home/home_screen.dart'
    show LocalPayrollScreen;

// Clinic admin settings
import 'package:clinic_smart_staff/screens/clinic/clinic_admin_setting_service.dart';

class ClinicHomeScreen extends StatefulWidget {
  final String? clinicId;
  final String? userId;

  const ClinicHomeScreen({super.key, this.clinicId, this.userId});

  @override
  State<ClinicHomeScreen> createState() => _ClinicHomeScreenState();
}

class _ClinicHomeScreenState extends State<ClinicHomeScreen> {
  String _clinicId = '';
  String _userId = '';
  bool _loading = true;

  static const List<String> _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
    'accessToken',
    'access_token',
    'auth_token',
  ];

  static const String _kClinicId = 'app_clinic_id';
  static const String _kUserId = 'app_user_id';
  static const String _kRole = 'app_role';

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

  Future<void> _openLocalPayroll() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LocalPayrollScreen()),
    );
  }

  Future<void> _openSocialSecurityReceipts() async {
    final cid = _clinicId.trim();

    if (cid.isEmpty) {
      _snack('ไม่พบข้อมูลคลินิก กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocialSecurityReceiptListScreen(clinicId: cid),
      ),
    );
  }

  Future<void> _openShiftNeed() async {
    final cid = _clinicId.trim();

    if (cid.isEmpty) {
      _snack('ไม่พบข้อมูลคลินิก กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClinicShiftNeedScreen(clinicId: cid)),
    );
  }

  Future<void> _openInvites() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClinicInvitesScreen()),
    );
  }

  Future<void> _openAvailabilities() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClinicAvailabilitiesScreen()),
    );
  }

  Future<void> _openAttendanceApproval() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClinicAttendanceApprovalScreen()),
    );
  }

  Future<void> _openAttendanceSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClinicAttendanceSettingsScreen()),
    );
  }

  Future<void> _openClinicLocationSettings() async {
    print('TAP -> OPEN_CLINIC_LOCATION_SETTINGS');

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClinicLocationSettingsScreen()),
    );
  }

  Future<void> _openAttendanceAnalytics() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AttendanceDashboardScreen()),
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
                if (ctx.mounted) {
                  setSt(() => loading = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('ยืนยัน PIN คลินิก'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('กรุณากรอก PIN เพื่อเข้าดูคะแนนความน่าเชื่อถือ'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'รหัส PIN',
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
      MaterialPageRoute(builder: (_) => const ClinicAdminSettingsScreen()),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
    );
  }

  Widget _menuCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('คลินิกของฉัน'),
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
          _sectionTitle('งานและผู้ช่วย'),
          const SizedBox(height: 8),
          _menuCard(
            icon: Icons.campaign_outlined,
            title: 'ประกาศงาน',
            subtitle: 'สร้างและจัดการประกาศงานของคลินิก',
            onTap: _openShiftNeed,
          ),
          _menuCard(
            icon: Icons.event_available,
            title: 'เลือกผู้ช่วย',
            subtitle: 'ดูผู้ช่วยที่พร้อมรับงานและเลือกผู้ช่วยที่เหมาะสม',
            onTap: _openAvailabilities,
          ),
          _menuCard(
            icon: Icons.person_add,
            title: 'เชิญผู้ช่วยเข้าร่วมงาน',
            subtitle: 'ส่งคำเชิญและติดตามการตอบรับ',
            onTap: _openInvites,
          ),
          _menuCard(
            icon: Icons.approval_outlined,
            title: 'อนุมัติคำขอเวลาเข้า-ออกงาน',
            subtitle: 'อนุมัติหรือปฏิเสธคำขอแก้ไขเวลาเข้า-ออกงาน',
            onTap: _openAttendanceApproval,
          ),
          _menuCard(
            icon: Icons.schedule_outlined,
            title: 'ตั้งค่ากฎเวลาเข้า-ออกงาน',
            subtitle: 'กำหนดเวลาเข้า-ออกงานปกติและกติกาการลงเวลาในแต่ละวัน',
            onTap: _openAttendanceSettings,
          ),
          _menuCard(
            icon: Icons.analytics_outlined,
            title: 'สถิติการเข้า-ออกงาน',
            subtitle: 'ดูภาพรวมการเข้า-ออกงาน มาสาย OT และพนักงานเสี่ยง',
            onTap: _openAttendanceAnalytics,
          ),
          _menuCard(
            icon: Icons.verified_outlined,
            title: 'คะแนนความน่าเชื่อถือ',
            subtitle: 'ตรวจสอบคะแนนและประวัติของผู้ช่วย',
            onTap: _openTrustScoreWithPin,
          ),
          const SizedBox(height: 20),
          _sectionTitle('เครื่องมือจัดการคลินิก'),
          const SizedBox(height: 8),
          _menuCard(
            icon: Icons.payments_outlined,
            title: 'พรีวิวเงินเดือน',
            subtitle: 'จัดการข้อมูลพนักงานและตรวจสอบยอดเงินเดือนก่อนปิดงวดจริง',
            onTap: _openLocalPayroll,
          ),
          _menuCard(
            icon: Icons.receipt_long_outlined,
            title: 'ใบเสร็จประกันสังคม',
            subtitle: 'สร้าง ดูรายการ เปิด PDF และยกเลิกใบเสร็จ',
            onTap: _openSocialSecurityReceipts,
          ),
          const SizedBox(height: 20),
          _sectionTitle('การตั้งค่าคลินิก'),
          const SizedBox(height: 8),
          _menuCard(
            icon: Icons.location_on_outlined,
            title: 'ตั้งพิกัดคลินิก',
            subtitle:
                'กำหนดพิกัดอ้างอิงของคลินิกสำหรับตรวจสอบระยะก่อนสแกนเข้างาน',
            onTap: _openClinicLocationSettings,
          ),
          _menuCard(
            icon: Icons.admin_panel_settings,
            title: 'ตั้งค่าผู้ดูแลคลินิก',
            subtitle: 'กำหนดค่าการใช้งานและสิทธิ์ของคลินิก',
            onTap: _openClinicAdmin,
          ),
        ],
      ),
    );
  }
}
