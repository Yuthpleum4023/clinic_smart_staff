// lib/screens/home_screen.dart
//
// ✅ CLEAN HOME (COMMERCIAL POLISH) — TrustScore READY + Biometric Attendance (Employee + Helper) + Payslip
// ✅ UPDATE (NEW):
// - ✅ เพิ่ม “ดูประวัติการเช็คอินย้อนหลัง” (Attendance History) แบบสวย + ใช้งานจริง
// - ✅ ดึงจาก backend: GET /attendance/me (fallback: /api/attendance/me)
// - ✅ ค้นหา/กรองช่วงเวลา: 7/30/90 วัน (พร้อมเลือกเองด้วย DatePicker)
// - ✅ เปิดดูรายละเอียดแต่ละวัน (เวลาเข้า/ออก + ชั่วโมงรวม)
// - ✅ ไม่เพิ่ม package ใหม่
//
// ✅ IMPORTANT:
// - ยังใช้ SafeArea + IndexedStack แก้ปุ่ม bottom nav เงียบ
// - ไม่บังคับ setState เปลี่ยนแท็บจากระบบ (กันเด้งกลับ)
//
// ✅ PATCH (NEW):
// - ✅ กันยิง attendance ซ้ำด้วย _attPosting
// - ✅ ถ้า endpoint แรกได้ 409 = STOP ทันที (ห้าม fallback ไป /api/...)
// - ✅ ถ้า endpoint แรกได้ 404 ค่อย fallback
// - ✅ ลดโอกาสสร้าง session ซ้ำจากการกดรัว / fallback ผิด logic
//
// ✅ NEW (POLICY / FEATURE FLAGS):
// - ✅ โหลด clinic policy จาก backend
// - ✅ ใช้ feature flags จาก backend เป็นตัวกำหนด flow หลัก
// - ✅ local premium flag ยังเก็บไว้เป็น fallback สำหรับโหมดทดสอบ
// - ✅ แสดง “กติกาการทำงานของคลินิก” แบบภาษาคนให้ employee/helper เห็น
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// ✅ Biometric
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';
import 'package:clinic_smart_staff/services/auth_service.dart';

import 'package:clinic_smart_staff/app/app_context.dart';
import 'package:clinic_smart_staff/app/app_context_resolver.dart';

import 'package:clinic_smart_staff/screens/clinic/clinic_home_screen.dart';
import 'package:clinic_smart_staff/screens/helper/helper_home_screen.dart';

import 'package:clinic_smart_staff/screens/clinic_shift_need_list_screen.dart';
import 'package:clinic_smart_staff/screens/helper_open_needs_screen.dart';

// ✅ TrustScore screen
import 'package:clinic_smart_staff/screens/trustscore_lookup_screen.dart';

// ✅ Local payroll screen อยู่ในไฟล์นี้ (เหมือนเดิม)
import 'package:clinic_smart_staff/models/employee_model.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';
import 'package:clinic_smart_staff/screens/employee_detail_screen.dart';
import 'package:clinic_smart_staff/screens/add_employee_screen.dart';
import 'package:clinic_smart_staff/screens/payslip_preview_screen.dart';

// ✅ route names จาก main.dart
import 'package:clinic_smart_staff/main.dart';

enum _AttendanceSubmitResult {
  success,
  alreadyDone,
  unauthorized,
  forbidden,
  failed,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  // ✅ NEW: กัน logic ภายในไปบังคับแท็บทับตอน user กดเอง
  bool _didSetInitialTab = false;

  // context
  bool _ctxLoading = true;
  String _ctxErr = '';
  String _role = ''; // admin | employee | helper
  String _clinicId = '';
  String _userId = '';
  String _staffId = '';

  // -------------------- Premium gate (LOCAL FALLBACK FLAG) --------------------
  static const String _kPremiumAttendanceKey = 'premium_attendance_enabled';
  bool _premiumLoading = true;
  bool _premiumAttendanceEnabled = false;

  // -------------------- Policy / Feature Flags (BACKEND) --------------------
  bool _policyLoading = false;
  String _policyErr = '';
  Map<String, dynamic> _policy = <String, dynamic>{};
  Map<String, dynamic> _features = <String, dynamic>{};
  List<String> _policyLines = [];

  // -------------------- Urgent Needs --------------------
  bool _urgentLoading = false;
  String _urgentErr = '';
  int _urgentCount = 0;
  Map<String, dynamic>? _urgentFirst;

  // -------------------- Employee payslip list (closed months) --------------------
  bool _payslipLoading = false;
  String _payslipErr = '';
  List<Map<String, dynamic>> _closedMonths = [];

  // -------------------- Attendance (Today preview) --------------------
  bool _attLoading = false;
  String _attErr = '';
  String _attStatusLine = '';
  bool _attCheckedIn = false;
  bool _attCheckedOut = false;

  // ✅ NEW: กันยิง submit ซ้ำ
  bool _attPosting = false;

  // -------------------- Biometric --------------------
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _bioLoading = false;

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

  void _tapLog(String msg) {
    debugPrint('TAP -> $msg');
  }

  String _norm(String s) => s.trim().toLowerCase();

