// lib/screens/home/home_screen.dart
//
// ✅ CLEAN HOME (REFACTORED)
// - แยก UI ออกไป tabs / widgets / attendance
// - HomeScreen เหลือเป็น controller/state หลัก
// - รักษา flow เดิมไว้
// - รวม fix attendance check-out state แล้ว
//
// ✅ PATCH (PRODUCTION HARDENED)
// - กันกด check-in / check-out ซ้ำตั้งแต่ต้นฟังก์ชัน
// - ลดโอกาสปุ่มนิ่งจาก loading state
// - ยังคง immediate UI update + refresh backend ตามเดิม
//
// ✅ PATCH (NEW)
// - ไม่ส่ง clinicId / staffId / deviceId แบบค่าว่างไป backend
// - แยก state ระหว่าง "กำลังสแกน" กับ "กำลังส่งข้อมูล"
// - เพิ่ม print สำหรับ attendance ทุกจุดสำคัญ
// - ดึงข้อความ error จาก API มาแสดงให้ผู้ใช้ได้ชัดขึ้น
// - กัน refresh attendance ซ้อนกันด้วย sequence guard
// - checkout fallback ใช้เฉพาะ session เปิดของ "วันนี้" เท่านั้น
//
// ✅ PATCH (SMOOTH UX)
// - เพิ่ม phase ของ attendance เพื่อให้ UI รู้ว่า "กำลังสแกน" หรือ "กำลังส่ง"
// - เพิ่ม slow network hint ถ้าเน็ตช้า
// - กันกดซ้ำแล้วเตือนผู้ใช้ชัดเจน
// - refresh attendance จะไม่มาทับตอนกำลัง submit
//
// ✅ PATCH (BACKEND RULE CODES)
// - รองรับ code ใหม่จาก backend เช่น:
//   - MANUAL_REQUIRED_PREVIOUS_OPEN_SESSION
//   - MANUAL_REQUIRED_EARLY_CHECKIN
//   - MANUAL_REQUIRED_AFTER_CUTOFF
//   - EARLY_CHECKOUT_REASON_REQUIRED
//   - CHECKOUT_TOO_FAST
//   - ATTENDANCE_ALREADY_COMPLETED
//   - ALREADY_CHECKED_IN
//   - NO_OPEN_SESSION
// - รองรับ pendingManualSession จาก me-preview
//
// ✅ PATCH (HOME REFRESH UX)
// - ปุ่มสายฟ้า AppBar มี loading state จริง
// - ปุ่มอัปเดตในการ์ดประกาศงานไม่ดูนิ่งเวลาเน็ตช้า
// - กันกดซ้ำทั้ง AppBar refresh และ urgent refresh
// - แสดง snackbar ระหว่างกำลังอัปเดต

import 'dart:async';
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
import 'package:clinic_smart_staff/screens/trustscore_lookup_screen.dart';

import 'package:clinic_smart_staff/models/employee_model.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';
import 'package:clinic_smart_staff/screens/employee_detail_screen.dart';
import 'package:clinic_smart_staff/screens/add_employee_screen.dart';
import 'package:clinic_smart_staff/screens/payslip_preview_screen.dart';

import 'package:clinic_smart_staff/main.dart';

import 'package:clinic_smart_staff/screens/home/tabs/home_tab.dart';
import 'package:clinic_smart_staff/screens/home/tabs/my_tab.dart';
import 'package:clinic_smart_staff/screens/home/widgets/attendance_card.dart';
import 'package:clinic_smart_staff/screens/home/widgets/premium_gate_card.dart';
import 'package:clinic_smart_staff/screens/home/widgets/policy_card.dart';
import 'package:clinic_smart_staff/screens/home/widgets/urgent_jobs_card.dart';
import 'package:clinic_smart_staff/screens/home/widgets/payslip_card.dart';
import 'package:clinic_smart_staff/screens/home/attendance/attendance_history_screen.dart';
import 'package:clinic_smart_staff/screens/home/attendance/manual_attendance_request_screen.dart';

enum _AttendanceSubmitResult {
  success,
  alreadyDone,
  unauthorized,
  forbidden,
  failed,
  manualRequired,
  earlyCheckoutReasonRequired,
}

enum _AttendanceUiPhase {
  idle,
  checkingInBio,
  checkingInSubmit,
  checkingOutBio,
  checkingOutSubmit,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _didSetInitialTab = false;

  // context
  bool _ctxLoading = true;
  String _ctxErr = '';
  String _role = '';
  String _clinicId = '';
  String _userId = '';
  String _staffId = '';

  // premium
  static const String _kPremiumAttendanceKey = 'premium_attendance_enabled';
  bool _premiumLoading = true;
  bool _premiumAttendanceEnabled = false;

  // policy
  bool _policyLoading = false;
  String _policyErr = '';
  Map<String, dynamic> _policy = <String, dynamic>{};
  Map<String, dynamic> _features = <String, dynamic>{};
  List<String> _policyLines = [];

  // urgent
  bool _urgentLoading = false;
  bool _activeRefreshing = false;
  String _urgentErr = '';
  int _urgentCount = 0;
  Map<String, dynamic>? _urgentFirst;

  // payslip
  bool _payslipLoading = false;
  String _payslipErr = '';
  List<Map<String, dynamic>> _closedMonths = [];

  // attendance
  bool _attLoading = false;
  String _attErr = '';
  String _attStatusLine = '';
  bool _attCheckedIn = false;
  bool _attCheckedOut = false;
  bool _attPosting = false;

  // attendance guards
  int _attRefreshSeq = 0;
  bool _attActionLock = false;

  // biometric
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _bioLoading = false;

  // ✅ smoother attendance UX
  _AttendanceUiPhase _attUiPhase = _AttendanceUiPhase.idle;
  String _attProgressText = '';
  bool _showSlowNetworkHint = false;
  Timer? _slowNetworkTimer;

  bool get _attBusy => _attUiPhase != _AttendanceUiPhase.idle;

  String get _displayAttendanceStatusLine {
    final base =
        _attProgressText.trim().isNotEmpty ? _attProgressText.trim() : _attStatusLine.trim();

    if (_showSlowNetworkHint) {
      if (base.isEmpty) {
        return 'อินเทอร์เน็ตค่อนข้างช้า กรุณารอสักครู่';
      }
      return '$base\nอินเทอร์เน็ตค่อนข้างช้า กรุณารอสักครู่';
    }

    return base;
  }

