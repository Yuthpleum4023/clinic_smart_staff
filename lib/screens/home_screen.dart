// lib/screens/home_screen.dart
//
// ✅ CLEAN HOME (UI SHELL ONLY) — Router removed 100%
// - ❌ ไม่ยิง /me
// - ❌ ไม่ map role / ไม่ save prefs
// - ❌ ไม่ push ไป ClinicHome/HelperHome แบบ router
// ✅ อ่าน context จาก AppContextResolver/AppContext เท่านั้น
// ✅ Urgent/Market ใช้ token + payroll API ได้ แต่ไม่ยุ่ง auth flow
// ✅ Logout ใช้ Named Route (กัน build scope crash)
//
// IMPORTANT:
// - AuthGateScreen เป็น router หลัก (ตัดสิน login/home)
// - HomeScreen เป็น UI shell (Home/My tabs) เท่านั้น
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_payroll/api/api_config.dart';
import 'package:clinic_payroll/services/auth_storage.dart';
import 'package:clinic_payroll/services/auth_service.dart';

import 'package:clinic_payroll/app/app_context.dart';
import 'package:clinic_payroll/app/app_context_resolver.dart';

import 'package:clinic_payroll/screens/clinic/clinic_home_screen.dart';
import 'package:clinic_payroll/screens/helper/helper_home_screen.dart';

import 'package:clinic_payroll/screens/clinic_shift_need_list_screen.dart';
import 'package:clinic_payroll/screens/helper_open_needs_screen.dart';

// ✅ Local payroll screen อยู่ในไฟล์นี้ (เหมือนเดิม)
import 'package:clinic_payroll/models/employee_model.dart';
import 'package:clinic_payroll/services/storage_service.dart';
import 'package:clinic_payroll/screens/employee_detail_screen.dart';
import 'package:clinic_payroll/screens/add_employee_screen.dart';
import 'package:clinic_payroll/screens/payslip_preview_screen.dart';