  String _friendlyAuthError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('no token') || s.contains('token')) {
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    }
    if (s.contains('timeout')) {
      return 'เชื่อมต่อช้าเกินไป กรุณาลองใหม่';
    }
    if (s.contains('unauthorized') || s.contains('401')) {
      return 'ไม่สามารถยืนยันตัวตนได้ กรุณาเข้าสู่ระบบใหม่';
    }
    if (s.contains('forbidden') || s.contains('403')) {
      return 'ไม่มีสิทธิ์ใช้งานเมนูนี้';
    }
    return 'เกิดข้อผิดพลาด กรุณาลองใหม่';
  }

  String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // -------------------- Token helper --------------------
  Future<String?> _getTokenAny() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.isNotEmpty && t != 'null') return t;
    } catch (_) {}

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

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      String p = parts[1];
      p = p.replaceAll('-', '+').replaceAll('_', '/');
      while (p.length % 4 != 0) {
        p += '=';
      }
      final decoded = utf8.decode(base64Url.decode(p));
      final obj = jsonDecode(decoded);
      if (obj is Map) return Map<String, dynamic>.from(obj);
      return null;
    } catch (_) {
      return null;
    }
  }

  // -------------------- Premium (LOCAL FLAG) --------------------
  Future<void> _loadPremiumFlags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_kPremiumAttendanceKey) ?? false;
      if (!mounted) return;
      setState(() {
        _premiumAttendanceEnabled = v;
        _premiumLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _premiumAttendanceEnabled = false;
        _premiumLoading = false;
      });
    }
  }

  Future<void> _setPremiumAttendanceEnabled(bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPremiumAttendanceKey, v);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _premiumAttendanceEnabled = v;
    });
    if (v && _isAttendanceUser) {
      await _refreshAttendanceToday();
    }
  }

  // -------------------- Role guards --------------------
  bool get _isClinic =>
      _role == 'admin' || _role == 'clinic' || _role == 'clinic_admin';
  bool get _isEmployee =>
      _role == 'employee' || _role == 'staff' || _role == 'emp';
  bool get _isHelper => _role == 'helper';
  bool get _isAttendanceUser => _isEmployee || _isHelper;

  // -------------------- Feature helpers --------------------
  bool _featureEnabled(String key, {bool fallback = false}) {
    final v = _features[key];
    if (v is bool) return v;
    return fallback;
  }

  bool get _hasBackendPolicy => _policy.isNotEmpty;

  bool get _attendancePremiumEnabled {
    // ✅ ใช้ backend feature ก่อน
    if (_hasBackendPolicy) {
      return _featureEnabled('fingerprintAttendance', fallback: false);
    }
    // ✅ fallback local flag ตอน backend policy ยังไม่มา/ยังไม่ผูกจริง
    return _premiumAttendanceEnabled;
  }

  bool get _autoOtEnabled {
    if (_hasBackendPolicy) {
      return _featureEnabled('autoOtCalculation', fallback: false);
    }
    return _premiumAttendanceEnabled;
  }

  bool get _policyHumanReadableEnabled {
    if (_hasBackendPolicy) {
      return _featureEnabled('policyHumanReadable', fallback: true);
    }
    return true;
  }

  String _hhmm(dynamic v, {String fallback = '--:--'}) {
    final s = (v ?? '').toString().trim();
    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) return s;
    return fallback;
  }

  List<String> _buildRoleAwarePolicyLines(Map<String, dynamic> p) {
    final lines = <String>[];

    final realTimeOnly = p['realTimeAttendanceOnly'] == true;
    final manualNeedApproval = p['manualAttendanceRequireApproval'] == true;
    final manualReasonRequired = p['manualReasonRequired'] == true;
    final employeeOnlyOt = p['employeeOnlyOt'] == true;
    final requireOtApproval = p['requireOtApproval'] == true;
    final lockAfterClose = p['lockAfterPayrollClose'] == true;

    final otWindowStart = _hhmm(p['otWindowStart'], fallback: '');
    final otWindowEnd = _hhmm(p['otWindowEnd'], fallback: '');

    if (_isHelper) {
      lines.add('ค่าจ้างของผู้ช่วยคิดจากเวลาทำงานจริง');
      if (employeeOnlyOt) {
        lines.add('ผู้ช่วยไม่มี OT แยกต่างหาก ระบบจะคำนวณตามเวลาทำงานจริง');
      }
      if (realTimeOnly) {
        lines.add('การลงเวลาทำงานต้องทำแบบเรียลไทม์');
      }
      if (manualNeedApproval) {
        lines.add('หากลืมลงเวลา ต้องส่งคำขอแก้ไขเวลาและรอผู้ดูแลอนุมัติ');
      }
      if (manualReasonRequired) {
        lines.add('การแก้ไขเวลาทำงานต้องระบุเหตุผล');
      }
      if (lockAfterClose) {
        lines.add('เมื่อปิดงวดเงินเดือนแล้ว จะไม่สามารถแก้ไขเวลาย้อนหลังได้');
      }
      return lines;
    }

    if (_isEmployee) {
      if (realTimeOnly) {
        lines.add('การลงเวลาทำงานต้องทำแบบเรียลไทม์');
      }
      if (otWindowStart.isNotEmpty && otWindowEnd.isNotEmpty) {
        lines.add('OT จะคิดเฉพาะช่วง $otWindowStart - $otWindowEnd');
        lines.add('เวลานอกช่วงดังกล่าวจะไม่ถูกนับเป็น OT');
      }
      if (requireOtApproval) {
        lines.add('OT ต้องได้รับการอนุมัติก่อนจึงจะถูกนำไปคิดเงิน');
      }
      if (manualNeedApproval) {
        lines.add('หากลืมลงเวลา ต้องส่งคำขอแก้ไขเวลาและรอผู้ดูแลอนุมัติ');
      }
      if (manualReasonRequired) {
        lines.add('การแก้ไขเวลาทำงานต้องระบุเหตุผล');
      }
      if (lockAfterClose) {
        lines.add('เมื่อปิดงวดเงินเดือนแล้ว จะไม่สามารถแก้ไขเวลาย้อนหลังได้');
      }
      return lines;
    }

    // clinic/admin
    if (otWindowStart.isNotEmpty && otWindowEnd.isNotEmpty) {
      lines.add('คลินิกตั้งช่วงเวลา OT ไว้ที่ $otWindowStart - $otWindowEnd');
    }
    if (requireOtApproval) {
      lines.add('OT ต้องได้รับการอนุมัติก่อนเข้าสู่ payroll');
    }
    if (manualNeedApproval) {
      lines.add('การแก้ไขเวลาทำงานต้องได้รับการอนุมัติ');
    }
    if (lockAfterClose) {
      lines.add('เมื่อปิดงวดเงินเดือนแล้ว จะไม่สามารถแก้ไขเวลาย้อนหลังได้');
    }

    return lines;
  }

  void _applyPolicyFromMap(Map<String, dynamic> p) {
    final featuresAny = p['features'];
    final features = (featuresAny is Map)
        ? Map<String, dynamic>.from(featuresAny)
        : <String, dynamic>{};

    final lines = _buildRoleAwarePolicyLines(p);

    if (!mounted) return;
    setState(() {
      _policy = p;
      _features = features;
      _policyLines = lines;
      _policyErr = '';
    });
  }

  // -------------------- Context bootstrap --------------------
  Future<void> _bootstrapContext() async {
    if (!mounted) return;
    setState(() {
      _ctxLoading = true;
      _ctxErr = '';
    });

    await _loadPremiumFlags();

    try {
      await AppContextResolver.loadFromPrefs();

      String role = _norm(AppContext.role);
      String uid = (AppContext.userId).trim();
      String cid = (AppContext.clinicId).trim();

      String sid = '';
      final token = await _getTokenAny();
      if (token != null && token.isNotEmpty) {
        final payload = _decodeJwtPayload(token);
        if (payload != null) {
          role = role.isNotEmpty ? role : _norm('${payload['role'] ?? ''}');
          uid = uid.isNotEmpty ? uid : ('${payload['userId'] ?? ''}').trim();
          cid = cid.isNotEmpty ? cid : ('${payload['clinicId'] ?? ''}').trim();
          sid = ('${payload['staffId'] ?? ''}').trim();
        }
      }

      if (role.isEmpty || uid.isEmpty) {
        throw Exception('context missing');
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _userId = uid;
        _clinicId = cid;
        _staffId = sid;
        _ctxLoading = false;
      });

      if (!_didSetInitialTab) {
        _didSetInitialTab = true;
      }

      await _loadClinicPolicy();
      await _loadUrgentNeeds();

      if (_isEmployee) {
        await _loadClosedMonthsForEmployee();
      }

      if (_isAttendanceUser && _attendancePremiumEnabled) {
        await _refreshAttendanceToday();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ctxErr = _friendlyAuthError(e);
        _ctxLoading = false;
      });
    }
  }

  // -------------------- URL helpers --------------------
  Uri _payrollUri(String path, {Map<String, String>? qs}) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$p');
    return (qs == null) ? uri : uri.replace(queryParameters: qs);
  }

  Future<http.Response> _tryGet(Uri uri,
      {required Map<String, String> headers}) async {
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> _tryPost(Uri uri,
      {required Map<String, String> headers, Object? body}) async {
    return http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));
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

  // -------------------- Policy fetch --------------------
  Future<void> _loadClinicPolicy() async {
    if (_ctxLoading) return;

    if (!mounted) return;
    setState(() {
      _policyLoading = true;
      _policyErr = '';
    });

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) {
        throw Exception('no token');
      }

      final headers = _authHeaders(token);
      final candidates = <String>[
        '/clinic-policy/me',
        '/api/clinic-policy/me',
      ];

      http.Response? last;

      for (final p in candidates) {
        final u = _payrollUri(p);
        final res = await _tryGet(u, headers: headers);
        last = res;

        if (res.statusCode == 404) continue;
        if (res.statusCode == 401) throw Exception('unauthorized');
        if (res.statusCode == 403) throw Exception('forbidden');

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          Map<String, dynamic> m = {};
          if (decoded is Map) m = Map<String, dynamic>.from(decoded);

          final policyAny = (m['policy'] is Map) ? m['policy'] : m;
          final pMap = (policyAny is Map)
              ? Map<String, dynamic>.from(policyAny)
              : <String, dynamic>{};

          _applyPolicyFromMap(pMap);

          if (!mounted) return;
          setState(() {
            _policyLoading = false;
            _policyErr = '';
          });
          return;
        }

        if (res.statusCode >= 400 && res.statusCode < 500) break;
      }

      if (!mounted) return;
      setState(() {
        _policyLoading = false;
        _policyErr = (last == null)
            ? 'เชื่อมต่อไม่สำเร็จ'
            : 'โหลดกติกาของคลินิกไม่สำเร็จ';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _policyLoading = false;
        _policyErr = _friendlyAuthError(e);
      });
    }
  }

  // -------------------- Urgent Needs fetch --------------------
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
        throw Exception('no token');
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      http.Response res;
      Uri u;

      if (_isHelper) {
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
        if (cid.isEmpty) {
          throw Exception('missing clinic');
        }

        u = _payrollUri('/shift-needs', qs: {'status': 'open', 'clinicId': cid});
        res = await _tryGet(u, headers: headers);

        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs',
              qs: {'status': 'open', 'clinicId': cid});
          res = await _tryGet(u, headers: headers);
        }

        if (res.statusCode == 404) {
          u = _payrollUri('/shift-needs/open');
          res = await _tryGet(u, headers: headers);
        }
        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs/open');
          res = await _tryGet(u, headers: headers);
        }
      } else {
        if (!mounted) return;
        setState(() {
          _urgentLoading = false;
          _urgentErr = '';
          _urgentCount = 0;
          _urgentFirst = null;
        });
        return;
      }

      if (res.statusCode != 200) {
        throw Exception('bad status ${res.statusCode}');
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
        _urgentErr = _friendlyAuthError(e);
        _urgentCount = 0;
        _urgentFirst = null;
      });
    }
  }

  Future<void> _activeRefreshUrgent() async {
    if (!mounted) return;

    if (_ctxLoading || _role.trim().isEmpty) {
      await _bootstrapContext();
    } else {
      await _loadClinicPolicy();
      await _loadUrgentNeeds();
      if (_isEmployee) {
        await _loadClosedMonthsForEmployee();
      }
      if (_isAttendanceUser && _attendancePremiumEnabled) {
        await _refreshAttendanceToday();
      }
    }

    if (!mounted) return;

    if (_ctxErr.isNotEmpty) {
      _snack(_ctxErr);
      return;
    }

    if (_urgentErr.isNotEmpty) {
      _snack(_urgentErr);
      return;
    }

    _snack('อัปเดตข้อมูลล่าสุดแล้ว');
  }

  // -------------------- Logout --------------------
  Future<void> _logout() async {
    _tapLog('LOGOUT');

    try {
      await AuthStorage.clearToken();
    } catch (_) {}
    try {
      await AppContextResolver.clear();
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.authGate,
      (_) => false,
    );
  }

  // -------------------- TrustScore gate --------------------
  Future<void> _openTrustScoreFromHome() async {
    _tapLog('OPEN_TRUSTSCORE');

    if (_ctxLoading) return;

    if (!_isClinic) {
      _snack('ฟีเจอร์นี้สำหรับคลินิกเท่านั้น');
      return;
    }

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
                if (ctx.mounted) setSt(() => loading = false);
              }
            }

            return AlertDialog(
              title: const Text('ยืนยันตัวตนคลินิก'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                        fontWeight: FontWeight.w700,
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

  // -------------------- Navigation: dashboards --------------------
  Future<void> _openMyClinic() async {
    _tapLog('OPEN_MY_CLINIC');

    if (_clinicId.trim().isEmpty || _userId.trim().isEmpty) {
      _snack('ไม่พบข้อมูลบัญชี กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicHomeScreen(
          clinicId: _clinicId.trim(),
          userId: _userId.trim(),
        ),
      ),
    );
  }

  Future<void> _openMyHelper() async {
    _tapLog('OPEN_MY_HELPER');

    if (_userId.trim().isEmpty) {
      _snack('ไม่พบข้อมูลบัญชี กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
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
    _tapLog('OPEN_CLINIC_MARKET');

    if (_ctxLoading) return;

    if (!_isClinic) {
      _snack('เมนูนี้สำหรับคลินิกเท่านั้น');
      return;
    }
    if (_clinicId.trim().isEmpty) {
      _snack('ไม่พบข้อมูลคลินิก กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
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
    _tapLog('OPEN_HELPER_OPEN_NEEDS');

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

  // ============================================================
  // ✅ Biometric (Fingerprint-only): error mapping
  // ============================================================
  String _bioUserMessageFromCode(String code) {
    final c = code.toLowerCase().trim();

    if (c.contains('notenrolled')) {
      return 'อุปกรณ์นี้ยังไม่มีลายนิ้วมือให้ใช้งาน (กรุณาตั้งค่าลายนิ้วมือในเครื่อง)';
    }
    if (c.contains('passcodenotset')) {
      return 'กรุณาตั้งรหัสล็อกหน้าจอก่อนใช้งาน';
    }
    if (c.contains('notavailable')) {
      return 'ระบบยืนยันตัวตนยังไม่พร้อมใช้งาน กรุณาลองใหม่';
    }
    if (c.contains('lockedout')) {
      return 'สแกนผิดหลายครั้ง ระบบล็อกชั่วคราว — ปลดล็อกด้วยรหัสหน้าจอก่อนแล้วลองใหม่';
    }
    if (c.contains('permanentlylockedout')) {
      return 'ระบบล็อกเพื่อความปลอดภัย — กรุณาปลดล็อกด้วยรหัสหน้าจอ/ตั้งค่าชีวมิติใหม่';
    }
    if (c.contains('usercanceled') || c.contains('usercancel')) {
      return 'ยกเลิกการยืนยันตัวตน';
    }
    if (c.contains('authentication_failed')) {
      return 'ยืนยันตัวตนไม่ผ่าน กรุณาลองใหม่';
    }
    if (c.contains('biometric_only_not_supported')) {
      return 'อุปกรณ์นี้ไม่รองรับโหมดชีวมิติอย่างเดียว';
    }

    return 'ยืนยันตัวตนไม่สำเร็จ (BIO ERROR: $code)';
  }

  Future<bool> _hasFingerprintAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;

      final canCheck = await _localAuth.canCheckBiometrics;
      final types = await _localAuth.getAvailableBiometrics();

      if (!canCheck && types.isEmpty) return false;

      if (types.contains(BiometricType.fingerprint)) return true;

      if (types.contains(BiometricType.face)) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _biometricAuthenticate() async {
    try {
      final okToTry = await _hasFingerprintAvailable();
      if (!okToTry) {
        _snack('อุปกรณ์นี้ไม่รองรับการยืนยันตัวตนด้วยลายนิ้วมือ');
        return false;
      }

      final ok = await _localAuth.authenticate(
        localizedReason: 'ยืนยันตัวตนด้วยลายนิ้วมือเพื่อบันทึกการทำงาน',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );

      if (!ok) {
        _snack('ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่');
      }

      return ok;
    } on PlatformException catch (e) {
      final msg = _bioUserMessageFromCode(e.code);
      _snack(msg);
      return false;
    } catch (_) {
      _snack('ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่');
      return false;
    }
  }

  // ============================================================
  // ✅ Attendance API helpers
  // ============================================================
  Map<String, String> _authHeaders(String token) => <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  bool _sameYmdFromAny(dynamic v, String ymd) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return false;
    if (s.length >= 10) {
      return s.substring(0, 10) == ymd;
    }
    return false;
  }

  void _deriveTodayStatusFromSessions(List<Map<String, dynamic>> sessions) {
    final today = _todayYmd();

    Map<String, dynamic>? todayOpen;
    Map<String, dynamic>? todayDone;

    for (final s in sessions) {
      final workDate = s['workDate'] ?? s['date'] ?? s['day'];
      final ci = s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime'];
      final co = s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime'];

      final isToday = _sameYmdFromAny(workDate, today) ||
          _sameYmdFromAny(ci, today) ||
          _sameYmdFromAny(co, today);

      if (!isToday) continue;

      final hasIn = (ci ?? '').toString().trim().isNotEmpty;
      final hasOut = (co ?? '').toString().trim().isNotEmpty;

      if (hasIn && hasOut) {
        todayDone = s;
      } else if (hasIn && !hasOut) {
        todayOpen = s;
      }
    }

    final checkedIn = todayOpen != null || todayDone != null;
    final checkedOut = todayDone != null;

    final line = checkedIn
        ? (checkedOut
            ? 'วันนี้เช็คอินและเช็คเอาท์แล้ว'
            : 'วันนี้เช็คอินแล้ว (ยังไม่เช็คเอาท์)')
        : 'วันนี้ยังไม่ได้เช็คอิน';

    if (!mounted) return;
    setState(() {
      _attStatusLine = line;
      _attCheckedIn = checkedIn;
      _attCheckedOut = checkedOut;
    });
  }

  Future<void> _refreshAttendanceToday() async {
    if (_ctxLoading) return;
    if (!_isAttendanceUser) return;
    if (!_attendancePremiumEnabled) return;
    if (_attLoading) return;

    if (!mounted) return;
    setState(() {
      _attLoading = true;
      _attErr = '';
      _attStatusLine = '';
      _attCheckedIn = false;
      _attCheckedOut = false;
    });

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) throw Exception('no token');

      final headers = _authHeaders(token);

      final previewCandidates = <String>[
        '/attendance/me-preview',
        '/api/attendance/me-preview',
      ];

      for (final p in previewCandidates) {
        try {
          final u = _payrollUri(p, qs: {'workDate': _todayYmd()});
          final res = await _tryGet(u, headers: headers);

          if (res.statusCode == 404) continue;
          if (res.statusCode == 401) throw Exception('no token');

          if (res.statusCode == 200) {
            final decoded = jsonDecode(res.body);
            Map<String, dynamic> m = {};
            if (decoded is Map) m = Map<String, dynamic>.from(decoded);

            final dataAny = (m['data'] is Map) ? m['data'] : m;
            final data = (dataAny is Map)
                ? Map<String, dynamic>.from(dataAny)
                : <String, dynamic>{};

            if (data['policy'] is Map) {
              _applyPolicyFromMap(Map<String, dynamic>.from(data['policy']));
            }

            final checkedIn = (data['checkedIn'] == true) ||
                (data['hasCheckIn'] == true) ||
                ((data['checkInAt'] ?? '').toString().trim().isNotEmpty);

            final checkedOut = (data['checkedOut'] == true) ||
                (data['hasCheckOut'] == true) ||
                ((data['checkOutAt'] ?? '').toString().trim().isNotEmpty);

            final msg = (data['message'] ?? '').toString().trim();
            final line = msg.isNotEmpty
                ? msg
                : checkedIn
                    ? (checkedOut
                        ? 'วันนี้เช็คอินและเช็คเอาท์แล้ว'
                        : 'วันนี้เช็คอินแล้ว (ยังไม่เช็คเอาท์)')
                    : 'วันนี้ยังไม่ได้เช็คอิน';

            if (!mounted) return;
            setState(() {
              _attLoading = false;
              _attErr = '';
              _attStatusLine = line;
              _attCheckedIn = checkedIn;
              _attCheckedOut = checkedOut;
            });
            return;
          }

          if (res.statusCode == 403) {
            if (!mounted) return;
            setState(() {
              _attLoading = false;
              _attErr = 'ไม่มีสิทธิ์ใช้งานเมนูนี้';
              _attStatusLine = '';
            });
            return;
          }

          if (res.statusCode >= 400 && res.statusCode < 500) break;
        } catch (_) {
          continue;
        }
      }

      final meCandidates = <String>[
        '/attendance/me',
        '/api/attendance/me',
      ];

      for (final p in meCandidates) {
        final u = _payrollUri(p);
        final r = await _tryGet(u, headers: headers);

        if (r.statusCode == 404) continue;
        if (r.statusCode == 401) throw Exception('no token');

        if (r.statusCode == 403) {
          if (!mounted) return;
          setState(() {
            _attLoading = false;
            _attErr = 'ไม่มีสิทธิ์ใช้งานเมนูนี้';
            _attStatusLine = '';
          });
          return;
        }

        if (r.statusCode != 200) break;

        final decoded = jsonDecode(r.body);

        List<Map<String, dynamic>> list = [];

        if (decoded is Map) {
          if (decoded['policy'] is Map) {
            _applyPolicyFromMap(Map<String, dynamic>.from(decoded['policy']));
          }

          final dataAny = decoded['data'];
          if (dataAny is List) {
            list = dataAny
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded['items'] is List) {
            list = (decoded['items'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded['results'] is List) {
            list = (decoded['results'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } else if (decoded is List) {
          list = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        if (!mounted) return;
        setState(() {
          _attLoading = false;
          _attErr = '';
        });
        _deriveTodayStatusFromSessions(list);
        return;
      }

      if (!mounted) return;
      setState(() {
        _attLoading = false;
        _attErr = 'เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่';
        _attStatusLine = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _attLoading = false;
        _attErr = _friendlyAuthError(e);
        _attStatusLine = '';
      });
    }
  }

  Future<_AttendanceSubmitResult> _postAttendanceCheckIn({
    required String token,
  }) async {
    final headers = _authHeaders(token);

    final body = jsonEncode({
      'workDate': _todayYmd(),
      'biometricVerified': true,
      'method': 'biometric',
      'deviceId': '',
      'clinicId': _clinicId.trim(),
      'staffId': _staffId.trim(),
    });

    final candidates = <String>[
      '/attendance/check-in',
      '/api/attendance/check-in',
    ];

    http.Response? lastRes;

    for (final p in candidates) {
      try {
        final u = _payrollUri(p);
        final res = await _tryPost(u, headers: headers, body: body);
        lastRes = res;

        if (res.statusCode == 200 || res.statusCode == 201) {
          return _AttendanceSubmitResult.success;
        }

        if (res.statusCode == 409) {
          _snack('คุณได้เช็คอินไว้แล้ว');
          return _AttendanceSubmitResult.alreadyDone;
        }

        if (res.statusCode == 404) continue;

        if (res.statusCode == 401) {
          _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
          return _AttendanceSubmitResult.unauthorized;
        }
        if (res.statusCode == 403) {
          _snack('ไม่มีสิทธิ์เช็คอิน');
          return _AttendanceSubmitResult.forbidden;
        }

        if (res.statusCode >= 400 && res.statusCode < 500) {
          _snack('บันทึกไม่สำเร็จ กรุณาลองใหม่');
          return _AttendanceSubmitResult.failed;
        }
      } catch (_) {
        continue;
      }
    }

    if (lastRes != null) {
      _snack('บันทึกไม่สำเร็จ กรุณาลองใหม่');
    } else {
      _snack('เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่');
    }
    return _AttendanceSubmitResult.failed;
  }

  Future<_AttendanceSubmitResult> _postAttendanceCheckOut({
    required String token,
  }) async {
    final headers = _authHeaders(token);

    final body = jsonEncode({
      'workDate': _todayYmd(),
      'biometricVerified': true,
      'method': 'biometric',
      'deviceId': '',
      'clinicId': _clinicId.trim(),
      'staffId': _staffId.trim(),
    });

    final directCandidates = <String>[
      '/attendance/check-out',
      '/api/attendance/check-out',
    ];

    http.Response? lastRes;
    bool shouldTryIdFallback = false;

    for (final p in directCandidates) {
      try {
        final u = _payrollUri(p);
        final res = await _tryPost(u, headers: headers, body: body);
        lastRes = res;

        if (res.statusCode == 200 || res.statusCode == 201) {
          return _AttendanceSubmitResult.success;
        }

        if (res.statusCode == 409) {
          _snack('คุณได้เช็คเอาท์ไว้แล้ว');
          return _AttendanceSubmitResult.alreadyDone;
        }

        if (res.statusCode == 404) {
          shouldTryIdFallback = true;
          continue;
        }

        if (res.statusCode == 401) {
          _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
          return _AttendanceSubmitResult.unauthorized;
        }
        if (res.statusCode == 403) {
          _snack('ไม่มีสิทธิ์เช็คเอาท์');
          return _AttendanceSubmitResult.forbidden;
        }

        if (res.statusCode >= 400 && res.statusCode < 500) {
          _snack('บันทึกไม่สำเร็จ กรุณาลองใหม่');
          return _AttendanceSubmitResult.failed;
        }
      } catch (_) {
        continue;
      }
    }

    if (shouldTryIdFallback) {
      try {
        final meCandidates = <String>[
          '/attendance/me',
          '/api/attendance/me',
        ];

        for (final p in meCandidates) {
          final u = _payrollUri(p);
          final r = await _tryGet(u, headers: headers);

          if (r.statusCode == 404) continue;

          if (r.statusCode == 401) {
            _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
            return _AttendanceSubmitResult.unauthorized;
          }

          if (r.statusCode == 403) {
            _snack('ไม่มีสิทธิ์เช็คเอาท์');
            return _AttendanceSubmitResult.forbidden;
          }

          if (r.statusCode != 200) break;

          final decoded = jsonDecode(r.body);
          List<Map<String, dynamic>> list = [];

          if (decoded is Map) {
            final dataAny = decoded['data'];
            if (dataAny is List) {
              list = dataAny
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            } else if (decoded['items'] is List) {
              list = (decoded['items'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
          } else if (decoded is List) {
            list = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }

          Map<String, dynamic>? open;
          for (final s in list) {
            final hasOut = (s['checkOutAt'] ?? s['checkoutAt'] ?? '')
                .toString()
                .trim()
                .isNotEmpty;
            if (!hasOut) {
              open = s;
              break;
            }
          }
          open ??= list.isNotEmpty ? list.first : null;

          final id = (open?['_id'] ?? open?['id'] ?? '').toString().trim();
          if (id.isEmpty) {
            _snack('ไม่พบรายการเช็คอินที่เปิดอยู่');
            return _AttendanceSubmitResult.failed;
          }

          final idCandidates = <String>[
            '/attendance/$id/check-out',
            '/api/attendance/$id/check-out',
          ];

          for (final p2 in idCandidates) {
            final u2 = _payrollUri(p2);
            final r2 = await _tryPost(u2, headers: headers, body: body);
            lastRes = r2;

            if (r2.statusCode == 200 || r2.statusCode == 201) {
              return _AttendanceSubmitResult.success;
            }

            if (r2.statusCode == 409) {
              _snack('คุณได้เช็คเอาท์ไว้แล้ว');
              return _AttendanceSubmitResult.alreadyDone;
            }

            if (r2.statusCode == 401) {
              _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
              return _AttendanceSubmitResult.unauthorized;
            }
            if (r2.statusCode == 403) {
              _snack('ไม่มีสิทธิ์เช็คเอาท์');
              return _AttendanceSubmitResult.forbidden;
            }
            if (r2.statusCode == 404) continue;
          }

          break;
        }
      } catch (_) {}
    }

    if (lastRes != null) {
      _snack('บันทึกไม่สำเร็จ กรุณาลองใหม่');
    } else {
      _snack('เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่');
    }
    return _AttendanceSubmitResult.failed;
  }

  Future<void> _scanAndCheckIn() async {
    _tapLog('SCAN_CHECKIN');

    if (_ctxLoading) return;

    if (!_isAttendanceUser) {
      _snack('เมนูนี้สำหรับพนักงาน/ผู้ช่วยเท่านั้น');
      return;
    }

    if (!_attendancePremiumEnabled) {
      _snack('ฟีเจอร์นี้เป็น Premium');
      return;
    }

    if (_attCheckedIn && !_attCheckedOut) {
      _snack('วันนี้คุณเช็คอินแล้ว');
      return;
    }

    if (_attCheckedIn && _attCheckedOut) {
      _snack('วันนี้เช็คอิน/เช็คเอาท์ครบแล้ว');
      return;
    }

    if (_bioLoading || _attPosting) return;

    setState(() {
      _bioLoading = true;
      _attPosting = true;
    });

    try {
      final okBio = await _biometricAuthenticate();
      if (!okBio) return;

      final token = await _getTokenAny();
      if (token == null || token.isEmpty) {
        _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
        return;
      }

      final result = await _postAttendanceCheckIn(token: token);

      if (result == _AttendanceSubmitResult.success) {
        _snack('บันทึกสำเร็จ');
        await _refreshAttendanceToday();
      } else if (result == _AttendanceSubmitResult.alreadyDone) {
        await _refreshAttendanceToday();
      }
    } finally {
      if (mounted) {
        setState(() {
          _bioLoading = false;
          _attPosting = false;
        });
      }
    }
  }

  Future<void> _scanAndCheckOut() async {
    _tapLog('SCAN_CHECKOUT');

    if (_ctxLoading) return;

    if (!_isAttendanceUser) {
      _snack('เมนูนี้สำหรับพนักงาน/ผู้ช่วยเท่านั้น');
      return;
    }

    if (!_attendancePremiumEnabled) {
      _snack('ฟีเจอร์นี้เป็น Premium');
      return;
    }

    if (!_attCheckedIn) {
      _snack('วันนี้ยังไม่ได้เช็คอิน');
      return;
    }

    if (_attCheckedOut) {
      _snack('วันนี้คุณเช็คเอาท์แล้ว');
      return;
    }

    if (_bioLoading || _attPosting) return;

    setState(() {
      _bioLoading = true;
      _attPosting = true;
    });

    try {
      final okBio = await _biometricAuthenticate();
      if (!okBio) return;

      final token = await _getTokenAny();
      if (token == null || token.isEmpty) {
        _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
        return;
      }

      final result = await _postAttendanceCheckOut(token: token);

      if (result == _AttendanceSubmitResult.success) {
        _snack('บันทึกสำเร็จ');
        await _refreshAttendanceToday();
      } else if (result == _AttendanceSubmitResult.alreadyDone) {
        await _refreshAttendanceToday();
      }
    } finally {
      if (mounted) {
        setState(() {
          _bioLoading = false;
          _attPosting = false;
        });
      }
    }
  }

  Future<void> _openAttendanceHistory() async {
    _tapLog('OPEN_ATTENDANCE_HISTORY');

    if (_ctxLoading) return;
    if (!_isAttendanceUser) {
      _snack('เมนูนี้สำหรับพนักงาน/ผู้ช่วยเท่านั้น');
      return;
    }
    if (!_attendancePremiumEnabled) {
      _snack('ฟีเจอร์นี้เป็น Premium');
      return;
    }

    final token = await _getTokenAny();
    if (token == null || token.isEmpty) {
      _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceHistoryScreen(
          token: token,
          role: _role,
          clinicId: _clinicId,
          staffId: _staffId,
        ),
      ),
    );

    if (_attendancePremiumEnabled && _isAttendanceUser) {
      await _refreshAttendanceToday();
    }
  }

  // -------------------- Employee: Payslip --------------------
  Future<void> _loadClosedMonthsForEmployee() async {
    if (_ctxLoading) return;

    if (!mounted) return;
    setState(() {
      _payslipLoading = true;
      _payslipErr = '';
      _closedMonths = [];
    });

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) throw Exception('no token');

      final staffId = _staffId.trim();
      if (staffId.isEmpty) throw Exception('missing staffId');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      Uri u = _payrollUri('/payroll-close/close-months/$staffId');
      http.Response res = await _tryGet(u, headers: headers);

      if (res.statusCode == 404) {
        u = _payrollUri('/api/payroll-close/close-months/$staffId');
        res = await _tryGet(u, headers: headers);
      }

      if (res.statusCode != 200) {
        throw Exception('bad status ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      final rowsAny = (decoded is Map) ? decoded['rows'] : null;
      final rows = (rowsAny is List) ? rowsAny : const [];

      final list = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() {
        _payslipLoading = false;
        _payslipErr = '';
        _closedMonths = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _payslipLoading = false;
        _payslipErr = _friendlyAuthError(e);
        _closedMonths = [];
      });
    }
  }

  Future<void> _openPayslipMonth(String month) async {
    _tapLog('OPEN_PAYSLIP_MONTH $month');

    final token = await _getTokenAny();
    if (token == null || token.isEmpty) {
      _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
      return;
    }
    final staffId = _staffId.trim();
    if (staffId.isEmpty) {
      _snack('ไม่พบข้อมูลพนักงาน กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PayslipMonthDetailScreen(
          token: token,
          staffId: staffId,
          month: month,
        ),
      ),
    );

    await _loadClosedMonthsForEmployee();
  }

  // -------------------- UI: urgent card --------------------
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

    final title = (_isClinic) ? 'ประกาศงานของคลินิก' : 'งานด่วนสำหรับผู้ช่วย';

    if (_urgentLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: const [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'กำลังอัปเดต...',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
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
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
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
                      onPressed: _isHelper
                          ? _openHelperOpenNeeds
                          : _openClinicNeedsMarket,
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
                  _isClinic ? 'ตอนนี้ยังไม่มีประกาศงาน' : 'ตอนนี้ยังไม่มีงานด่วน',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed:
                    _isHelper ? _openHelperOpenNeeds : _openClinicNeedsMarket,
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
                    _isClinic
                        ? 'ประกาศงานที่เปิดอยู่: $_urgentCount งาน'
                        : 'งานด่วนที่เปิดอยู่: $_urgentCount งาน',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900),
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
                onPressed:
                    _isHelper ? _openHelperOpenNeeds : _openClinicNeedsMarket,
                child: const Text('ดูทั้งหมด'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- Policy card --------------------
  Widget _policyCard() {
    if (!_isAttendanceUser) return const SizedBox.shrink();
    if (!_policyHumanReadableEnabled) return const SizedBox.shrink();

    if (_policyLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: const [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'กำลังโหลดกติกาของคลินิก...',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_policyErr.isNotEmpty && _policyLines.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'กติกาการทำงานของคลินิก',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                _policyErr,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _loadClinicPolicy,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
      );
    }

    if (_policyLines.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'กติกาการทำงานของคลินิก',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              _isHelper
                  ? 'สรุปกติกาที่เกี่ยวข้องกับผู้ช่วย'
                  : 'สรุปกติกาที่เกี่ยวข้องกับการลงเวลาและ OT',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            ..._policyLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle_outline, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- Attendance UI --------------------
  Widget _attendancePremiumGateCard({bool compact = false}) {
    if (!_isAttendanceUser) return const SizedBox.shrink();

    if (_premiumLoading || _policyLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: const [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'กำลังตรวจสอบสิทธิ์ Premium...',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_attendancePremiumEnabled) return const SizedBox.shrink();

    final title = compact
        ? 'Premium Attendance'
        : 'Premium: บันทึกเวลางานด้วยลายนิ้วมือ';

    final subtitle = _isHelper
        ? 'ผู้ช่วยสามารถเช็คอิน/เช็คเอาท์ด้วยลายนิ้วมือ เพื่อให้ระบบคำนวณชั่วโมงงานจริงได้แม่นยำขึ้น'
        : 'เช็คอิน/เช็คเอาท์ด้วยลายนิ้วมือ เพื่อให้ระบบคำนวณชั่วโมงงานและ OT ให้อัตโนมัติ';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  _tapLog('UPGRADE_PREMIUM_DIALOG');
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('เปิดใช้งาน Premium'),
                      content: const Text(
                          'ตอนนี้ยังเป็นโหมดทดสอบ (ยังไม่ผูกชำระเงินจริง)\nต้องการเปิด Premium Attendance ไหม?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('ยกเลิก')),
                        ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('เปิดใช้งาน')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await _setPremiumAttendanceEnabled(true);
                    _snack('เปิดใช้งาน Premium แล้ว');
                  }
                },
                child: const Text('อัปเกรด Premium 299'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attendanceActionCard({String? header}) {
    if (!_isAttendanceUser) return const SizedBox.shrink();
    if (!_attendancePremiumEnabled) return const SizedBox.shrink();

    final title = header ??
        (_isHelper ? 'บันทึกการทำงานวันนี้ (ผู้ช่วย)' : 'บันทึกการทำงานวันนี้');

    final canCheckIn = !_bioLoading &&
        !_attLoading &&
        !_attPosting &&
        (!_attCheckedIn || (_attCheckedIn && _attCheckedOut));
    final canCheckOut = !_bioLoading &&
        !_attLoading &&
        !_attPosting &&
        (_attCheckedIn && !_attCheckedOut);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              'ยืนยันตัวตนด้วยลายนิ้วมือ แล้วกดเช็คอิน/เช็คเอาท์',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),

            if (_attErr.isNotEmpty) ...[
              Text(
                _attErr,
                style: const TextStyle(fontSize: 12, color: Colors.red),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
            ] else if (_attLoading || _attPosting) ...[
              Row(
                children: const [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'กำลังอัปเดตสถานะวันนี้...',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ] else if (_attStatusLine.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade100,
                ),
                child: Text(
                  _attStatusLine,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canCheckIn ? _scanAndCheckIn : null,
                    icon: _bioLoading || _attPosting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('เช็คอิน'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canCheckOut ? _scanAndCheckOut : null,
                    icon: const Icon(Icons.logout),
                    label: const Text('เช็คเอาท์'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: _attLoading || _attPosting
                        ? null
                        : _refreshAttendanceToday,
                    icon: const Icon(Icons.refresh),
                    label: const Text('รีเฟรชสถานะวันนี้'),
                  ),
                ),
                TextButton.icon(
                  onPressed: _openAttendanceHistory,
                  icon: const Icon(Icons.history),
                  label: const Text('ดูย้อนหลัง'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _employeePayslipCard() {
    if (!_isEmployee) return const SizedBox.shrink();

    if (_payslipLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: const [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'กำลังโหลดสลิป...',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_payslipErr.isNotEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('สลิปเงินเดือน',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                _payslipErr,
                style: const TextStyle(fontSize: 12, color: Colors.red),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loadClosedMonthsForEmployee,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองใหม่'),
                ),
              )
            ],
          ),
        ),
      );
    }

    final months = _closedMonths
        .map((e) => (e['month'] ?? '').toString().trim())
        .where((m) => m.isNotEmpty)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('สลิปเงินเดือน',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              months.isEmpty ? 'ยังไม่มีงวดที่ปิด' : 'เลือกงวดที่ต้องการดูสลิป',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            if (months.isEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loadClosedMonthsForEmployee,
                  icon: const Icon(Icons.refresh),
                  label: const Text('รีเฟรช'),
                ),
              )
            else
              Column(
                children: months.take(6).map((m) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text('งวด $m'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openPayslipMonth(m),
                  );
                }).toList(),
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
        title: 'ไม่พร้อมใช้งาน',
        message: _ctxErr,
        onRetry: _bootstrapContext,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (_isAttendanceUser) ...[
          _attendancePremiumGateCard(),
          if (!_attendancePremiumEnabled) const SizedBox(height: 10),
        ],
        if (_isAttendanceUser) ...[
          _attendanceActionCard(
              header: _isHelper ? 'บันทึกการทำงาน (ผู้ช่วย)' : 'บันทึกการทำงาน'),
          if (_attendancePremiumEnabled) const SizedBox(height: 10),
        ],
        if (_isAttendanceUser) ...[
          _policyCard(),
          if (_policyLines.isNotEmpty) const SizedBox(height: 10),
        ],
        if (_isEmployee) ...[
          _employeePayslipCard(),
          const SizedBox(height: 10),
        ],
        _urgentCardCompact(),
        const SizedBox(height: 10),
        if (_isClinic)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TrustScore ผู้ช่วย',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'กดเพื่อดูคะแนนผู้ช่วย — ต้องยืนยัน PIN คลินิกก่อน',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
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
        if (_isClinic || _isHelper) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ตลาดงาน',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.local_hospital_outlined),
                    title: const Text('ฝั่งคลินิก'),
                    subtitle: const Text('ดูประกาศงานและจัดการงานของคลินิก'),
                    onTap: _openClinicNeedsMarket,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('ฝั่งผู้ช่วย'),
                    subtitle: const Text('ดูงานว่างและสมัครงาน'),
                    onTap: _openHelperOpenNeeds,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _myTab() {
    if (_ctxLoading) return const Center(child: CircularProgressIndicator());

    if (_ctxErr.isNotEmpty) {
      return _errorBox(
        title: 'ไม่พร้อมใช้งาน',
        message: _ctxErr,
        onRetry: _bootstrapContext,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'เมนูของฉัน',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
            ),
          ),
        ),

        if (_isAttendanceUser) ...[
          _attendancePremiumGateCard(compact: true),
          if (_attendancePremiumEnabled) _attendanceActionCard(),
          const SizedBox(height: 10),

          if (_attendancePremiumEnabled)
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('ประวัติการเช็คอินย้อนหลัง'),
                    subtitle: const Text('ดูรายการย้อนหลัง 7/30/90 วัน พร้อมรายละเอียด'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openAttendanceHistory,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
        ],

        if (_isAttendanceUser) ...[
          _policyCard(),
          if (_policyLines.isNotEmpty) const SizedBox(height: 10),
        ],

        if (_isClinic)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: const Text('My Clinic'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openMyClinic,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('TrustScore'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openTrustScoreFromHome,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Payroll (Local)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    _tapLog('OPEN_LOCAL_PAYROLL');
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LocalPayrollScreen()),
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
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openMyHelper,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.work_outline),
                  title: const Text('งานว่าง (ตลาดงาน)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openHelperOpenNeeds,
                ),
              ],
            ),
          ),

        if (_isEmployee)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('สลิปเงินเดือน'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    _tapLog('MY_EMP_PAYSLIP');
                    await _loadClosedMonthsForEmployee();
                    if (!mounted) return;

                    final months = _closedMonths
                        .map((e) => (e['month'] ?? '').toString().trim())
                        .where((m) => m.isNotEmpty)
                        .toList();

                    if (months.isEmpty) {
                      _snack('ยังไม่มีงวดที่ปิด');
                      return;
                    }

                    final picked = await showModalBottomSheet<String>(
                      context: context,
                      showDragHandle: true,
                      builder: (ctx) {
                        return SafeArea(
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              const ListTile(
                                title: Text(
                                  'เลือกงวดที่ต้องการดู',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                              ...months.map((m) {
                                return ListTile(
                                  leading: const Icon(Icons.receipt_long),
                                  title: Text('งวด $m'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.pop(ctx, m),
                                );
                              }),
                              const SizedBox(height: 12),
                            ],
                          ),
                        );
                      },
                    );

                    if (picked != null && picked.isNotEmpty) {
                      await _openPayslipMonth(picked);
                    }
                  },
                ),
              ],
            ),
          ),

        if (_isAttendanceUser && !_hasBackendPolicy) ...[
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Premium Attendance (ทดสอบ)'),
              subtitle: const Text('เปิด/ปิดฟีเจอร์สแกนลายนิ้วมือแบบ Premium'),
              value: _premiumAttendanceEnabled,
              onChanged: (v) async => _setPremiumAttendanceEnabled(v),
            ),
          ),
        ],

        const SizedBox(height: 8),
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

  Widget _errorBox({
    required String title,
    required String message,
    required VoidCallback onRetry,
  }) {
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

  void _setTab(int i) {
    _tapLog('BOTTOM_NAV_TAP -> $i');
    if (i == _tab) return;
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _homeTab(),
      _myTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic Smart Staff'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _tapLog('APPBAR_REFRESH');
              _bootstrapContext();
            },
          ),
          IconButton(
            tooltip: 'อัปเดตล่าสุด',
            icon: const Icon(Icons.flash_on),
            onPressed: _activeRefreshUrgent,
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: IndexedStack(
          index: _tab,
          children: pages,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: _setTab,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'My'),
        ],
      ),
    );
  }
}

/// ============================================================
/// ✅ NEW: Attendance History Screen (ย้อนหลัง 7/30/90 วัน + เลือกเอง)
/// ============================================================
class AttendanceHistoryScreen extends StatefulWidget {
  final String token;
  final String role;
  final String clinicId;
  final String staffId;

  const AttendanceHistoryScreen({
    super.key,
    required this.token,
    required this.role,
    required this.clinicId,
    required this.staffId,
  });

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  bool _loading = true;
  String _err = '';
  List<Map<String, dynamic>> _all = [];

  int _quickDays = 30;
  DateTime? _from;
  DateTime? _to;

  Uri _payrollUri(String path) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Map<String, String> _headers() => <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  DateTime? _parseDateAny(dynamic v) {
    if (v == null) return null;

    final s = v.toString().trim();
    if (s.isEmpty) return null;

    final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (dateOnly.hasMatch(s)) {
      final parts = s.split('-');
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || m == null || d == null) return null;
      return DateTime(y, m, d);
    }

    try {
      final dt = DateTime.parse(s);

      final hasUtcZ = s.toUpperCase().endsWith('Z');
      final hasTzOffset = RegExp(r'([+-]\d{2}:\d{2})$').hasMatch(s);

      if (hasUtcZ || hasTzOffset || dt.isUtc) {
        return dt.toLocal();
      }
      return dt;
    } catch (_) {
      if (s.length >= 10) {
        final head = s.substring(0, 10);
        if (dateOnly.hasMatch(head)) {
          final parts = head.split('-');
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y == null || m == null || d == null) return null;
          return DateTime(y, m, d);
        }
      }
      return null;
    }
  }

  String _fmtHM(dynamic v) {
    final dt = _parseDateAny(v);
    if (dt == null) return '-';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  double _calcHours(Map<String, dynamic> s) {
    final ci =
        _parseDateAny(s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime']);
    final co =
        _parseDateAny(s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime']);
    if (ci == null || co == null) return 0;
    final diff = co.difference(ci).inMinutes;
    if (diff <= 0) return 0;
    return diff / 60.0;
  }

  String _workDateText(Map<String, dynamic> s) {
    final workDate = s['workDate'] ?? s['date'] ?? s['day'];
    final d = _parseDateAny(workDate) ??
        _parseDateAny(s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime']) ??
        _parseDateAny(s['createdAt']);
    if (d == null) return '-';
    return _ymd(d);
  }

  DateTimeRange _effectiveRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _quickDays - 1));
    return DateTimeRange(start: start, end: end);
  }

  DateTimeRange _rangeOrQuick() {
    if (_from == null && _to == null) return _effectiveRange();
    final now = DateTime.now();
    final from =
        _from ?? DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
    final to = _to ?? now;
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
    return DateTimeRange(start: start, end: end);
  }

  bool _isInRange(Map<String, dynamic> s, DateTimeRange r) {
    final d = _parseDateAny(s['workDate'] ?? s['date'] ?? s['day']) ??
        _parseDateAny(s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime']) ??
        _parseDateAny(s['createdAt']);
    if (d == null) return false;
    return !d.isBefore(r.start) && !d.isAfter(r.end);
  }

  List<Map<String, dynamic>> _filtered() {
    final r = _rangeOrQuick();
    final list = _all.where((s) => _isInRange(s, r)).toList();

    list.sort((a, b) {
      final da = _parseDateAny(a['workDate'] ?? a['date'] ?? a['day']) ??
          _parseDateAny(a['checkInAt'] ?? a['checkinAt'] ?? a['checkInTime']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db = _parseDateAny(b['workDate'] ?? b['date'] ?? b['day']) ??
          _parseDateAny(b['checkInAt'] ?? b['checkinAt'] ?? b['checkInTime']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<http.Response> _tryGet(Uri uri) async {
    return http.get(uri, headers: _headers()).timeout(const Duration(seconds: 15));
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _err = '';
      _all = [];
    });

    try {
      final candidates = <String>[
        '/attendance/me',
        '/api/attendance/me',
      ];

      http.Response? last;

      for (final p in candidates) {
        final u = _payrollUri(p);
        final res = await _tryGet(u);
        last = res;

        if (res.statusCode == 404) continue;
        if (res.statusCode == 401) throw Exception('no token');
        if (res.statusCode == 403) throw Exception('forbidden');
        if (res.statusCode != 200) break;

        final decoded = jsonDecode(res.body);

        List<Map<String, dynamic>> list = [];

        if (decoded is Map) {
          final dataAny = decoded['data'];
          if (dataAny is List) {
            list = dataAny
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded['items'] is List) {
            list = (decoded['items'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else if (decoded['results'] is List) {
            list = (decoded['results'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } else if (decoded is List) {
          list = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        if (!mounted) return;
        setState(() {
          _loading = false;
          _err = '';
          _all = list;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = (last == null)
            ? 'เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่'
            : 'โหลดข้อมูลไม่สำเร็จ กรุณาลองใหม่';
        _all = [];
      });
    } catch (e) {
      if (!mounted) return;
      final s = e.toString().toLowerCase();
      setState(() {
        _loading = false;
        _err = s.contains('forbidden')
            ? 'ไม่มีสิทธิ์ใช้งานเมนูนี้'
            : 'เซสชันหมดอายุ/โหลดข้อมูลไม่สำเร็จ กรุณาเข้าสู่ระบบใหม่';
        _all = [];
      });
    }
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final initial = _from ?? now.subtract(Duration(days: _quickDays));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _from = picked;
      _to = _to;
    });
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final initial = _to ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _to = picked;
      _from = _from;
    });
  }

  void _setQuick(int days) {
    setState(() {
      _quickDays = days;
      _from = null;
      _to = null;
    });
  }

  Widget _chip(String label, bool on, VoidCallback tap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        onSelected: (_) => tap(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _rangeOrQuick();
    final list = _filtered();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติการเช็คอินย้อนหลัง'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('ไม่พร้อมใช้งาน',
                                style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            Text(_err,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade700)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('ลองใหม่'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ช่วงเวลา',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _chip(
                                      '7 วัน',
                                      _from == null && _to == null && _quickDays == 7,
                                      () => _setQuick(7),
                                    ),
                                    _chip(
                                      '30 วัน',
                                      _from == null && _to == null && _quickDays == 30,
                                      () => _setQuick(30),
                                    ),
                                    _chip(
                                      '90 วัน',
                                      _from == null && _to == null && _quickDays == 90,
                                      () => _setQuick(90),
                                    ),
                                    _chip('เลือกเอง', _from != null || _to != null,
                                        () {
                                      if (_from == null && _to == null) {
                                        setState(() {
                                          _from = DateTime.now()
                                              .subtract(const Duration(days: 29));
                                          _to = DateTime.now();
                                        });
                                      }
                                    }),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        if (_from == null && _to == null) {
                                          setState(() {
                                            _from = DateTime.now()
                                                .subtract(const Duration(days: 29));
                                            _to = DateTime.now();
                                          });
                                        }
                                        await _pickFrom();
                                      },
                                      icon: const Icon(Icons.date_range),
                                      label: Text(
                                        'เริ่ม: ${_from == null ? _ymd(r.start) : _ymd(_from!)}',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        if (_from == null && _to == null) {
                                          setState(() {
                                            _from = DateTime.now()
                                                .subtract(const Duration(days: 29));
                                            _to = DateTime.now();
                                          });
                                        }
                                        await _pickTo();
                                      },
                                      icon: const Icon(Icons.event),
                                      label: Text(
                                        'ถึง: ${_to == null ? _ymd(r.end) : _ymd(_to!)}',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'แสดง: ${_ymd(r.start)} ถึง ${_ymd(r.end)} • ทั้งหมด ${list.length} รายการ',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? Center(
                              child: Text(
                                'ไม่พบรายการในช่วงเวลานี้',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final s = list[i];

                                final dateText = _workDateText(s);
                                final ci = _fmtHM(
                                  s['checkInAt'] ??
                                      s['checkinAt'] ??
                                      s['checkInTime'],
                                );
                                final co = _fmtHM(
                                  s['checkOutAt'] ??
                                      s['checkoutAt'] ??
                                      s['checkOutTime'],
                                );

                                final hasOut = (s['checkOutAt'] ??
                                        s['checkoutAt'] ??
                                        s['checkOutTime'] ??
                                        '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty;

                                final hours = _calcHours(s);
                                final hoursText = hasOut && hours > 0
                                    ? '${hours.toStringAsFixed(2)} ชม.'
                                    : 'ยังไม่เช็คเอาท์';

                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      child: Text(
                                        dateText.length >= 10
                                            ? dateText.substring(8, 10)
                                            : '--',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                    title: Text(
                                      dateText,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900),
                                    ),
                                    subtitle: Text('เข้า $ci • ออก $co'),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          hoursText,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          hasOut ? 'เสร็จสิ้น' : 'กำลังทำงาน',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: hasOut
                                                ? Colors.green.shade700
                                                : Colors.orange.shade700,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () async {
                                      await showModalBottomSheet(
                                        context: context,
                                        showDragHandle: true,
                                        builder: (ctx) {
                                          return SafeArea(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(14),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'รายละเอียด $dateText',
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w900),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  _kv('เวลาเช็คอิน', ci),
                                                  _kv('เวลาเช็คเอาท์', co),
                                                  _kv(
                                                    'ชั่วโมงรวม',
                                                    hasOut
                                                        ? (hours > 0
                                                            ? '${hours.toStringAsFixed(2)} ชั่วโมง'
                                                            : '-')
                                                        : 'ยังไม่เช็คเอาท์',
                                                  ),
                                                  const SizedBox(height: 10),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: OutlinedButton.icon(
                                                      onPressed: () =>
                                                          Navigator.pop(ctx),
                                                      icon: const Icon(
                                                          Icons.close),
                                                      label:
                                                          const Text('ปิด'),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            v,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// ✅ Payslip Month Detail (simple, clean, show OT snapshot too)
/// ============================================================
class _PayslipMonthDetailScreen extends StatefulWidget {
  final String token;
  final String staffId;
  final String month;

  const _PayslipMonthDetailScreen({
    required this.token,
    required this.staffId,
    required this.month,
  });

  @override
  State<_PayslipMonthDetailScreen> createState() =>
      _PayslipMonthDetailScreenState();
}

class _PayslipMonthDetailScreenState extends State<_PayslipMonthDetailScreen> {
  bool _loading = true;
  String _err = '';
  Map<String, dynamic>? _row;

  Uri _payrollUri(String path) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  String _fmtMoney(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    return n.toStringAsFixed(0);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<http.Response> _tryGet(Uri uri,
      {required Map<String, String> headers}) async {
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = '';
      _row = null;
    });

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

      Uri u = _payrollUri(
          '/payroll-close/close-month/${widget.staffId}/${widget.month}');
      http.Response res = await _tryGet(u, headers: headers);

      if (res.statusCode == 404) {
        u = _payrollUri(
            '/api/payroll-close/close-month/${widget.staffId}/${widget.month}');
        res = await _tryGet(u, headers: headers);
      }

      if (res.statusCode != 200) {
        throw Exception('bad status ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      final rowAny = (decoded is Map) ? decoded['row'] : null;
      if (rowAny is! Map) {
        throw Exception('invalid data');
      }

      setState(() {
        _loading = false;
        _err = '';
        _row = Map<String, dynamic>.from(rowAny);
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _err = 'ไม่สามารถโหลดข้อมูลได้ กรุณาลองใหม่';
        _row = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _row;

    return Scaffold(
      appBar: AppBar(
        title: Text('สลิปงวด ${widget.month}'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('ไม่พร้อมใช้งาน',
                                style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            Text(_err,
                                style: TextStyle(color: Colors.grey.shade700)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('ลองใหม่'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('สรุป',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            _kv('รายรับรวม', '฿${_fmtMoney(r?['grossMonthly'])}'),
                            _kv('ภาษีหัก ณ ที่จ่าย',
                                '฿${_fmtMoney(r?['withheldTaxMonthly'])}'),
                            _kv('ประกันสังคม',
                                '฿${_fmtMoney(r?['ssoEmployeeMonthly'])}'),
                            _kv('กองทุนสำรองเลี้ยงชีพ',
                                '฿${_fmtMoney(r?['pvdEmployeeMonthly'])}'),
                            const Divider(height: 16),
                            _kv('รับสุทธิ', '฿${_fmtMoney(r?['netPay'])}',
                                bold: true),
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
                            const Text('รายละเอียด OT',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            _kv('OT ที่รวมในงวดนี้', '฿${_fmtMoney(r?['otPay'])}'),
                            _kv('รวมเวลาที่อนุมัติ (นาที)',
                                '${(r?['otApprovedMinutes'] ?? 0)}'),
                            _kv('ชั่วโมงถ่วงน้ำหนัก',
                                '${(r?['otApprovedWeightedHours'] ?? 0)}'),
                            _kv('จำนวนรายการ',
                                '${(r?['otApprovedCount'] ?? 0)}'),
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
                            const Text('องค์ประกอบรายได้',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            _kv('เงินเดือน/ฐาน', '฿${_fmtMoney(r?['grossBase'])}'),
                            _kv('โบนัส', '฿${_fmtMoney(r?['bonus'])}'),
                            _kv('เงินเพิ่มอื่นๆ',
                                '฿${_fmtMoney(r?['otherAllowance'])}'),
                            _kv('หักอื่นๆ', '฿${_fmtMoney(r?['otherDeduction'])}'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            v,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            ),
          ),
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

  bool _isParttime(EmployeeModel e) =>
      e.employmentType.toLowerCase().trim() == 'parttime';

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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ลบ')),
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
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const AddEmployeeScreen()));
    await _refreshData();
  }

  Future<void> _openPayslipPreview(EmployeeModel emp) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PayslipPreviewScreen(emp: emp)),
    );
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
                        margin: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(emp.fullName),
                          subtitle: Text(_subtitle(emp)),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EmployeeDetailScreen(
                                  clinicId: '',
                                  employee: emp,
                                ),
                              ),
                            );
                            await _refreshData();
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'ดู/พิมพ์สลิป (PDF)',
                                icon: const Icon(Icons.picture_as_pdf,
                                    color: Colors.red),
                                onPressed: () => _openPayslipPreview(emp),
                              ),
                              IconButton(
                                tooltip: 'ลบพนักงาน',
                                icon:
                                    const Icon(Icons.delete, color: Colors.grey),
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