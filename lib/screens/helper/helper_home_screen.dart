// lib/screens/helper/helper_home_screen.dart
//
// ✅ FULL FILE — HelperHomeScreen (clinic_smart_staff) — PRODUCTION FRIENDLY
// ----------------------------------------------------
// ✅ GOAL: ผู้ช่วย “ประกาศเวลาว่าง” ได้ครบ flow
// - เมนูแรก: ผู้ช่วยประกาศเวลาว่าง -> เข้า HelperAvailabilityScreen
// - เมนูสอง: งานว่าง (ตลาดงาน)
// - เมนูสาม: งานของฉัน (Shifts + นำทาง)
//
// ✅ THIS ROUND FIX:
// - ✅ ลบ "จุดสแกนนิ้วมือ" ออกจาก HelperHomeScreen ทั้งหมด
// - ✅ ให้ helper ใช้จุดเช็คอิน/เช็คเอาท์จาก HomeScreen เพียงจุดเดียว
// - ✅ ลดความซ้ำซ้อนของ flow และกันสถานะ attendance ชนกัน
//
// ✅ PRODUCTION CLEAN:
// - ไม่โชว์ clinicId/userId/staffId ใน UI
// - ไม่โชว์ข้อความ endpoint/เทคนิคใน subtitle/snack
//
// ✅ IMPORTANT FIX:
// - ✅ helper token บางแบบไม่มี staffId -> ห้ามโยน MISSING_PROFILE
// - ✅ เมนู “งานว่าง/งานของฉัน” ต้องเข้าได้ แม้ staffId ว่าง
//
// ✅ STABILITY PATCH:
// - กัน setState หลัง dispose
// - กันกดสมัครซ้ำ / กันเปิด bottomSheet ซ้ำ
//
// ✅ PATCH (ตามบั๊กที่ท่านรายงาน):
// - ✅ สมัครสำเร็จ -> เด้งกลับจากหน้ารายละเอียดอัตโนมัติ
// - ✅ สมัครสำเร็จ -> refresh list แล้วขึ้น “สมัครแล้ว” ทันที
// - ✅ กันจอแดงจาก async/context/mounted ให้จบในรอบเดียว
//
// ✅ UX PATCH:
// - ✅ หน้ารายละเอียดงานแสดง “เบอร์โทรคลินิก” ถ้ามี
// - ✅ เพิ่มปุ่ม “โทรคลินิก” กดโทรออกได้ทันที
// - ✅ ถ้าไม่มีเบอร์ จะซ่อน section โทรอัตโนมัติ
// - ✅ หน้า list งานว่าง แสดงเบอร์โทรคลินิกแบบไม่รก UI
// - ✅ หน้า “งานของฉัน” เพิ่มปุ่มโทรคลินิกข้างปุ่มนำทาง
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:clinic_smart_staff/screens/auth/auth_gate_screen.dart';
import 'package:clinic_smart_staff/screens/home/home_screen.dart';
import 'package:clinic_smart_staff/screens/helper_availability_screen.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

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

  /// ✅ เก็บ error ภายใน แต่ไม่โชว์ tech ใน UI
  String _err = '';

  String _clinicId = '';
  String _userId = '';
  String _staffId = '';

  // context keys (ตาม AuthGate ที่เราเซฟไว้)
  static const _kRole = 'app_role';
  static const _kClinicId = 'app_clinic_id';
  static const _kUserId = 'app_user_id';
  static const _kStaffId = 'app_staff_id';

  final _authClient = ApiClient(baseUrl: ApiConfig.authBaseUrl);

  // ✅ payroll client (shifts/shift-needs)
  final _payroll = ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  // ✅ STABILITY PATCH
  bool _disposed = false;
  void _safeSetState(VoidCallback fn) {
    if (!mounted || _disposed) return;
    setState(fn);
  }

  // ✅ BottomNav state (งานของฉัน / งานว่าง / ออกจากระบบ)
  int _navIndex = 0;

  // ✅ กันกด nav ซ้ำซ้อน
  bool _navBusy = false;

  @override
  void initState() {
    super.initState();
    _clinicId = widget.clinicId;
    _userId = widget.userId;
    _staffId = widget.staffId.trim();
    _boot();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // -------------------- auth helpers --------------------
  Future<void> _clearAllAuth() async {
    await AuthStorage.clearToken();

    final prefs = await SharedPreferences.getInstance();
    for (final k in [_kRole, _kClinicId, _kUserId, _kStaffId]) {
      await prefs.remove(k);
    }
  }

  Future<Map<String, dynamic>> _me() async {
    final data = await _authClient.get(ApiConfig.me, auth: true);
    if (data is Map && data['user'] is Map) {
      return (data['user'] as Map).cast<String, dynamic>();
    }
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  bool _isMissingProfileError(String raw) {
    final s = raw.toLowerCase();
    return s.contains('missing_profile') || s.contains('staffid');
  }

  Future<void> _boot() async {
    _safeSetState(() {
      _loading = true;
      _err = '';
    });

    try {
      if (_staffId.isNotEmpty) {
        await _saveStaffId(_staffId);
        if (!mounted) return;
        _safeSetState(() => _loading = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_kStaffId) ?? '').trim();
      if (saved.isNotEmpty) {
        _staffId = saved;
        if (!mounted) return;
        _safeSetState(() => _loading = false);
        return;
      }

      final token = await AuthStorage.getToken();
      if (token == null || token.trim().isEmpty || token.trim() == 'null') {
        throw Exception('AUTH_REQUIRED');
      }

      final userMap = await _me();

      final staffId =
          (userMap['staffId'] ?? userMap['staff_id'] ?? '').toString().trim();
      final clinicId =
          (userMap['clinicId'] ?? userMap['clinic_id'] ?? '').toString().trim();
      final userId =
          (userMap['userId'] ?? userMap['_id'] ?? userMap['id'] ?? '')
              .toString()
              .trim();

      _staffId = staffId;
      if (_staffId.isNotEmpty) {
        await _saveStaffId(_staffId);
      }

      if (clinicId.isNotEmpty) _clinicId = clinicId;
      if (userId.isNotEmpty) _userId = userId;

      if (!mounted) return;
      _safeSetState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;

      final raw = e.toString();

      if (_isMissingProfileError(raw)) {
        _safeSetState(() {
          _err = '';
          _loading = false;
        });
        return;
      }

      _safeSetState(() {
        _err = raw;
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

  Future<void> _openAvailability() async {
    debugPrint('[UI] tap: availability');
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HelperAvailabilityScreen()),
    );
  }

  Future<void> _openOpenNeeds() async {
    debugPrint('[UI] tap: bottom/open needs');
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OpenNeedsScreen(staffId: _staffId)),
    );
  }

  Future<void> _openMyShifts() async {
    debugPrint('[UI] tap: bottom/my shifts');
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MyShiftsScreen(staffId: _staffId)),
    );
  }

  Future<void> _onBottomTap(int i) async {
    if (_navBusy) return;
    _navBusy = true;

    try {
      _safeSetState(() => _navIndex = i);

      if (i == 0) {
        await _openMyShifts();
      } else if (i == 1) {
        await _openOpenNeeds();
      } else {
        await _logout();
      }
    } finally {
      _navBusy = false;
    }
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _goHome(),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'กลับหน้าแรก',
            icon: const Icon(Icons.home),
            onPressed: _goHome,
          ),
          title: const Text('ผู้ช่วยของฉัน'),
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
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _navIndex,
          onTap: _onBottomTap,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'งานของฉัน',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.work_outline),
              label: 'งานว่าง',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.logout),
              label: 'ออกจากระบบ',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _boot,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_err.isNotEmpty)
                      _ErrorCard(
                        err: _err,
                        onRetry: _boot,
                        onHome: _goHome,
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'การลงเวลาทำงาน',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'การเช็คอินและเช็คเอาท์ของผู้ช่วยย้ายไปใช้งานที่หน้าแรกแล้ว เพื่อให้มีจุดบันทึกเวลาทำงานเพียงจุดเดียว',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _goHome,
                                icon: const Icon(Icons.home),
                                label: const Text('กลับไปหน้าแรก'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MenuCard(
                      title: 'ตารางเวลาว่างของฉัน',
                      subtitle:
                          'ประกาศและแก้ไขเวลาว่าง เพื่อให้คลินิกเลือกจองงานได้',
                      icon: Icons.calendar_month,
                      iconColor: cs.primary,
                      onTap: _openAvailability,
                    ),
                    const SizedBox(height: 10),
                    _MenuCard(
                      title: 'งานว่างที่เปิดรับ',
                      subtitle:
                          'ดูรายการงานที่เปิดรับสมัครและสมัครงานได้ทันที',
                      icon: Icons.work_outline,
                      iconColor: cs.primary,
                      onTap: () async {
                        debugPrint('[UI] tap: open needs');
                        await _openOpenNeeds();
                      },
                    ),
                    const SizedBox(height: 10),
                    _MenuCard(
                      title: 'งานที่ได้รับของฉัน',
                      subtitle:
                          'ดูงานที่ได้รับแล้ว พร้อมโทรคลินิกและนำทางไปยังสถานที่ทำงาน',
                      icon: Icons.assignment_turned_in_outlined,
                      iconColor: cs.primary,
                      onTap: () async {
                        debugPrint('[UI] tap: my shifts');
                        await _openMyShifts();
                      },
                    ),
                    const SizedBox(height: 6),
                    if (_staffId.isEmpty)
                      const Text(
                        'หมายเหตุ: บางบัญชีอาจแสดงข้อมูลบางส่วนได้ไม่ครบถ้วน แต่ยังสามารถใช้งานเมนูงานว่างและงานของฉันได้ตามปกติ',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ============================================================
// UI components
// ============================================================
class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        leading: Icon(icon, color: iconColor),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String err;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  const _ErrorCard({
    required this.err,
    required this.onRetry,
    required this.onHome,
  });

  String _friendly(String raw) {
    final s = raw.toLowerCase();

    if (s.contains('auth_required') ||
        s.contains('no token') ||
        s.contains('unauthorized') ||
        s.contains('401')) {
      return 'กรุณาเข้าสู่ระบบใหม่อีกครั้ง';
    }

    if (s.contains('missing_profile') || s.contains('staffid')) {
      return 'ระบบกำลังอัปเดตข้อมูลบัญชีของคุณ โดยคุณยังใช้งานเมนูหลักได้ตามปกติ';
    }

    if (s.contains('socket') ||
        s.contains('timeout') ||
        s.contains('network') ||
        s.contains('connection')) {
      return 'เชื่อมต่อไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่อีกครั้ง';
    }
    return 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
  }

  @override
  Widget build(BuildContext context) {
    final msg = _friendly(err);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'เกิดข้อผิดพลาด',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(msg, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ลองใหม่'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onHome,
                    icon: const Icon(Icons.home),
                    label: const Text('กลับหน้าแรก'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Screen 1: Open Needs (งานว่าง)
// ============================================================
class OpenNeedsScreen extends StatefulWidget {
  final String staffId;
  const OpenNeedsScreen({super.key, required this.staffId});

  @override
  State<OpenNeedsScreen> createState() => _OpenNeedsScreenState();
}

class _OpenNeedsScreenState extends State<OpenNeedsScreen> {
  final _payroll = ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  bool _loading = true;
  String _err = '';
  List<Map<String, dynamic>> _items = [];

  static const _kApplyPhone = 'helper_apply_phone';

  bool _busyApply = false;
  String _busyNeedId = '';

  bool _disposed = false;
  void _safeSetState(VoidCallback fn) {
    if (!mounted || _disposed) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<Map<String, dynamic>> _extractItems(dynamic resAny) {
    if (resAny is Map) {
      final items1 = resAny['items'];
      if (items1 is List) {
        return items1
            .whereType<Map>()
            .map((x) => x.cast<String, dynamic>())
            .toList();
      }
      final data = resAny['data'];
      if (data is List) {
        return data
            .whereType<Map>()
            .map((x) => x.cast<String, dynamic>())
            .toList();
      }
      if (data is Map && data['items'] is List) {
        final items2 = data['items'] as List;
        return items2
            .whereType<Map>()
            .map((x) => x.cast<String, dynamic>())
            .toList();
      }
    }
    return [];
  }

  String _s(dynamic v) => (v ?? '').toString();

  String _clinicPhone(Map<String, dynamic> n) {
    final c = n['clinic'];
    if (c is Map) {
      final phone = (c['phone'] ?? c['clinicPhone'] ?? '').toString().trim();
      if (phone.isNotEmpty) return phone;
    }
    final phone =
        (n['clinicPhone'] ?? n['clinic_phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) return phone;
    return '';
  }

  Future<void> _load() async {
    _safeSetState(() {
      _loading = true;
      _err = '';
    });

    try {
      dynamic res;
      try {
        res = await _payroll.get('/shift-needs/open', auth: true);
      } catch (_) {
        res = await _payroll.get('/api/shift-needs/open', auth: true);
      }

      _safeSetState(() {
        _items = _extractItems(res);
        _loading = false;
      });
    } catch (e) {
      _safeSetState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  bool _applied(Map<String, dynamic> it) {
    final v = it['_applied'];
    if (v is bool) return v;
    return _s(v).toLowerCase() == 'true';
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  bool _isValidPhone(String p) {
    final d = _digitsOnly(p);
    return d.length >= 9 && d.length <= 10;
  }

  Future<String?> _askPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_kApplyPhone) ?? '').trim();
    final ctrl = TextEditingController(text: saved);

    try {
      final result = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          String err = '';
          return StatefulBuilder(
            builder: (ctx2, setLocal) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: MediaQuery.of(ctx2).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'กรอกเบอร์โทรเพื่อสมัครงาน',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'กรอกเบอร์โทร 9–10 หลัก เพื่อให้คลินิกสามารถติดต่อกลับได้',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'เบอร์โทร (9–10 หลัก)',
                          border: const OutlineInputBorder(),
                          errorText: err.isEmpty ? null : err,
                        ),
                        onSubmitted: (_) async {
                          final d = _digitsOnly(ctrl.text.trim());
                          if (!_isValidPhone(d)) {
                            setLocal(
                              () => err = 'เบอร์โทรต้องเป็นตัวเลข 9–10 หลัก',
                            );
                            return;
                          }
                          await prefs.setString(_kApplyPhone, d);
                          if (!ctx2.mounted) return;
                          Navigator.pop(ctx2, d);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx2, null),
                              child: const Text('ยกเลิก'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                final d = _digitsOnly(ctrl.text.trim());
                                if (!_isValidPhone(d)) {
                                  setLocal(
                                    () => err = 'เบอร์โทรต้องเป็นตัวเลข 9–10 หลัก',
                                  );
                                  return;
                                }
                                await prefs.setString(_kApplyPhone, d);
                                if (!ctx2.mounted) return;
                                Navigator.pop(ctx2, d);
                              },
                              child: const Text('ยืนยัน'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      if (!mounted) return null;
      return result;
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _apply(String needId) async {
    if (_busyApply) return;
    if (needId.trim().isEmpty) return;

    final phone = await _askPhone();
    if (!mounted) return;

    if (phone == null || phone.trim().isEmpty) return;

    _safeSetState(() {
      _busyApply = true;
      _busyNeedId = needId;
    });

    try {
      dynamic res;
      try {
        res = await _payroll.post(
          '/shift-needs/$needId/apply',
          auth: true,
          body: {'phone': phone},
        );
      } catch (_) {
        res = await _payroll.post(
          '/api/shift-needs/$needId/apply',
          auth: true,
          body: {'phone': phone},
        );
      }

      if (!mounted) return;

      bool ok = true;
      if (res is Map && res['ok'] is bool) ok = res['ok'] as bool;
      if (!ok) {
        throw Exception(
          (res is Map ? (res['message'] ?? res['error']) : null) ??
              'apply failed',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ สมัครงานสำเร็จ')),
      );

      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('สมัครงานไม่สำเร็จ กรุณาลองใหม่')),
      );
      rethrow;
    } finally {
      if (!mounted) return;
      _safeSetState(() {
        _busyApply = false;
        _busyNeedId = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('งานว่างที่เปิดรับ'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _err.isNotEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _ErrorCard(
                          err: _err,
                          onRetry: _load,
                          onHome: () => Navigator.pop(context),
                        ),
                      ],
                    )
                  : _items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: const [
                            SizedBox(height: 30),
                            Center(child: Text('ยังไม่มีงานว่างในขณะนี้')),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final it = _items[i];

                            final title = _s(it['title']).isNotEmpty
                                ? _s(it['title'])
                                : 'ต้องการผู้ช่วย';
                            final date = _s(it['date']);
                            final start = _s(it['start']);
                            final end = _s(it['end']);
                            final rate = it['hourlyRate'];
                            final clinicPhone = _clinicPhone(it);

                            final needId = _s(it['_id']).isNotEmpty
                                ? _s(it['_id'])
                                : _s(it['id']);

                            final already = _applied(it);
                            final busyThis = _busyApply && _busyNeedId == needId;

                            final line1 = [
                              if (date.isNotEmpty) 'วันที่ $date',
                              if (start.isNotEmpty || end.isNotEmpty)
                                'เวลา $start - $end',
                              if (rate != null) 'ค่าตอบแทน ${_s(rate)} บาท/ชม.',
                            ].join(' • ');

                            final subtitleLines = <String>[
                              if (line1.isNotEmpty) line1,
                              if (clinicPhone.isNotEmpty) 'โทร $clinicPhone',
                            ];

                            return Card(
                              child: ListTile(
                                leading: Icon(Icons.work_outline, color: cs.primary),
                                title: Text(title),
                                subtitle: Text(
                                  subtitleLines.isEmpty
                                      ? 'รายละเอียดเพิ่มเติมจะแสดงเมื่อเปิดดูงาน'
                                      : subtitleLines.join('\n'),
                                ),
                                isThreeLine: clinicPhone.isNotEmpty,
                                trailing: already
                                    ? const Chip(
                                        label: Text('สมัครแล้ว'),
                                        visualDensity: VisualDensity.compact,
                                      )
                                    : busyThis
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.chevron_right),
                                onTap: () async {
                                  if (needId.isEmpty) return;

                                  final didPop = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => NeedDetailScreen(
                                        need: it,
                                        applying: busyThis,
                                        onApply: (already || _busyApply)
                                            ? null
                                            : () => _apply(needId),
                                      ),
                                    ),
                                  );

                                  if (didPop == true && mounted) {
                                    await _load();
                                  }
                                },
                              ),
                            );
                          },
                        ),
            ),
    );
  }
}

class NeedDetailScreen extends StatelessWidget {
  final Map<String, dynamic> need;
  final Future<void> Function()? onApply;
  final bool applying;

  const NeedDetailScreen({
    super.key,
    required this.need,
    this.onApply,
    this.applying = false,
  });

  String _s(dynamic v) => (v ?? '').toString();

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().toLowerCase().trim();
    return s == 'true' || s == '1' || s == 'yes';
  }

  String _clinicName(Map<String, dynamic> n) {
    final c = n['clinic'];
    if (c is Map) {
      final name = (c['name'] ?? c['clinicName'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
    final name = (n['clinicName'] ?? n['clinic_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return 'คลินิก';
  }

  String _clinicPhone(Map<String, dynamic> n) {
    final c = n['clinic'];
    if (c is Map) {
      final phone = (c['phone'] ?? c['clinicPhone'] ?? '').toString().trim();
      if (phone.isNotEmpty) return phone;
    }
    final phone =
        (n['clinicPhone'] ?? n['clinic_phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) return phone;
    return '';
  }

  String _clinicAddress(Map<String, dynamic> n) {
    final c = n['clinic'];
    if (c is Map) {
      final address =
          (c['address'] ?? c['clinicAddress'] ?? '').toString().trim();
      if (address.isNotEmpty) return address;
    }
    final address =
        (n['clinicAddress'] ?? n['clinic_address'] ?? '').toString().trim();
    if (address.isNotEmpty) return address;
    return '';
  }

  Future<void> _callClinic(BuildContext context, String phone) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) return;

    final uri = Uri.parse('tel:$cleanPhone');

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเปิดหน้าจอโทรออกได้')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดหน้าจอโทรออกได้')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _s(need['title']).isNotEmpty ? _s(need['title']) : 'รายละเอียดงาน';
    final applied = _asBool(need['_applied']);
    final clinicName = _clinicName(need);
    final clinicPhone = _clinicPhone(need);
    final clinicAddress = _clinicAddress(need);
    final hasClinicPhone = clinicPhone.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('สถานที่ทำงาน: $clinicName'),
                  if (clinicAddress.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('ที่อยู่: $clinicAddress'),
                  ],
                  if (hasClinicPhone) ...[
                    const SizedBox(height: 4),
                    Text(
                      'เบอร์โทร: $clinicPhone',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  Text(
                    'ตำแหน่ง: ${_s(need['role']).isEmpty ? 'ผู้ช่วย' : _s(need['role'])}',
                  ),
                  Text(
                    'วันและเวลา: ${_s(need['date'])}  ${_s(need['start'])}-${_s(need['end'])}',
                  ),
                  Text('ค่าตอบแทน: ${_s(need['hourlyRate'])} บาท/ชม.'),
                  if (_s(need['note']).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('หมายเหตุ: ${_s(need['note'])}'),
                  ],
                  if (hasClinicPhone) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _callClinic(context, clinicPhone),
                        icon: const Icon(Icons.phone),
                        label: const Text('โทรหาคลินิก'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (applied)
                    const Text(
                      '✅ คุณสมัครงานนี้แล้ว',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    )
                  else if (onApply != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: applying
                            ? null
                            : () async {
                                try {
                                  await onApply!.call();
                                  if (context.mounted) {
                                    Navigator.pop(context, true);
                                  }
                                } catch (_) {}
                              },
                        icon: applying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: Text(applying ? 'กำลังสมัคร...' : 'สมัครงานนี้'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Screen 2: My Shifts
// ============================================================
class MyShiftsScreen extends StatefulWidget {
  final String staffId;
  const MyShiftsScreen({super.key, required this.staffId});

  @override
  State<MyShiftsScreen> createState() => _MyShiftsScreenState();
}

class _MyShiftsScreenState extends State<MyShiftsScreen> {
  final _payroll = ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  bool _loading = true;
  String _err = '';
  List<Map<String, dynamic>> _items = [];

  bool _disposed = false;
  void _safeSetState(VoidCallback fn) {
    if (!mounted || _disposed) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<Map<String, dynamic>> _extractItems(dynamic resAny) {
    if (resAny is Map) {
      final v = resAny['items'];
      if (v is List) {
        return v
            .whereType<Map>()
            .map((x) => x.cast<String, dynamic>())
            .toList();
      }
      final data = resAny['data'];
      if (data is List) {
        return data
            .whereType<Map>()
            .map((x) => x.cast<String, dynamic>())
            .toList();
      }
      if (data is Map && data['items'] is List) {
        final items2 = data['items'] as List;
        return items2
            .whereType<Map>()
            .map((x) => x.cast<String, dynamic>())
            .toList();
      }
    }
    return [];
  }

  String _s(dynamic v) => (v ?? '').toString();

  double? _toD(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  String _statusThai(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return 'นัดหมายแล้ว';
    if (s == 'scheduled') return 'นัดหมายแล้ว';
    if (s == 'completed') return 'เสร็จสิ้น';
    if (s == 'cancelled') return 'ยกเลิก';
    if (s == 'approved') return 'อนุมัติแล้ว';
    if (s == 'pending') return 'รอดำเนินการ';
    if (s == 'rejected') return 'ไม่ผ่านการอนุมัติ';
    if (s == 'open') return 'เปิดรับอยู่';
    if (s == 'closed') return 'ปิดแล้ว';
    return raw;
  }

  String _clinicPhoneFromShift(Map<String, dynamic> it) {
    final phone1 = _s(it['clinicPhone'] ?? it['clinic_phone']).trim();
    if (phone1.isNotEmpty) return phone1;

    final clinic = it['clinic'];
    if (clinic is Map) {
      final phone2 = _s(clinic['phone'] ?? clinic['clinicPhone']).trim();
      if (phone2.isNotEmpty) return phone2;
    }

    return '';
  }

  Future<void> _callClinicFromShift(Map<String, dynamic> it) async {
    final phone = _clinicPhoneFromShift(it);

    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('คลินิกยังไม่มีเบอร์โทร')),
      );
      return;
    }

    final uri = Uri.parse('tel:$phone');

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเปิดหน้าจอโทรได้')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดหน้าจอโทรได้')),
      );
    }
  }

  String _pickTravelMode(Map<String, dynamic> it) {
    final raw = _s(
      it['travelMode'] ?? it['transportMode'] ?? it['mode'],
    ).trim();
    final m = raw.toLowerCase();
    if (m == 'w' || m == 'walk' || m == 'walking') return 'walk';
    if (m == 'd' || m == 'drive' || m == 'driving' || m == 'car') {
      return 'drive';
    }
    if (m == 'transit' || m == 'public' || m == 'bus' || m == 'train') {
      return 'transit';
    }

    final note = _s(it['note']).toLowerCase();
    final title = _s(it['title']).toLowerCase();
    final role = _s(it['role']).toLowerCase();
    final type = _s(it['type']).toLowerCase();
    final blob = '$note $title $role $type';

    if (blob.contains('รถสาธารณะ') ||
        blob.contains('transit') ||
        blob.contains('bts') ||
        blob.contains('mrt') ||
        blob.contains('bus') ||
        blob.contains('รถเมล์') ||
        blob.contains('รถไฟ')) {
      return 'transit';
    }

    if (blob.contains('เดิน') ||
        blob.contains('walk') ||
        blob.contains('walking') ||
        blob.contains('ใกล้') ||
        blob.contains('near')) {
      return 'walk';
    }

    return 'drive';
  }

  Future<void> _openNavFromShift(Map<String, dynamic> it) async {
    final lat = _toD(
      it['clinicLat'] ??
          it['clinic_lat'] ??
          it['lat'] ??
          (it['clinicLocation'] is Map
              ? (it['clinicLocation'] as Map)['lat']
              : null) ??
          (it['clinic_location'] is Map
              ? (it['clinic_location'] as Map)['lat']
              : null),
    );

    final lng = _toD(
      it['clinicLng'] ??
          it['clinic_lng'] ??
          it['lng'] ??
          (it['clinicLocation'] is Map
              ? (it['clinicLocation'] as Map)['lng']
              : null) ??
          (it['clinic_location'] is Map
              ? (it['clinic_location'] as Map)['lng']
              : null),
    );

    if (lat == null || lng == null || lat == 0 || lng == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('งานนี้ยังไม่มีพิกัดสำหรับนำทาง')),
      );
      return;
    }

    final mode = _pickTravelMode(it);

    final androidNav = Uri.parse(
      'google.navigation:q=$lat,$lng&mode=${mode == 'walk' ? 'w' : 'd'}',
    );

    final webDir = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
      '&travelmode=${mode == 'transit' ? 'transit' : (mode == 'walk' ? 'walking' : 'driving')}',
    );

    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng');

    Future<bool> tryLaunch(Uri u) async {
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }

    if (mode == 'transit') {
      if (await tryLaunch(webDir)) return;
      if (await tryLaunch(geo)) return;
      if (await tryLaunch(androidNav)) return;
    } else {
      if (await tryLaunch(androidNav)) return;
      if (await tryLaunch(geo)) return;
      if (await tryLaunch(webDir)) return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('เปิดแผนที่ไม่ได้')),
    );
  }

  Future<void> _load() async {
    _safeSetState(() {
      _loading = true;
      _err = '';
    });

    try {
      dynamic res;
      try {
        res = await _payroll.get('/shifts', auth: true);
      } catch (_) {
        res = await _payroll.get('/api/shifts', auth: true);
      }

      if (res is Map) {
        final ok = res['ok'];
        if (ok is bool && ok == false) {
          throw Exception(res['message'] ?? 'load shifts failed');
        }
      }

      _safeSetState(() {
        _items = _extractItems(res);
        _loading = false;
      });
    } catch (e) {
      _safeSetState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('งานที่ได้รับของฉัน'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _err.isNotEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _ErrorCard(
                          err: _err,
                          onRetry: _load,
                          onHome: () => Navigator.pop(context),
                        ),
                      ],
                    )
                  : _items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: const [
                            SizedBox(height: 30),
                            Center(child: Text('ยังไม่มีงานที่ได้รับ')),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final it = _items[i];

                            final date = _s(it['date']);
                            final start = _s(it['start']);
                            final end = _s(it['end']);
                            final status = _statusThai(_s(it['status']));
                            final note =
                                _s(it['note']).isEmpty ? 'กะงาน' : _s(it['note']);
                            final rate = _s(it['hourlyRate']);

                            final sub = [
                              if (date.isNotEmpty) 'วันที่ $date',
                              if (start.isNotEmpty || end.isNotEmpty)
                                'เวลา $start - $end',
                              if (rate.isNotEmpty) 'ค่าตอบแทน $rate บาท/ชม.',
                              'สถานะ $status',
                            ].join(' • ');

                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  Icons.assignment_turned_in_outlined,
                                  color: cs.primary,
                                ),
                                title: Text(note),
                                subtitle: Text(sub),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'โทรหาคลินิก',
                                      icon: const Icon(Icons.phone),
                                      onPressed: () => _callClinicFromShift(it),
                                    ),
                                    IconButton(
                                      tooltip: 'นำทางไปคลินิก',
                                      icon: const Icon(Icons.navigation),
                                      onPressed: () => _openNavFromShift(it),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
    );
  }
}