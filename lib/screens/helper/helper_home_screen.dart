// lib/screens/helper/helper_home_screen.dart
//
// ✅ FULL FILE — HelperHomeScreen (clinic_smart_staff) + OpenNeeds + MyShifts + HelperAvailability
// - ✅ เปลี่ยน package clinic_payroll -> clinic_smart_staff (กันแดงทั้งไฟล์)
// - ✅ ไม่ hardcode สีฟ้า: AppBar ปล่อยให้ Theme (ม่วง) คุม
// - ✅ งานว่าง: GET /shift-needs/open + สมัคร: POST /shift-needs/:id/apply
// - ✅ งานของฉัน: GET /shifts + ปุ่มนำทาง (anti-cache) ด้วย google.navigation + web dir fallback
// - ✅ ตารางเวลาว่างของฉัน: ใช้ HelperAvailabilityService + HelperAvailabilityModel ของท่าน (local storage)
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:clinic_smart_staff/screens/auth/auth_gate_screen.dart';
import 'package:clinic_smart_staff/screens/home_screen.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

// ✅ ใช้ service + model ของคุณ
import 'package:clinic_smart_staff/services/helper_availability_service.dart';
import 'package:clinic_smart_staff/models/helper_availability_model.dart';

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

  // context keys (ตาม AuthGate ที่เราเซฟไว้)
  static const _kRole = 'app_role';
  static const _kClinicId = 'app_clinic_id';
  static const _kUserId = 'app_user_id';
  static const _kStaffId = 'app_staff_id';

  final _authClient = ApiClient(baseUrl: ApiConfig.authBaseUrl);

  @override
  void initState() {
    super.initState();
    _clinicId = widget.clinicId;
    _userId = widget.userId;
    _staffId = widget.staffId.trim();
    _boot();
  }

  // -------------------- auth helpers --------------------
  Future<void> _clearAllAuth() async {
    // ✅ ตาม AuthStorage ของท่านจริง
    await AuthStorage.clearToken();

    final prefs = await SharedPreferences.getInstance();
    for (final k in [_kRole, _kClinicId, _kUserId, _kStaffId]) {
      await prefs.remove(k);
    }
  }

  Future<Map<String, dynamic>> _me() async {
    final data = await _authClient.get(ApiConfig.me, auth: true);
    if (data['user'] is Map) {
      return (data['user'] as Map).cast<String, dynamic>();
    }
    return data;
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _err = '';
    });

    try {
      if (_staffId.isNotEmpty) {
        await _saveStaffId(_staffId);
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_kStaffId) ?? '').trim();
      if (saved.isNotEmpty) {
        _staffId = saved;
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final token = await AuthStorage.getToken();
      if (token == null || token.trim().isEmpty || token.trim() == 'null') {
        throw Exception('no token (โปรด login ใหม่)');
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

      if (staffId.isEmpty) {
        throw Exception(
          'ไม่พบ staffId ใน /me (ต้องให้ backend ใส่ staffId ให้บัญชีผู้ช่วย)',
        );
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
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _goHome(),
      child: Scaffold(
        appBar: AppBar(
          // ✅ ปล่อยให้ Theme จาก main.dart คุมสี
          leading: IconButton(
            tooltip: 'กลับหน้า Home',
            icon: const Icon(Icons.home),
            onPressed: _goHome,
          ),
          title: const Text('Helper'),
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
                    _MenuCard(
                      title: 'งานว่าง',
                      subtitle:
                          'รายการ ShiftNeed ที่เปิดรับ (GET /shift-needs/open)',
                      icon: Icons.work_outline,
                      iconColor: cs.primary,
                      onTap: () {
                        if (_staffId.isEmpty) {
                          _snack('ยังไม่มี staffId');
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OpenNeedsScreen(staffId: _staffId),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _MenuCard(
                      title: 'งานของฉัน',
                      subtitle: 'Shifts ของฉัน (GET /shifts)',
                      icon: Icons.assignment_turned_in_outlined,
                      iconColor: cs.primary,
                      onTap: () {
                        if (_staffId.isEmpty) {
                          _snack('ยังไม่มี staffId');
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MyShiftsScreen(staffId: _staffId),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _MenuCard(
                      title: 'ตารางเวลาว่างของฉัน',
                      subtitle: 'HelperAvailability (ใช้ Service + Model ของคุณ)',
                      icon: Icons.calendar_month,
                      iconColor: cs.primary,
                      onTap: () {
                        if (_staffId.isEmpty) {
                          _snack('ยังไม่มี staffId');
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                HelperAvailabilityScreen(helperId: _staffId),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'clinicId=$_clinicId\nuserId=$_userId\nstaffId=${_staffId.isEmpty ? "-" : _staffId}',
                      style: TextStyle(color: Colors.grey.shade700),
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

  @override
  Widget build(BuildContext context) {
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
            Text(err, style: TextStyle(color: Colors.grey.shade700)),
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
                    label: const Text('กลับ Home'),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> res) {
    final v = res['items'];
    if (v is List) {
      return v
          .whereType<Map>()
          .map((x) => x.cast<String, dynamic>())
          .toList();
    }
    return [];
  }

  String _s(dynamic v) => (v ?? '').toString();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = '';
    });

    try {
      final res = await _payroll.get('/shift-needs/open', auth: true);
      setState(() {
        _items = _extractItems(res);
        _loading = false;
      });
    } catch (e) {
      setState(() {
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

  Future<void> _apply(String id) async {
    try {
      await _payroll.post('/shift-needs/$id/apply', auth: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ สมัครงานสำเร็จ')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('สมัครไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('งานว่าง'),
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
                            Center(child: Text('ยังไม่มีงานว่าง')),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final it = _items[i];
                            final title = _s(it['title']).isNotEmpty
                                ? _s(it['title'])
                                : 'ต้องการผู้ช่วย';
                            final date = _s(it['date']);
                            final start = _s(it['start']);
                            final end = _s(it['end']);
                            final rate = it['hourlyRate'];
                            final needId = _s(it['_id']).isNotEmpty
                                ? _s(it['_id'])
                                : _s(it['id']);
                            final already = _applied(it);

                            final sub = [
                              if (date.isNotEmpty) 'วันที่ $date',
                              if (start.isNotEmpty || end.isNotEmpty)
                                'เวลา $start - $end',
                              if (rate != null) 'ค่าจ้าง/ชม. $rate',
                            ].join(' • ');

                            return Card(
                              child: ListTile(
                                leading:
                                    Icon(Icons.work_outline, color: cs.primary),
                                title: Text(title),
                                subtitle:
                                    Text(sub.isEmpty ? 'รายละเอียดไม่ครบ' : sub),
                                trailing: already
                                    ? const Chip(
                                        label: Text('สมัครแล้ว'),
                                        visualDensity: VisualDensity.compact,
                                      )
                                    : const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => NeedDetailScreen(
                                        need: it,
                                        onApply: (already || needId.isEmpty)
                                            ? null
                                            : () => _apply(needId),
                                      ),
                                    ),
                                  );
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
  final VoidCallback? onApply;

  const NeedDetailScreen({super.key, required this.need, this.onApply});

  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final title =
        _s(need['title']).isNotEmpty ? _s(need['title']) : 'รายละเอียดงาน';
    final applied = (_s(need['_applied']).toLowerCase() == 'true');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
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
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text('วันที่: ${_s(need['date'])}'),
                  Text('เวลา: ${_s(need['start'])} - ${_s(need['end'])}'),
                  Text('ค่าจ้าง/ชม.: ${_s(need['hourlyRate'])}'),
                  if (_s(need['note']).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('หมายเหตุ: ${_s(need['note'])}'),
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
                        onPressed: onApply,
                        icon: const Icon(Icons.send),
                        label: const Text('สมัครงานนี้'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('ดู JSON (debug)'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  const JsonEncoder.withIndent('  ').convert(need),
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Screen 2: My Shifts (staff เห็นของตัวเองจาก token -> GET /shifts)
// ============================================================
class MyShiftsScreen extends StatefulWidget {
  final String staffId; // เก็บไว้แค่ debug/แสดง ไม่ต้องส่ง query
  const MyShiftsScreen({super.key, required this.staffId});

  @override
  State<MyShiftsScreen> createState() => _MyShiftsScreenState();
}

class _MyShiftsScreenState extends State<MyShiftsScreen> {
  final _payroll = ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  bool _loading = true;
  String _err = '';
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> res) {
    final v = res['items'];
    if (v is List) {
      return v
          .whereType<Map>()
          .map((x) => x.cast<String, dynamic>())
          .toList();
    }
    return [];
  }

  String _s(dynamic v) => (v ?? '').toString();

  // =========================
  // ✅ NAV HELPERS
  // =========================
  double? _toD(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  // ✅✅✅ FIX: ANTI MAP CACHE (ใช้ google.navigation + dir destination only)
  Future<void> _openNavFromShift(Map<String, dynamic> it) async {
    // ✅ รองรับหลายชื่อ field (เผื่อ backend ส่งไม่เหมือนกัน)
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
        const SnackBar(content: Text('งานนี้ยังไม่มีพิกัดคลินิกสำหรับนำทาง')),
      );
      return;
    }

    // ✅ ANTI-CACHE: ไม่ใช้ search/query ที่ทำให้ Google เดา/แคชชื่อสถานที่
    final androidNav = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webDir = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng');

    try {
      if (await canLaunchUrl(androidNav)) {
        await launchUrl(androidNav, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(webDir)) {
        await launchUrl(webDir, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(geo)) {
        await launchUrl(geo, mode: LaunchMode.externalApplication);
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิดแผนที่ไม่ได้')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('นำทางล้มเหลว: $e')),
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = '';
    });

    try {
      final res = await _payroll.get('/shifts', auth: true);

      final ok = res['ok'];
      if (ok is bool && ok == false) {
        throw Exception(res['message'] ?? 'load shifts failed');
      }

      setState(() {
        _items = _extractItems(res);
        _loading = false;
      });
    } catch (e) {
      setState(() {
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
        title: const Text('งานของฉัน'),
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
                            Center(child: Text('ยังไม่มีงานของฉัน')),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final it = _items[i];

                            final date = _s(it['date']);
                            final start = _s(it['start']);
                            final end = _s(it['end']);
                            final status = _s(it['status']).isEmpty
                                ? 'scheduled'
                                : _s(it['status']);
                            final note =
                                _s(it['note']).isEmpty ? 'Shift' : _s(it['note']);
                            final rate = _s(it['hourlyRate']);

                            final sub = [
                              if (date.isNotEmpty) 'วันที่ $date',
                              if (start.isNotEmpty || end.isNotEmpty)
                                'เวลา $start - $end',
                              if (rate.isNotEmpty) '฿/ชม. $rate',
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
                                trailing: IconButton(
                                  tooltip: 'นำทางไปคลินิก',
                                  icon: const Icon(Icons.navigation),
                                  onPressed: () => _openNavFromShift(it),
                                ),
                              ),
                            );
                          },
                        ),
            ),
    );
  }
}

// ============================================================
// Screen 3: Helper Availability — ใช้ Model ของคุณครบฟิลด์
// ============================================================
class HelperAvailabilityScreen extends StatefulWidget {
  final String helperId; // ใช้ staffId เป็น helperId
  const HelperAvailabilityScreen({super.key, required this.helperId});

  @override
  State<HelperAvailabilityScreen> createState() =>
      _HelperAvailabilityScreenState();
}

class _HelperAvailabilityScreenState extends State<HelperAvailabilityScreen> {
  bool _loading = true;
  String _err = '';
  List<HelperAvailability> _items = [];

  static const _kHelperName = 'helper_name';
  static const _kHelperRole = 'helper_role';
  static const _kHelperLocationLabel = 'helper_location_label';
  static const _kHelperLocationAddress = 'helper_location_address';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = '';
    });

    try {
      final list =
          await HelperAvailabilityService.loadByHelper(widget.helperId);
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _remove(HelperAvailability item) async {
    await HelperAvailabilityService.removeById(
      item.id,
      helperId: widget.helperId,
    );
    await _load();
  }

  String _genId() => 'hav_${DateTime.now().millisecondsSinceEpoch}';

  DateTime _parseDate(String s) {
    try {
      final p = s.split('-').map((e) => int.tryParse(e) ?? 0).toList();
      if (p.length == 3) return DateTime(p[0], p[1], p[2]);
    } catch (_) {}
    return DateTime.now();
  }

  TimeOfDay _parseTime(String s) {
    try {
      final p = s.split(':');
      if (p.length == 2) {
        return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      }
    } catch (_) {}
    return const TimeOfDay(hour: 9, minute: 0);
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<Map<String, String>> _loadDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': (prefs.getString(_kHelperName) ?? '').trim(),
      'role': (prefs.getString(_kHelperRole) ?? 'ผู้ช่วย').trim(),
      'label': (prefs.getString(_kHelperLocationLabel) ?? '').trim(),
      'addr': (prefs.getString(_kHelperLocationAddress) ?? '').trim(),
    };
  }

  Future<void> _saveDefaults({
    required String name,
    required String role,
    required String label,
    required String addr,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHelperName, name);
    await prefs.setString(_kHelperRole, role);
    await prefs.setString(_kHelperLocationLabel, label);
    await prefs.setString(_kHelperLocationAddress, addr);
  }

  Future<void> _addOrEdit({HelperAvailability? existing}) async {
    final now = DateTime.now();

    DateTime selectedDate = existing != null
        ? _parseDate(existing.date)
        : DateTime(now.year, now.month, now.day);
    TimeOfDay start = existing != null
        ? _parseTime(existing.start)
        : const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end = existing != null
        ? _parseTime(existing.end)
        : const TimeOfDay(hour: 18, minute: 0);

    final defaults = await _loadDefaults();

    final nameCtrl = TextEditingController(
      text: (existing?.helperName ?? defaults['name'] ?? '').trim(),
    );
    final roleCtrl = TextEditingController(
      text: (existing?.role ?? defaults['role'] ?? 'ผู้ช่วย').trim(),
    );
    final noteCtrl = TextEditingController(text: (existing?.note ?? '').trim());

    // ✅ ฟิลด์เพิ่มเติม (ถ้า model ของท่านมี)
    final labelCtrl = TextEditingController(
      text: (existing?.locationLabel ?? defaults['label'] ?? '').trim(),
    );
    final addrCtrl = TextEditingController(
      text: (existing?.locationAddress ?? defaults['addr'] ?? '').trim(),
    );

    String status = (existing?.status ?? 'open').trim();
    if (status.isEmpty) status = 'open';

    bool ok = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setM) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null ? 'เพิ่มเวลาว่าง' : 'แก้ไขเวลาว่าง',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(now.year - 1),
                              lastDate: DateTime(now.year + 2),
                            );
                            if (d != null) {
                              selectedDate = d;
                              setM(() {});
                            }
                          },
                          icon: const Icon(Icons.calendar_month),
                          label: Text('วันที่ ${_fmtDate(selectedDate)}'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: start,
                            );
                            if (t != null) {
                              start = t;
                              setM(() {});
                            }
                          },
                          icon: const Icon(Icons.access_time),
                          label: Text('เริ่ม ${_fmtTime(start)}'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: end,
                            );
                            if (t != null) {
                              end = t;
                              setM(() {});
                            }
                          },
                          icon: const Icon(Icons.access_time_filled),
                          label: Text('จบ ${_fmtTime(end)}'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อผู้ช่วย (helperName)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: roleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'บทบาทงาน (role) เช่น ผู้ช่วยทันตแพทย์',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: status,
                      items: const [
                        DropdownMenuItem(
                            value: 'open', child: Text('open (ว่าง)')),
                        DropdownMenuItem(
                            value: 'booked', child: Text('booked (ติดงานแล้ว)')),
                        DropdownMenuItem(
                            value: 'cancelled', child: Text('cancelled (ยกเลิก)')),
                      ],
                      onChanged: (v) => setM(() => status = (v ?? 'open')),
                      decoration: const InputDecoration(
                        labelText: 'สถานะ (status)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: labelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'โซน/สาขา (locationLabel)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: addrCtrl,
                      decoration: const InputDecoration(
                        labelText: 'รายละเอียดตำแหน่ง (locationAddress)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ (note)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              ok = true;
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.save),
                            label: const Text('บันทึก'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                            label: const Text('ยกเลิก'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (!ok) return;

    final item = HelperAvailability(
      id: existing?.id ?? _genId(),
      helperId: widget.helperId,
      helperName: nameCtrl.text.trim(),
      role: roleCtrl.text.trim().isEmpty ? 'ผู้ช่วย' : roleCtrl.text.trim(),
      date: _fmtDate(selectedDate),
      start: _fmtTime(start),
      end: _fmtTime(end),
      status: status,
      note: noteCtrl.text.trim(),
      // ✅ ฟิลด์พิกัด/โซน (ถ้า model ของท่านมี)
      locationLabel: labelCtrl.text.trim(),
      locationAddress: addrCtrl.text.trim(),
    );

    await _saveDefaults(
      name: item.helperName,
      role: item.role,
      label: item.locationLabel,
      addr: item.locationAddress,
    );

    if (existing == null) {
      await HelperAvailabilityService.add(item);
    } else {
      await HelperAvailabilityService.update(item);
    }

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตารางเวลาว่างของฉัน'),
        actions: [
          IconButton(
            tooltip: 'เพิ่ม',
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: cs.primary,
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err.isNotEmpty
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
                        Center(child: Text('ยังไม่มีเวลาว่างที่บันทึกไว้')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final e = _items[i];
                        final sub = '${e.start} - ${e.end}'
                            '${e.role.trim().isEmpty ? '' : ' • ${e.role}'}'
                            '${e.locationLabel.trim().isEmpty ? '' : ' • ${e.locationLabel}'}'
                            '${e.status.trim().isEmpty ? '' : ' • ${e.status}'}';

                        return Card(
                          child: ListTile(
                            leading:
                                Icon(Icons.calendar_month, color: cs.primary),
                            title: Text(
                              '${e.date}  (${e.helperName.isEmpty ? "ไม่ระบุชื่อ" : e.helperName})',
                            ),
                            subtitle: Text(sub),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  await _addOrEdit(existing: e);
                                } else if (v == 'del') {
                                  await _remove(e);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
                                PopupMenuItem(value: 'del', child: Text('ลบ')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