// ✅ route names จาก main.dart
import 'package:clinic_payroll/main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  // context (from AppContext)
  bool _ctxLoading = true;
  String _ctxErr = '';
  String _role = ''; // clinic | helper
  String _clinicId = '';
  String _userId = '';
  String _staffId = '';

  // -------------------- Urgent Needs (Top 1-10 summary) --------------------
  bool _urgentLoading = false;
  String _urgentErr = '';
  int _urgentCount = 0;
  Map<String, dynamic>? _urgentFirst;

  @override
  void initState() {
    super.initState();
    _bootstrapContext();
  }

  // -------------------- UI helpers --------------------
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _norm(String s) => s.trim().toLowerCase();

  // -------------------- Context: read-only from AppContext --------------------
  Future<void> _bootstrapContext() async {
    if (!mounted) return;
    setState(() {
      _ctxLoading = true;
      _ctxErr = '';
    });

    try {
      // ✅ โหลดจาก prefs -> validate -> เข้า AppContext
      await AppContextResolver.loadFromPrefs();

      final role = _norm(AppContext.role);
      final uid = (AppContext.userId).trim();
      final cid = (AppContext.clinicId).trim();

      if (role.isEmpty || uid.isEmpty) {
        throw Exception('AppContext ไม่พร้อม (role/userId ว่าง) — กรุณา logout/login ใหม่');
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _userId = uid;
        _clinicId = cid;
        _staffId = ''; // ถ้าคุณเก็บ staffId ใน AppContext ภายหลัง ค่อยเติม
        _ctxLoading = false;
      });

      // ✅ โหลด urgent ต่อ (ไม่ยุ่ง auth)
      await _loadUrgentNeeds();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ctxErr = e.toString();
        _ctxLoading = false;
      });
    }
  }

  bool get _isClinic => _role == 'clinic' || _role == 'admin' || _role == 'clinic_admin';
  bool get _isHelper => _role == 'helper' || _role == 'employee' || _role == 'staff';

  // -------------------- Token helper --------------------
  Future<String?> _getTokenAny() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.isNotEmpty && t != 'null') return t;
    } catch (_) {}

    // fallback scan prefs
    const keys = [
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
      'accessToken',
      'access_token',
    ];
    final prefs = await SharedPreferences.getInstance();
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  // -------------------- Urgent Needs fetch --------------------
  Uri _payrollUri(String path, {Map<String, String>? qs}) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$p');
    return (qs == null) ? uri : uri.replace(queryParameters: qs);
  }

  List<Map<String, dynamic>> _decodeNeedList(dynamic decoded) {
    dynamic listAny = decoded;
    if (decoded is Map) {
      if (decoded['items'] is List) listAny = decoded['items'];
      else if (decoded['data'] is List) listAny = decoded['data'];
      else if (decoded['results'] is List) listAny = decoded['results'];
      else if (decoded['needs'] is List) listAny = decoded['needs'];
    }
    if (listAny is! List) return [];
    return listAny
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<http.Response> _tryGet(Uri uri, {required Map<String, String> headers}) async {
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
  }

  Future<void> _loadUrgentNeeds() async {
    if (_ctxLoading) return;

    if (!mounted) return;
    setState(() {
      _urgentLoading = true;
      _urgentErr = '';
      _urgentCount = 0;
      _urgentFirst = null;
    });

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) {
        throw Exception('no token (กรุณา login ใหม่)');
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      http.Response res;
      Uri u;

      if (_isHelper) {
        // helper: open needs ทั้งหมด
        u = _payrollUri('/shift-needs/open');
        res = await _tryGet(u, headers: headers);

        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs/open');
          res = await _tryGet(u, headers: headers);
        }
        if (res.statusCode == 404) {
          u = _payrollUri('/shift-needs', qs: {'status': 'open'});
          res = await _tryGet(u, headers: headers);
        }
        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs', qs: {'status': 'open'});
          res = await _tryGet(u, headers: headers);
        }
      } else if (_isClinic) {
        final cid = _clinicId.trim();
        if (cid.isEmpty) throw Exception('ไม่พบ clinicId (ลอง logout/login ใหม่)');

        u = _payrollUri('/shift-needs', qs: {'status': 'open', 'clinicId': cid});
        res = await _tryGet(u, headers: headers);

        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs', qs: {'status': 'open', 'clinicId': cid});
          res = await _tryGet(u, headers: headers);
        }

        // fallback เผื่อ backend เปิด /open ให้ clinic
        if (res.statusCode == 404) {
          u = _payrollUri('/shift-needs/open');
          res = await _tryGet(u, headers: headers);
        }
        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs/open');
          res = await _tryGet(u, headers: headers);
        }
      } else {
        throw Exception('role ไม่รองรับ: $_role');
      }

      if (res.statusCode != 200) {
        throw Exception('GET $u -> ${res.statusCode} ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      final list = _decodeNeedList(decoded);

      final openOnly = list.where((n) {
        final status = (n['status'] ?? '').toString().toLowerCase().trim();
        return status.isEmpty || status == 'open';
      }).toList();

      if (!mounted) return;
      setState(() {
        _urgentLoading = false;
        _urgentErr = '';
        _urgentCount = openOnly.length;
        _urgentFirst = openOnly.isNotEmpty ? openOnly.first : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _urgentLoading = false;
        _urgentErr = e.toString();
        _urgentCount = 0;
        _urgentFirst = null;
      });
    }
  }

  // -------------------- Logout (clean + named route) --------------------
  Future<void> _logout() async {
    try {
      await AuthStorage.clearToken();
    } catch (_) {}
    try {
      await AppContextResolver.clear();
    } catch (_) {}

    if (!mounted) return;

    // ✅ กลับไป Gate ด้วย named route (ไม่ใช้ MaterialPageRoute)
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.authGate,
      (_) => false,
    );
  }

  // -------------------- TrustScore gate (Clinic PIN) --------------------
  Future<void> _openTrustScoreFromHome() async {
    if (_ctxLoading) return;

    if (!_isClinic) {
      _snack('TrustScore รวมสำหรับคลินิกเท่านั้น');
      setState(() => _tab = 1);
      return;
    }

    final ok = await _askClinicPin();
    if (ok != true) return;

    if (!mounted) return;
    // TODO: ถ้าคุณมีหน้า TrustScore แยกไฟล์อยู่แล้ว ให้ push ไปหน้านั้น
    _snack('TODO: เชื่อมหน้า TrustScoreLookupScreen (ส่งไฟล์มาเดี๋ยวผมผูกให้)');
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

  // -------------------- Navigation: dashboards (NOT router, just menu) --------------------
  Future<void> _openMyClinic() async {
    if (_clinicId.trim().isEmpty || _userId.trim().isEmpty) {
      _snack('ไม่พบ clinicId/userId (ลอง logout/login ใหม่)');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicHomeScreen(clinicId: _clinicId.trim(), userId: _userId.trim()),
      ),
    );
  }

  Future<void> _openMyHelper() async {
    if (_userId.trim().isEmpty) {
      _snack('ไม่พบ userId (ลอง logout/login ใหม่)');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HelperHomeScreen(
          clinicId: _clinicId.trim(),
          userId: _userId.trim(),
          staffId: _staffId.trim(),
        ),
      ),
    );
  }

  // -------------------- Market --------------------
  Future<void> _openClinicNeedsMarket() async {
    if (_ctxLoading) return;

    if (!_isClinic) {
      _snack('เมนูนี้สำหรับคลินิกเท่านั้น');
      return;
    }
    if (_clinicId.trim().isEmpty) {
      _snack('ไม่พบ clinicId (ลอง logout/login ใหม่)');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicShiftNeedListScreen(clinicId: _clinicId.trim()),
      ),
    );
  }

  Future<void> _openHelperOpenNeeds() async {
    if (_ctxLoading) return;

    if (!_isHelper) {
      _snack('เมนูนี้สำหรับผู้ช่วยเท่านั้น');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HelperOpenNeedsScreen()),
    );
  }

  // -------------------- UI: urgent card (compact) --------------------
  String _oneLineNeed(Map<String, dynamic> n) {
    final title = (n['title'] ?? 'ต้องการผู้ช่วย').toString();
    final date = (n['date'] ?? '').toString();
    final start = (n['start'] ?? '').toString();
    final end = (n['end'] ?? '').toString();
    final rate = (n['hourlyRate'] ?? n['rate'] ?? '').toString();
    final requiredCount = (n['requiredCount'] ?? 1).toString();
    final pieces = <String>[
      if (date.isNotEmpty) date,
      if (start.isNotEmpty || end.isNotEmpty) '$start-$end',
      if (rate.isNotEmpty) '฿$rate/ชม.',
      'ต้องการ $requiredCount คน',
    ];
    return '$title • ${pieces.join(' • ')}';
  }

  Widget _urgentCardCompact() {
    if (!_isClinic && !_isHelper) return const SizedBox.shrink();

    final title = (_isClinic) ? 'งานของคลินิก (open)' : 'คลินิกต้องการผู้ช่วยด่วน';

    if (_urgentLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: const [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Expanded(
                child: Text('กำลังโหลด “งานด่วน” ...', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    if (_urgentErr.isNotEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                _urgentErr,
                style: const TextStyle(fontSize: 12, color: Colors.red),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loadUrgentNeeds,
                      icon: const Icon(Icons.refresh),
                      label: const Text('ลองใหม่'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isHelper ? _openHelperOpenNeeds : _openClinicNeedsMarket,
                      child: const Text('ไปหน้ารายการ'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_urgentCount <= 0) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.flash_on, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isClinic ? 'งาน open ของคลินิกตอนนี้: 0 งาน' : 'งานด่วนตอนนี้: 0 งาน',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: _isHelper ? _openHelperOpenNeeds : _openClinicNeedsMarket,
                child: const Text('ไปดูรายการ'),
              ),
            ],
          ),
        ),
      );
    }

    final line = (_urgentFirst == null) ? '' : _oneLineNeed(_urgentFirst!);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flash_on, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isClinic ? 'งาน open ของคลินิก: $_urgentCount งาน' : 'คลินิกต้องการผู้ช่วยด่วน: $_urgentCount งาน',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'รีเฟรช',
                  onPressed: _loadUrgentNeeds,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (line.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isHelper ? _openHelperOpenNeeds : _openClinicNeedsMarket,
                child: const Text('ดูทั้งหมด'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- Tabs --------------------
  Widget _homeTab() {
    if (_ctxLoading) return const Center(child: CircularProgressIndicator());

    if (_ctxErr.isNotEmpty) {
      return _errorBox(
        title: 'AppContext ไม่พร้อม',
        message: _ctxErr,
        onRetry: _bootstrapContext,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _urgentCardCompact(),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TrustScore ผู้ช่วย (ศูนย์กลาง)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('กดเพื่อดูคะแนนผู้ช่วย — ต้องยืนยัน PIN คลินิกก่อน', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openTrustScoreFromHome,
                    icon: const Icon(Icons.verified),
                    label: const Text('ดู TrustScore'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ตลาดงาน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.local_hospital_outlined),
                  title: const Text('คลินิกต้องการผู้ช่วย'),
                  subtitle: const Text('รายการประกาศงาน (shift-needs)'),
                  onTap: _openClinicNeedsMarket,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('ผู้ช่วยพร้อมทำงาน'),
                  subtitle: const Text('รายการงานว่าง (open) และสมัครงาน'),
                  onTap: _openHelperOpenNeeds,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _myTab() {
    if (_ctxLoading) return const Center(child: CircularProgressIndicator());

    if (_ctxErr.isNotEmpty) {
      return _errorBox(
        title: 'AppContext ไม่พร้อม',
        message: _ctxErr,
        onRetry: _bootstrapContext,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'role: ${_role.isEmpty ? '-' : _role}\n'
                  'clinicId: ${_clinicId.isEmpty ? '-' : _clinicId}\n'
                  'userId: ${_userId.isEmpty ? '-' : _userId}\n'
                  'staffId: ${_staffId.isEmpty ? '-' : _staffId}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Auth: ${ApiConfig.authBaseUrl}\nScore: ${ApiConfig.scoreBaseUrl}\nPayroll: ${ApiConfig.payrollBaseUrl}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_isClinic)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: const Text('My Clinic'),
                  subtitle: const Text('แดชบอร์ดคลินิก'),
                  onTap: _openMyClinic,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Payroll (Local)'),
                  subtitle: const Text('รายชื่อพนักงาน + สลิป (ในเครื่อง)'),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LocalPayrollScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        if (_isHelper)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('My (Helper)'),
                  subtitle: const Text('แดชบอร์ดผู้ช่วย'),
                  onTap: _openMyHelper,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.work_outline),
                  title: const Text('งานว่าง (ตลาดงาน)'),
                  subtitle: const Text('ดู open needs และสมัครงาน'),
                  onTap: _openHelperOpenNeeds,
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: _logout,
          ),
        ),
      ],
    );
  }

  Widget _errorBox({required String title, required String message, required VoidCallback onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Text(message, style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ลองใหม่'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_homeTab(), _myTab()];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic Payroll'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช context',
            icon: const Icon(Icons.refresh),
            onPressed: _bootstrapContext,
          ),
          IconButton(
            tooltip: 'รีเฟรช Urgent',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _loadUrgentNeeds(),
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'My'),
        ],
      ),
    );
  }
}

/// ============================================================
/// ✅ Local Payroll (เก็บในเครื่อง) — เหมือนเดิม
/// ============================================================
class LocalPayrollScreen extends StatefulWidget {
  const LocalPayrollScreen({super.key});

  @override
  State<LocalPayrollScreen> createState() => _LocalPayrollScreenState();
}

class _LocalPayrollScreenState extends State<LocalPayrollScreen> {
  List<EmployeeModel> employees = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    final data = await StorageService.loadEmployees();
    if (!mounted) return;
    setState(() {
      employees = data;
      isLoading = false;
    });
  }

  bool _isParttime(EmployeeModel e) => e.employmentType.toLowerCase().trim() == 'parttime';

  String _subtitle(EmployeeModel e) {
    if (_isParttime(e)) {
      return 'Part-time • ${e.position} • ${e.hourlyWage.toStringAsFixed(0)} บาท/ชม.';
    }
    return 'Full-time • ${e.position} • ฐาน ${e.baseSalary.toStringAsFixed(0)} • โบนัส ${e.bonus.toStringAsFixed(0)} • ขาด/ลา ${e.absentDays} วัน';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _deleteEmployee(int index) async {
    final removed = employees[index];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบ “${removed.fullName}” ใช่ไหม?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => employees.removeAt(index));
    await StorageService.saveEmployees(employees);
    await _refreshData();
    _snack('ลบ ${removed.fullName} แล้ว');
  }

  Future<void> _goAddEmployee() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddEmployeeScreen()));
    await _refreshData();
  }

  Future<void> _openPayslipPreview(EmployeeModel emp) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipPreviewScreen(emp: emp)));
    await _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll (Local)'),
        actions: [
          IconButton(onPressed: _goAddEmployee, icon: const Icon(Icons.add)),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : employees.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('ยังไม่มีข้อมูลพนักงานที่บันทึกไว้'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _goAddEmployee,
                        icon: const Icon(Icons.add),
                        label: const Text('เพิ่มพนักงานคนแรก'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshData,
                  child: ListView.builder(
                    itemCount: employees.length,
                    itemBuilder: (context, index) {
                      final emp = employees[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(emp.fullName),
                          subtitle: Text(_subtitle(emp)),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => EmployeeDetailScreen(clinicId: '', employee: emp)),
                            );
                            await _refreshData();
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'ดู/พิมพ์สลิป (PDF)',
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                                onPressed: () => _openPayslipPreview(emp),
                              ),
                              IconButton(
                                tooltip: 'ลบพนักงาน',
                                icon: const Icon(Icons.delete, color: Colors.grey),
                                onPressed: () => _deleteEmployee(index),
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