  @override
  void initState() {
    super.initState();
    _bootstrapContext();
  }

  @override
  void dispose() {
    _slowNetworkTimer?.cancel();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _tapLog(String msg) {
    print('TAP -> $msg');
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

  void _setAttendanceUiPhase(
    _AttendanceUiPhase phase, {
    String progressText = '',
    bool clearErr = false,
  }) {
    if (!mounted) return;
    setState(() {
      _attUiPhase = phase;
      _attProgressText = progressText;
      if (clearErr) _attErr = '';
      _bioLoading = phase == _AttendanceUiPhase.checkingInBio ||
          phase == _AttendanceUiPhase.checkingOutBio;
      _attPosting = phase == _AttendanceUiPhase.checkingInSubmit ||
          phase == _AttendanceUiPhase.checkingOutSubmit;
    });
  }

  void _resetAttendanceUiPhase() {
    _slowNetworkTimer?.cancel();
    _slowNetworkTimer = null;
    if (!mounted) return;
    setState(() {
      _attUiPhase = _AttendanceUiPhase.idle;
      _attProgressText = '';
      _showSlowNetworkHint = false;
      _bioLoading = false;
      _attPosting = false;
    });
  }

  void _startSlowNetworkHint() {
    _slowNetworkTimer?.cancel();
    _showSlowNetworkHint = false;
    _slowNetworkTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_attBusy) return;
      setState(() {
        _showSlowNetworkHint = true;
      });
    });
  }

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

  bool get _isClinic =>
      _role == 'admin' || _role == 'clinic' || _role == 'clinic_admin';
  bool get _isEmployee =>
      _role == 'employee' || _role == 'staff' || _role == 'emp';
  bool get _isHelper => _role == 'helper';
  bool get _isAttendanceUser => _isEmployee || _isHelper;

  bool _featureEnabled(String key, {bool fallback = false}) {
    final v = _features[key];
    if (v is bool) return v;
    return fallback;
  }

  bool get _hasBackendPolicy => _policy.isNotEmpty;

  bool get _attendancePremiumEnabled {
    if (_hasBackendPolicy) {
      return _featureEnabled('fingerprintAttendance', fallback: true);
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

  Uri _payrollUri(String path, {Map<String, String>? qs}) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$p');
    return (qs == null) ? uri : uri.replace(queryParameters: qs);
  }

  Future<http.Response> _tryGet(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> _tryPost(
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) async {
    return http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));
  }

  List<Map<String, dynamic>> _decodeNeedList(dynamic decoded) {
    dynamic listAny = decoded;
    if (decoded is Map) {
      if (decoded['items'] is List) {
        listAny = decoded['items'];
      } else if (decoded['data'] is List) {
        listAny = decoded['data'];
      } else if (decoded['results'] is List) {
        listAny = decoded['results'];
      } else if (decoded['needs'] is List) {
        listAny = decoded['needs'];
      }
    }
    if (listAny is! List) return [];
    return listAny
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

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

  Future<void> _loadUrgentNeeds() async {
    if (_ctxLoading) return;

    if (_urgentLoading) {
      print('[URGENT] skipped because loading');
      return;
    }

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

        u = _payrollUri('/shift-needs', qs: {
          'status': 'open',
          'clinicId': cid,
        });
        res = await _tryGet(u, headers: headers);

        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs', qs: {
            'status': 'open',
            'clinicId': cid,
          });
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
        _urgentErr = '';
        _urgentCount = openOnly.length;
        _urgentFirst = openOnly.isNotEmpty ? openOnly.first : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _urgentErr = _friendlyAuthError(e);
        _urgentCount = 0;
        _urgentFirst = null;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _urgentLoading = false;
      });
    }
  }

  Future<void> _activeRefreshUrgent() async {
    if (!mounted) return;

    if (_activeRefreshing) {
      _snack('กำลังอัปเดตข้อมูล...');
      return;
    }

    setState(() {
      _activeRefreshing = true;
    });

    _snack('กำลังอัปเดตข้อมูล...');

    try {
      if (_ctxLoading || _role.trim().isEmpty) {
        await _bootstrapContext();
      } else {
        await _loadClinicPolicy();
        await _loadUrgentNeeds();
        if (_isEmployee) {
          await _loadClosedMonthsForEmployee();
        }
        if (_isAttendanceUser && _attendancePremiumEnabled && !_attBusy) {
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
    } catch (e) {
      if (!mounted) return;
      _snack('ไม่สามารถอัปเดตข้อมูลได้ กรุณาลองใหม่');
    } finally {
      if (!mounted) return;
      setState(() {
        _activeRefreshing = false;
      });
    }
  }

  Future<void> _refreshUrgentCardOnly() async {
    if (_urgentLoading || _activeRefreshing) {
      _snack('กำลังอัปเดตประกาศงาน...');
      return;
    }

    _snack('กำลังอัปเดตประกาศงาน...');
    await _loadUrgentNeeds();

    if (!mounted) return;

    if (_urgentErr.isNotEmpty) {
      _snack(_urgentErr);
      return;
    }

    _snack('อัปเดตประกาศงานล่าสุดแล้ว');
  }

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
      print('[BIO] START');
      final okToTry = await _hasFingerprintAvailable();
      print('[BIO] hasFingerprintAvailable=$okToTry');

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

      print('[BIO] authenticate result=$ok');

      if (!ok) {
        _snack('ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่');
      }

      return ok;
    } on PlatformException catch (e) {
      print('[BIO] PlatformException code=${e.code} message=${e.message}');
      final msg = _bioUserMessageFromCode(e.code);
      _snack(msg);
      return false;
    } catch (e) {
      print('[BIO] ERROR $e');
      _snack('ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่');
      return false;
    }
  }

  Map<String, String> _authHeaders(String token) => <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Map<String, dynamic> _attendancePayload({
    String? reasonCode,
    String? reasonText,
    String? note,
  }) {
    final payload = <String, dynamic>{
      'workDate': _todayYmd(),
      'biometricVerified': true,
      'method': 'biometric',
    };

    if (_clinicId.trim().isNotEmpty) {
      payload['clinicId'] = _clinicId.trim();
    }

    if (_staffId.trim().isNotEmpty) {
      payload['staffId'] = _staffId.trim();
    }

    if ((reasonCode ?? '').trim().isNotEmpty) {
      payload['reasonCode'] = reasonCode!.trim();
    }

    if ((reasonText ?? '').trim().isNotEmpty) {
      payload['reasonText'] = reasonText!.trim();
    }

    if ((note ?? '').trim().isNotEmpty) {
      payload['note'] = note!.trim();
    }

    return payload;
  }

  Map<String, dynamic> _decodeBodyMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _extractApiMessage(http.Response res) {
    final decoded = _decodeBodyMap(res.body);
    final msg = (decoded['message'] ??
            decoded['error'] ??
            decoded['msg'] ??
            decoded['detail'] ??
            '')
        .toString()
        .trim();
    return msg;
  }

  String _extractApiCode(http.Response res) {
    final decoded = _decodeBodyMap(res.body);
    return (decoded['code'] ?? '').toString().trim();
  }

  bool _sameYmdFromAny(dynamic v, String ymd) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return false;
    if (s.length >= 10) {
      return s.substring(0, 10) == ymd;
    }
    return false;
  }

  bool _hasValue(dynamic v) => (v ?? '').toString().trim().isNotEmpty;

  bool _isTodaySession(Map<String, dynamic> s) {
    final today = _todayYmd();
    final workDate = s['workDate'] ?? s['date'] ?? s['day'];
    final ci = s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime'];
    final co = s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime'];

    return _sameYmdFromAny(workDate, today) ||
        _sameYmdFromAny(ci, today) ||
        _sameYmdFromAny(co, today);
  }

  bool _sessionLooksOpen(Map<String, dynamic> s) {
    final status = (s['status'] ?? '').toString().trim().toLowerCase();
    final hasIn =
        _hasValue(s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime']);
    final hasOut =
        _hasValue(s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime']);

    if (status == 'open') return true;
    if (status == 'closed' || status == 'cancelled') return false;

    return hasIn && !hasOut;
  }

  bool _sessionLooksClosed(Map<String, dynamic> s) {
    final status = (s['status'] ?? '').toString().trim().toLowerCase();
    final hasIn =
        _hasValue(s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime']);
    final hasOut =
        _hasValue(s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime']);

    if (status == 'closed') return true;
    if (status == 'open') return false;

    return hasIn && hasOut;
  }

  List<Map<String, dynamic>> _extractAttendanceList(dynamic decoded) {
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

    return list;
  }

  Future<bool> _openManualAttendanceRequest({
    required String manualRequestType,
    String initialReasonCode = '',
    String initialReasonText = '',
    String initialMessage = '',
  }) async {
    if (!mounted) return false;

    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ManualAttendanceRequestScreen(
          role: _role,
          clinicId: _clinicId,
          userId: _userId,
          staffId: _staffId,
          initialWorkDate: _todayYmd(),
          initialManualRequestType: manualRequestType,
          initialReasonCode: initialReasonCode,
          initialReasonText: initialReasonText,
          initialMessage: initialMessage,
        ),
      ),
    );

    return ok == true;
  }

  Future<void> _showManualAttendanceRequiredDialog({
    required String title,
    required String message,
    required String manualRequestType,
    String initialReasonCode = '',
    String initialReasonText = '',
  }) async {
    if (!mounted) return;

    final openManual = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ปิด'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('ส่งคำขอ Manual'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!openManual) return;

    final submitted = await _openManualAttendanceRequest(
      manualRequestType: manualRequestType,
      initialReasonCode: initialReasonCode,
      initialReasonText: initialReasonText,
      initialMessage: message,
    );

    if (submitted) {
      _snack('ส่งคำขอ Manual แล้ว');
    }
  }

  Future<Map<String, String>?> _showEarlyCheckoutReasonDialog() async {
    if (!mounted) return null;

    String selectedReasonCode = 'EARLY_CHECKOUT';
    final reasonTextCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String err = '';

    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return AlertDialog(
              title: const Text('เช็คเอาท์ก่อนเวลา'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'กรุณาระบุเหตุผลก่อนเช็คเอาท์',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedReasonCode,
                      decoration: const InputDecoration(
                        labelText: 'เหตุผล',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'EARLY_CHECKOUT',
                          child: Text('เช็คเอาท์ก่อนเวลา'),
                        ),
                        DropdownMenuItem(
                          value: 'PERSONAL_REASON',
                          child: Text('ติดธุระส่วนตัว'),
                        ),
                        DropdownMenuItem(
                          value: 'SICK',
                          child: Text('ไม่สบาย'),
                        ),
                        DropdownMenuItem(
                          value: 'EMERGENCY',
                          child: Text('เหตุฉุกเฉิน'),
                        ),
                        DropdownMenuItem(
                          value: 'OTHER',
                          child: Text('อื่น ๆ'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setSt(() {
                          selectedReasonCode = v;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonTextCtrl,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'รายละเอียดเหตุผล',
                        hintText: 'เช่น มีเหตุจำเป็นต้องกลับก่อนเวลา',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุเพิ่มเติม',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (err.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          err,
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final reasonText = reasonTextCtrl.text.trim();
                    final note = noteCtrl.text.trim();

                    if (reasonText.isEmpty && note.isEmpty) {
                      setSt(() {
                        err = 'กรุณาระบุรายละเอียดอย่างน้อย 1 ช่อง';
                      });
                      return;
                    }

                    Navigator.pop(ctx, {
                      'reasonCode': selectedReasonCode,
                      'reasonText': reasonText,
                      'note': note,
                    });
                  },
                  child: const Text('ยืนยัน'),
                ),
              ],
            );
          },
        );
      },
    );

    reasonTextCtrl.dispose();
    noteCtrl.dispose();

    return result;
  }

  Future<_AttendanceSubmitResult> _handleAttendanceConflictResponse(
    http.Response res, {
    required bool isCheckIn,
  }) async {
    final code = _extractApiCode(res);
    final apiMsg = _extractApiMessage(res);

    if (code == 'ALREADY_CHECKED_IN') {
      _snack('วันนี้คุณเช็คอินแล้ว');
      return _AttendanceSubmitResult.alreadyDone;
    }

    if (code == 'ATTENDANCE_ALREADY_COMPLETED') {
      _snack('วันนี้เช็คอิน/เช็คเอาท์ครบแล้ว');
      return _AttendanceSubmitResult.alreadyDone;
    }

    if (code == 'NO_OPEN_SESSION') {
      _snack('ไม่พบรายการเช็คอินที่เปิดอยู่สำหรับวันนี้');
      return _AttendanceSubmitResult.failed;
    }

    if (code == 'CHECKOUT_TOO_FAST') {
      final msg = apiMsg.isNotEmpty
          ? apiMsg
          : 'ยังเช็คเอาท์เร็วเกินไป กรุณารอสักครู่แล้วลองใหม่';
      _snack(msg);
      return _AttendanceSubmitResult.failed;
    }

    if (code == 'MANUAL_REQUIRED_PREVIOUS_OPEN_SESSION') {
      await _showManualAttendanceRequiredDialog(
        title: 'ต้องใช้การลงเวลาแบบ Manual',
        message:
            'ยังมี session วันก่อนค้างอยู่ จึงไม่สามารถสแกนเข้าใหม่ได้\n\nกรุณาส่งคำขอแก้ไขเวลาแบบ Manual เพื่อให้คลินิกอนุมัติ',
        manualRequestType: 'edit_both',
        initialReasonCode: 'PREVIOUS_OPEN_SESSION',
      );
      return _AttendanceSubmitResult.manualRequired;
    }

    if (code == 'MANUAL_REQUIRED_EARLY_CHECKIN') {
      await _showManualAttendanceRequiredDialog(
        title: 'เช็คอินก่อนเวลา',
        message:
            'การเช็คอินก่อนเวลาในกะงาน ต้องส่งคำขอแบบ Manual พร้อมเหตุผล และรอคลินิกอนุมัติ',
        manualRequestType: 'check_in',
        initialReasonCode: 'EARLY_CHECKIN',
      );
      return _AttendanceSubmitResult.manualRequired;
    }

    if (code == 'MANUAL_REQUIRED_AFTER_CUTOFF') {
      await _showManualAttendanceRequiredDialog(
        title: 'เลยเวลา Cut-off',
        message:
            'เลยเวลา cut-off ของวันนั้นแล้ว จึงไม่สามารถสแกนเช็คเอาท์ได้\n\nกรุณาส่งคำขอแบบ Manual และรอคลินิกอนุมัติ',
        manualRequestType: 'forgot_checkout',
        initialReasonCode: 'FORGOT_CHECKOUT',
      );
      return _AttendanceSubmitResult.manualRequired;
    }

    if (code == 'EARLY_CHECKOUT_REASON_REQUIRED') {
      return _AttendanceSubmitResult.earlyCheckoutReasonRequired;
    }

    if (apiMsg.isNotEmpty) {
      _snack(apiMsg);
    } else {
      _snack(
        isCheckIn
            ? 'บันทึกเช็คอินไม่สำเร็จ กรุณาลองใหม่'
            : 'บันทึกเช็คเอาท์ไม่สำเร็จ กรุณาลองใหม่',
      );
    }
    return _AttendanceSubmitResult.failed;
  }

  void _applyImmediateCheckInUi() {
    if (!mounted) return;
    setState(() {
      _attErr = '';
      _attCheckedIn = true;
      _attCheckedOut = false;
      _attStatusLine = 'วันนี้เช็คอินแล้ว (ยังไม่เช็คเอาท์)';
    });
  }

  void _applyImmediateCheckOutUi() {
    if (!mounted) return;
    setState(() {
      _attErr = '';
      _attCheckedIn = true;
      _attCheckedOut = true;
      _attStatusLine = 'วันนี้เช็คอินและเช็คเอาท์แล้ว';
    });
  }

  void _applyImmediateAlreadyCheckedInUi() {
    if (!mounted) return;
    setState(() {
      _attErr = '';
      _attCheckedIn = true;
      if (!_attCheckedOut) {
        _attStatusLine = 'วันนี้เช็คอินแล้ว (ยังไม่เช็คเอาท์)';
      }
    });
  }

  void _applyImmediateAlreadyCheckedOutUi() {
    if (!mounted) return;
    setState(() {
      _attErr = '';
      _attCheckedIn = true;
      _attCheckedOut = true;
      _attStatusLine = 'วันนี้เช็คอินและเช็คเอาท์แล้ว';
    });
  }

  Future<void> _refreshAttendanceToday({bool silent = false}) async {
    if (_ctxLoading) return;
    if (!_isAttendanceUser) return;
    if (!_attendancePremiumEnabled) return;
    if (_attBusy && !silent) {
      print('[ATTENDANCE][REFRESH] skipped because busy');
      return;
    }

    final int seq = ++_attRefreshSeq;

    if (!silent && mounted) {
      setState(() {
        _attLoading = true;
        _attErr = '';
      });
    }

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

          if (seq != _attRefreshSeq) return;

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

            final explicitCheckedIn =
                data['checkedIn'] == true || data['hasCheckIn'] == true;
            final explicitCheckedOut =
                data['checkedOut'] == true || data['hasCheckOut'] == true;

            bool checkedIn = explicitCheckedIn;
            bool checkedOut = explicitCheckedOut;

            final attendanceAny = data['attendance'];
            final attendance = attendanceAny is Map
                ? Map<String, dynamic>.from(attendanceAny)
                : <String, dynamic>{};

            final openSessionAny = attendance['openSession'];
            final hasOpenSession = openSessionAny is Map &&
                Map<String, dynamic>.from(openSessionAny).isNotEmpty;

            final pendingManualAny = attendance['pendingManualSession'];
            final hasPendingManual = pendingManualAny is Map &&
                Map<String, dynamic>.from(pendingManualAny).isNotEmpty;

            List<Map<String, dynamic>> sessions = <Map<String, dynamic>>[];
            if (data['sessions'] is List) {
              sessions = (data['sessions'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }

            Map<String, dynamic>? todayOpen;
            Map<String, dynamic>? todayDone;

            for (final s in sessions) {
              if (!_isTodaySession(s)) continue;

              if (_sessionLooksOpen(s)) {
                todayOpen = s;
                break;
              }

              if (_sessionLooksClosed(s)) {
                todayDone ??= s;
              }
            }

            if (hasPendingManual) {
              checkedIn = true;
              checkedOut = false;
            } else if (hasOpenSession || todayOpen != null) {
              checkedIn = true;
              checkedOut = false;
            } else if (todayDone != null) {
              checkedIn = true;
              checkedOut = true;
            } else if (!checkedIn && !checkedOut) {
              final hasTopLevelCheckIn = _hasValue(data['checkInAt']);
              final hasTopLevelCheckOut = _hasValue(data['checkOutAt']);

              if (hasTopLevelCheckIn && !hasTopLevelCheckOut) {
                checkedIn = true;
                checkedOut = false;
              } else if (hasTopLevelCheckIn && hasTopLevelCheckOut) {
                checkedIn = true;
                checkedOut = true;
              }
            }

            if (!checkedIn && data['summary'] is Map) {
              final summary = Map<String, dynamic>.from(data['summary']);
              final workedMinutes = summary['workedMinutes'];
              if (workedMinutes is num && workedMinutes > 0) {
                checkedIn = true;
                checkedOut = true;
              }
            }

            final msg = (data['message'] ?? '').toString().trim();
            final line = msg.isNotEmpty
                ? msg
                : hasPendingManual
                    ? 'วันนี้มีคำขอแก้ไขเวลา รออนุมัติ'
                    : checkedIn
                        ? (checkedOut
                            ? 'วันนี้เช็คอินและเช็คเอาท์แล้ว'
                            : 'วันนี้เช็คอินแล้ว (ยังไม่เช็คเอาท์)')
                        : 'วันนี้ยังไม่ได้เช็คอิน';

            if (!mounted || seq != _attRefreshSeq) return;
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
            if (!mounted || seq != _attRefreshSeq) return;
            setState(() {
              _attLoading = false;
              _attErr = 'ไม่มีสิทธิ์ใช้งานเมนูนี้';
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

        if (seq != _attRefreshSeq) return;

        if (r.statusCode == 404) continue;
        if (r.statusCode == 401) throw Exception('no token');

        if (r.statusCode == 403) {
          if (!mounted || seq != _attRefreshSeq) return;
          setState(() {
            _attLoading = false;
            _attErr = 'ไม่มีสิทธิ์ใช้งานเมนูนี้';
          });
          return;
        }

        if (r.statusCode != 200) break;

        final decoded = jsonDecode(r.body);
        final list = _extractAttendanceList(decoded);

        Map<String, dynamic>? todayOpen;
        Map<String, dynamic>? todayDone;

        for (final s in list) {
          if (!_isTodaySession(s)) continue;

          if (_sessionLooksOpen(s)) {
            todayOpen = s;
            break;
          }

          if (_sessionLooksClosed(s)) {
            todayDone ??= s;
          }
        }

        final checkedIn = todayOpen != null || todayDone != null;
        final checkedOut = todayOpen == null && todayDone != null;
        final line = checkedIn
            ? (checkedOut
                ? 'วันนี้เช็คอินและเช็คเอาท์แล้ว'
                : 'วันนี้เช็คอินแล้ว (ยังไม่เช็คเอาท์)')
            : 'วันนี้ยังไม่ได้เช็คอิน';

        if (!mounted || seq != _attRefreshSeq) return;
        setState(() {
          _attLoading = false;
          _attErr = '';
          _attStatusLine = line;
          _attCheckedIn = checkedIn;
          _attCheckedOut = checkedOut;
        });
        return;
      }

      if (!mounted || seq != _attRefreshSeq) return;
      setState(() {
        _attLoading = false;
        _attErr = 'เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่';
      });
    } catch (e) {
      if (!mounted || seq != _attRefreshSeq) return;
      setState(() {
        _attLoading = false;
        _attErr = _friendlyAuthError(e);
      });
    }
  }

  Future<_AttendanceSubmitResult> _postAttendanceCheckIn({
    required String token,
  }) async {
    final headers = _authHeaders(token);
    final body = jsonEncode(_attendancePayload());

    final candidates = <String>[
      '/attendance/check-in',
      '/api/attendance/check-in',
    ];

    http.Response? lastRes;

    for (final p in candidates) {
      try {
        final u = _payrollUri(p);
        print('[ATTENDANCE][CHECKIN] POST $u');
        print('[ATTENDANCE][CHECKIN] BODY $body');

        final res = await _tryPost(u, headers: headers, body: body);
        lastRes = res;

        print(
          '[ATTENDANCE][CHECKIN] STATUS=${res.statusCode} BODY=${res.body}',
        );

        if (res.statusCode == 200 || res.statusCode == 201) {
          return _AttendanceSubmitResult.success;
        }

        if (res.statusCode == 409) {
          return _handleAttendanceConflictResponse(res, isCheckIn: true);
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

        final apiMsg = _extractApiMessage(res);
        if (apiMsg.isNotEmpty) {
          _snack(apiMsg);
        } else {
          _snack('บันทึกเช็คอินไม่สำเร็จ กรุณาลองใหม่');
        }
        return _AttendanceSubmitResult.failed;
      } catch (e) {
        print('[ATTENDANCE][CHECKIN] ERROR $e');
        continue;
      }
    }

    if (lastRes != null) {
      final apiMsg = _extractApiMessage(lastRes);
      _snack(apiMsg.isNotEmpty ? apiMsg : 'บันทึกเช็คอินไม่สำเร็จ กรุณาลองใหม่');
    } else {
      _snack('เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่');
    }

    return _AttendanceSubmitResult.failed;
  }

  Future<_AttendanceSubmitResult> _postAttendanceCheckOut({
    required String token,
    String? reasonCode,
    String? reasonText,
    String? note,
  }) async {
    final headers = _authHeaders(token);
    final body = jsonEncode(
      _attendancePayload(
        reasonCode: reasonCode,
        reasonText: reasonText,
        note: note,
      ),
    );

    final directCandidates = <String>[
      '/attendance/check-out',
      '/api/attendance/check-out',
    ];

    http.Response? lastRes;
    bool shouldTryIdFallback = false;

    for (final p in directCandidates) {
      try {
        final u = _payrollUri(p);
        print('[ATTENDANCE][CHECKOUT] POST $u');
        print('[ATTENDANCE][CHECKOUT] BODY $body');

        final res = await _tryPost(u, headers: headers, body: body);
        lastRes = res;

        print(
          '[ATTENDANCE][CHECKOUT] STATUS=${res.statusCode} BODY=${res.body}',
        );

        if (res.statusCode == 200 || res.statusCode == 201) {
          return _AttendanceSubmitResult.success;
        }

        if (res.statusCode == 409) {
          final code = _extractApiCode(res);

          if (code == 'NO_OPEN_SESSION') {
            shouldTryIdFallback = true;
            continue;
          }

          return _handleAttendanceConflictResponse(res, isCheckIn: false);
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

        final apiMsg = _extractApiMessage(res);
        if (apiMsg.isNotEmpty) {
          _snack(apiMsg);
        } else {
          _snack('บันทึกเช็คเอาท์ไม่สำเร็จ กรุณาลองใหม่');
        }
        return _AttendanceSubmitResult.failed;
      } catch (e) {
        print('[ATTENDANCE][CHECKOUT] ERROR $e');
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
          print('[ATTENDANCE][CHECKOUT] FALLBACK GET $u');

          final r = await _tryGet(u, headers: headers);

          print(
            '[ATTENDANCE][CHECKOUT] FALLBACK STATUS=${r.statusCode} BODY=${r.body}',
          );

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
          final list = _extractAttendanceList(decoded);

          Map<String, dynamic>? openToday;

          for (final s in list) {
            final hasOut = _hasValue(
              s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime'],
            );

            if (_isTodaySession(s) && !hasOut) {
              openToday = s;
              break;
            }
          }

          final id = (openToday?['_id'] ?? openToday?['id'] ?? '')
              .toString()
              .trim();

          print('[ATTENDANCE][CHECKOUT] FALLBACK SESSION ID=$id');

          if (id.isEmpty) {
            _snack('วันนี้ไม่พบรายการเช็คอินที่เปิดอยู่');
            return _AttendanceSubmitResult.failed;
          }

          final idCandidates = <String>[
            '/attendance/$id/check-out',
            '/api/attendance/$id/check-out',
          ];

          for (final p2 in idCandidates) {
            final u2 = _payrollUri(p2);
            print('[ATTENDANCE][CHECKOUT] FALLBACK POST $u2');

            final r2 = await _tryPost(u2, headers: headers, body: body);
            lastRes = r2;

            print(
              '[ATTENDANCE][CHECKOUT] FALLBACK POST STATUS=${r2.statusCode} BODY=${r2.body}',
            );

            if (r2.statusCode == 200 || r2.statusCode == 201) {
              return _AttendanceSubmitResult.success;
            }

            if (r2.statusCode == 409) {
              return _handleAttendanceConflictResponse(r2, isCheckIn: false);
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

            final apiMsg = _extractApiMessage(r2);
            if (apiMsg.isNotEmpty) {
              _snack(apiMsg);
            } else {
              _snack('บันทึกเช็คเอาท์ไม่สำเร็จ กรุณาลองใหม่');
            }
            return _AttendanceSubmitResult.failed;
          }

          break;
        }
      } catch (e) {
        print('[ATTENDANCE][CHECKOUT] FALLBACK ERROR $e');
      }
    }

    if (lastRes != null) {
      final apiMsg = _extractApiMessage(lastRes);
      _snack(apiMsg.isNotEmpty ? apiMsg : 'บันทึกเช็คเอาท์ไม่สำเร็จ กรุณาลองใหม่');
    } else {
      _snack('เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่');
    }
    return _AttendanceSubmitResult.failed;
  }

  Future<void> _scanAndCheckIn() async {
    _tapLog('SCAN_CHECKIN');
    print('[ATTENDANCE] ROLE=$_role clinicId=$_clinicId staffId=$_staffId');

    if (_attActionLock || _attBusy) {
      _snack('กรุณารอสักครู่ ระบบกำลังดำเนินการ');
      print('[ATTENDANCE][CHECKIN] BLOCKED busy/actionLock');
      return;
    }
    _attActionLock = true;

    try {
      if (_ctxLoading) {
        print('[ATTENDANCE][CHECKIN] BLOCKED ctxLoading=$_ctxLoading');
        _snack('กำลังเตรียมข้อมูล กรุณาลองอีกครั้ง');
        return;
      }

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

      _setAttendanceUiPhase(
        _AttendanceUiPhase.checkingInBio,
        progressText: 'กรุณาสแกนลายนิ้วมือ',
        clearErr: true,
      );

      print('[ATTENDANCE][CHECKIN] BEFORE BIO');
      final okBio = await _biometricAuthenticate();
      print('[ATTENDANCE][CHECKIN] AFTER BIO ok=$okBio');

      if (!okBio) return;

      final token = await _getTokenAny();
      print(
        '[ATTENDANCE][CHECKIN] TOKEN exists=${token != null && token.isNotEmpty}',
      );

      if (token == null || token.isEmpty) {
        _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
        return;
      }

      _setAttendanceUiPhase(
        _AttendanceUiPhase.checkingInSubmit,
        progressText: 'กำลังส่งข้อมูลไปยังระบบ',
      );
      _startSlowNetworkHint();

      print('[ATTENDANCE][CHECKIN] BEFORE POST');
      final result = await _postAttendanceCheckIn(token: token);
      print('[ATTENDANCE][CHECKIN] RESULT=$result');

      if (result == _AttendanceSubmitResult.success) {
        _applyImmediateCheckInUi();
        _snack('บันทึกสำเร็จ');
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.alreadyDone) {
        _applyImmediateAlreadyCheckedInUi();
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.manualRequired) {
        await _refreshAttendanceToday(silent: true);
      }
    } finally {
      _resetAttendanceUiPhase();
      _attActionLock = false;
      print('[ATTENDANCE][CHECKIN] FINALLY');
    }
  }

  Future<void> _scanAndCheckOut() async {
    _tapLog('SCAN_CHECKOUT');
    print('[ATTENDANCE] ROLE=$_role clinicId=$_clinicId staffId=$_staffId');

    if (_attActionLock || _attBusy) {
      _snack('กรุณารอสักครู่ ระบบกำลังดำเนินการ');
      print('[ATTENDANCE][CHECKOUT] BLOCKED busy/actionLock');
      return;
    }
    _attActionLock = true;

    try {
      if (_ctxLoading) {
        print('[ATTENDANCE][CHECKOUT] BLOCKED ctxLoading=$_ctxLoading');
        _snack('กำลังเตรียมข้อมูล กรุณาลองอีกครั้ง');
        return;
      }

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

      _setAttendanceUiPhase(
        _AttendanceUiPhase.checkingOutBio,
        progressText: 'กรุณาสแกนลายนิ้วมือ',
        clearErr: true,
      );

      print('[ATTENDANCE][CHECKOUT] BEFORE BIO');
      final okBio = await _biometricAuthenticate();
      print('[ATTENDANCE][CHECKOUT] AFTER BIO ok=$okBio');

      if (!okBio) return;

      final token = await _getTokenAny();
      print(
        '[ATTENDANCE][CHECKOUT] TOKEN exists=${token != null && token.isNotEmpty}',
      );

      if (token == null || token.isEmpty) {
        _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
        return;
      }

      _setAttendanceUiPhase(
        _AttendanceUiPhase.checkingOutSubmit,
        progressText: 'กำลังส่งข้อมูลไปยังระบบ',
      );
      _startSlowNetworkHint();

      print('[ATTENDANCE][CHECKOUT] BEFORE POST');
      final result = await _postAttendanceCheckOut(token: token);
      print('[ATTENDANCE][CHECKOUT] RESULT=$result');

      if (result == _AttendanceSubmitResult.success) {
        _applyImmediateCheckOutUi();
        _snack('บันทึกสำเร็จ');
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.alreadyDone) {
        _applyImmediateAlreadyCheckedOutUi();
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.manualRequired) {
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.earlyCheckoutReasonRequired) {
        _resetAttendanceUiPhase();

        final reason = await _showEarlyCheckoutReasonDialog();
        if (reason == null) {
          return;
        }

        _setAttendanceUiPhase(
          _AttendanceUiPhase.checkingOutSubmit,
          progressText: 'กำลังส่งข้อมูลพร้อมเหตุผล',
          clearErr: true,
        );
        _startSlowNetworkHint();

        final retry = await _postAttendanceCheckOut(
          token: token,
          reasonCode: reason['reasonCode'],
          reasonText: reason['reasonText'],
          note: reason['note'],
        );

        print('[ATTENDANCE][CHECKOUT] RETRY RESULT=$retry');

        if (retry == _AttendanceSubmitResult.success) {
          _applyImmediateCheckOutUi();
          _snack('บันทึกสำเร็จ');
          await _refreshAttendanceToday(silent: true);
        } else if (retry == _AttendanceSubmitResult.alreadyDone) {
          _applyImmediateAlreadyCheckedOutUi();
          await _refreshAttendanceToday(silent: true);
        } else if (retry == _AttendanceSubmitResult.manualRequired) {
          await _refreshAttendanceToday(silent: true);
        }
      }
    } finally {
      _resetAttendanceUiPhase();
      _attActionLock = false;
      print('[ATTENDANCE][CHECKOUT] FINALLY');
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

    if (_attendancePremiumEnabled && _isAttendanceUser && !_attBusy) {
      await _refreshAttendanceToday();
    }
  }

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
    return UrgentJobsCard(
      visible: _isClinic || _isHelper,
      loading: _urgentLoading,
      errText: _urgentErr,
      count: _urgentCount,
      line: (_urgentFirst == null) ? '' : _oneLineNeed(_urgentFirst!),
      isClinic: _isClinic,
      onRefresh: _refreshUrgentCardOnly,
      onOpenList: _isHelper ? _openHelperOpenNeeds : _openClinicNeedsMarket,
    );
  }

  Widget _policyCard() {
    if (!_isAttendanceUser) return const SizedBox.shrink();
    if (!_policyHumanReadableEnabled) return const SizedBox.shrink();

    return PolicyCard(
      loading: _policyLoading,
      errText: _policyErr,
      lines: _policyLines,
      isHelper: _isHelper,
      onRetry: _loadClinicPolicy,
    );
  }

  Widget _attendancePremiumGateCard({bool compact = false}) {
    if (!_isAttendanceUser) return const SizedBox.shrink();

    final title =
        compact ? 'Premium Attendance' : 'Premium: บันทึกเวลางานด้วยลายนิ้วมือ';

    final subtitle = _isHelper
        ? 'ผู้ช่วยสามารถเช็คอิน/เช็คเอาท์ด้วยลายนิ้วมือ เพื่อให้ระบบคำนวณชั่วโมงงานจริงได้แม่นยำขึ้น'
        : 'เช็คอิน/เช็คเอาท์ด้วยลายนิ้วมือ เพื่อให้ระบบคำนวณชั่วโมงงานและ OT ให้อัตโนมัติ';

    return PremiumGateCard(
      loading: _premiumLoading || _policyLoading,
      enabled: _attendancePremiumEnabled,
      title: title,
      subtitle: subtitle,
      onUpgrade: () async {
        _tapLog('UPGRADE_PREMIUM_DIALOG');
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('เปิดใช้งาน Premium'),
            content: const Text(
              'ตอนนี้ยังเป็นโหมดทดสอบ (ยังไม่ผูกชำระเงินจริง)\nต้องการเปิด Premium Attendance ไหม?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('เปิดใช้งาน'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await _setPremiumAttendanceEnabled(true);
          _snack('เปิดใช้งาน Premium แล้ว');
        }
      },
    );
  }

  Widget _attendanceActionCard({String? header}) {
    if (!_isAttendanceUser) return const SizedBox.shrink();
    if (!_attendancePremiumEnabled) return const SizedBox.shrink();

    return AttendanceCard(
      title: header ??
          (_isHelper ? 'บันทึกการทำงานวันนี้ (ผู้ช่วย)' : 'บันทึกการทำงานวันนี้'),
      statusLine: _displayAttendanceStatusLine,
      errText: _attErr,
      loading: _attLoading,
      posting: _attPosting,
      bioLoading: _bioLoading,
      checkedIn: _attCheckedIn,
      checkedOut: _attCheckedOut,
      onCheckIn: _scanAndCheckIn,
      onCheckOut: _scanAndCheckOut,
      onRefresh: () => _refreshAttendanceToday(),
      onOpenHistory: _openAttendanceHistory,
    );
  }

  Widget _employeePayslipCard() {
    if (!_isEmployee) return const SizedBox.shrink();

    final months = _closedMonths
        .map((e) => (e['month'] ?? '').toString().trim())
        .where((m) => m.isNotEmpty)
        .toList();

    return PayslipCard(
      loading: _payslipLoading,
      errText: _payslipErr,
      months: months,
      onRetry: _loadClosedMonthsForEmployee,
      onOpenMonth: _openPayslipMonth,
    );
  }

  Widget _homeTab() {
    if (_ctxLoading) return const Center(child: CircularProgressIndicator());

    if (_ctxErr.isNotEmpty) {
      return _errorBox(
        title: 'ไม่พร้อมใช้งาน',
        message: _ctxErr,
        onRetry: _bootstrapContext,
      );
    }

    final trustScoreCard = _isClinic
        ? Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'คะเเนนความน่าเชื่อถือ ผู้ช่วย',
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
                      label: const Text('ดู คะแนนความน่าเชื่อถือ'),
                    ),
                  ),
                ],
              ),
            ),
          )
        : null;

    final marketCard = (_isClinic || _isHelper)
        ? Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ตลาดงาน',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.local_hospital_outlined),
                    title: const Text('สำหรับคลินิก'),
                    subtitle: const Text('ดูประกาศงานและจัดการงานของคลินิก'),
                    onTap: _openClinicNeedsMarket,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('สำหรับผู้ช่วย'),
                    subtitle: const Text('ดูงานว่างและสมัครงาน'),
                    onTap: _openHelperOpenNeeds,
                  ),
                ],
              ),
            ),
          )
        : null;

    return HomeTab(
      isAttendanceUser: _isAttendanceUser,
      attendancePremiumEnabled: _attendancePremiumEnabled,
      isEmployee: _isEmployee,
      isClinic: _isClinic,
      isHelper: _isHelper,
      premiumGateCard: _attendancePremiumGateCard(),
      attendanceCard: _attendanceActionCard(
        header: _isHelper ? 'บันทึกการทำงาน (ผู้ช่วย)' : 'บันทึกการทำงาน',
      ),
      policyCard: _policyCard(),
      payslipCard: _employeePayslipCard(),
      urgentCard: _urgentCardCompact(),
      trustScoreCard: trustScoreCard,
      marketCard: marketCard,
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

    final clinicSection = _isClinic
        ? Card(
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
                        builder: (_) => const LocalPayrollScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          )
        : null;

    final helperSection = _isHelper
        ? Card(
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
          )
        : null;

    final employeeSection = _isEmployee
        ? Card(
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
          )
        : null;

    return MyTab(
      isAttendanceUser: _isAttendanceUser,
      attendancePremiumEnabled: _attendancePremiumEnabled,
      hasBackendPolicy: _hasBackendPolicy,
      isClinic: _isClinic,
      isHelper: _isHelper,
      isEmployee: _isEmployee,
      premiumAttendanceEnabled: _premiumAttendanceEnabled,
      onOpenAttendanceHistory: _openAttendanceHistory,
      policyCard: _policyCard(),
      clinicSection: clinicSection,
      helperSection: helperSection,
      employeeSection: employeeSection,
      onTogglePremiumAttendance: (v) async => _setPremiumAttendanceEnabled(v),
      onLogout: _logout,
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
            icon: _activeRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.flash_on),
            onPressed: _activeRefreshing ? null : _activeRefreshUrgent,
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
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'My',
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// ✅ Payslip Month Detail
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

  Future<http.Response> _tryGet(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
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
        '/payroll-close/close-month/${widget.staffId}/${widget.month}',
      );
      http.Response res = await _tryGet(u, headers: headers);

      if (res.statusCode == 404) {
        u = _payrollUri(
          '/api/payroll-close/close-month/${widget.staffId}/${widget.month}',
        );
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
                            const Text(
                              'ไม่พร้อมใช้งาน',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _err,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
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
                            const Text(
                              'สรุป',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _kv('รายรับรวม', '฿${_fmtMoney(r?['grossMonthly'])}'),
                            _kv(
                              'ภาษีหัก ณ ที่จ่าย',
                              '฿${_fmtMoney(r?['withheldTaxMonthly'])}',
                            ),
                            _kv(
                              'ประกันสังคม',
                              '฿${_fmtMoney(r?['ssoEmployeeMonthly'])}',
                            ),
                            _kv(
                              'กองทุนสำรองเลี้ยงชีพ',
                              '฿${_fmtMoney(r?['pvdEmployeeMonthly'])}',
                            ),
                            const Divider(height: 16),
                            _kv(
                              'รับสุทธิ',
                              '฿${_fmtMoney(r?['netPay'])}',
                              bold: true,
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
                            const Text(
                              'รายละเอียด OT',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _kv('OT ที่รวมในงวดนี้', '฿${_fmtMoney(r?['otPay'])}'),
                            _kv(
                              'รวมเวลาที่อนุมัติ (นาที)',
                              '${(r?['otApprovedMinutes'] ?? 0)}',
                            ),
                            _kv(
                              'ชั่วโมงถ่วงน้ำหนัก',
                              '${(r?['otApprovedWeightedHours'] ?? 0)}',
                            ),
                            _kv('จำนวนรายการ', '${(r?['otApprovedCount'] ?? 0)}'),
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
                            const Text(
                              'องค์ประกอบรายได้',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _kv('เงินเดือน/ฐาน', '฿${_fmtMoney(r?['grossBase'])}'),
                            _kv('โบนัส', '฿${_fmtMoney(r?['bonus'])}'),
                            _kv(
                              'เงินเพิ่มอื่นๆ',
                              '฿${_fmtMoney(r?['otherAllowance'])}',
                            ),
                            _kv(
                              'หักอื่นๆ',
                              '฿${_fmtMoney(r?['otherDeduction'])}',
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

/// ============================================================
/// ✅ Local Payroll
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
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ'),
          ),
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
      context,
      MaterialPageRoute(builder: (_) => const AddEmployeeScreen()),
    );
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
                          horizontal: 10,
                          vertical: 5,
                        ),
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
                                icon: const Icon(
                                  Icons.picture_as_pdf,
                                  color: Colors.red,
                                ),
                                onPressed: () => _openPayslipPreview(emp),
                              ),
                              IconButton(
                                tooltip: 'ลบพนักงาน',
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.grey,
                                ),
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