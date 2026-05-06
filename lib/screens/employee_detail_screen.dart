import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/models/employee_model.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/api/payroll_close_api.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

import 'package:clinic_smart_staff/screens/payroll/payroll_after_tax_preview_screen.dart';
import 'package:clinic_smart_staff/screens/clinic/clinic_home_screen.dart';
import 'package:clinic_smart_staff/screens/edit_employee_screen.dart';

enum _EmployeeTaxMode { none, withholding }

class WorkHourEntry {
  final String date;
  final double hours;

  const WorkHourEntry({required this.date, required this.hours});

  Map<String, dynamic> toMap() => {'date': date, 'hours': hours};

  factory WorkHourEntry.fromMap(Map<String, dynamic> map) {
    return WorkHourEntry(
      date: (map['date'] ?? '').toString(),
      hours: (map['hours'] as num? ?? 0).toDouble(),
    );
  }

  bool isInMonth(int year, int month) {
    final d = DateTime.tryParse(date);
    if (d == null) return false;
    return d.year == year && d.month == month;
  }
}

class WorkTimeEntry {
  final String date;
  final String start;
  final String end;
  final int breakMinutes;

  const WorkTimeEntry({
    required this.date,
    required this.start,
    required this.end,
    this.breakMinutes = 0,
  });

  Map<String, dynamic> toMap() => {
    'date': date,
    'start': start,
    'end': end,
    'breakMinutes': breakMinutes,
  };

  factory WorkTimeEntry.fromMap(Map<String, dynamic> map) {
    return WorkTimeEntry(
      date: (map['date'] ?? '').toString(),
      start: (map['start'] ?? '').toString(),
      end: (map['end'] ?? '').toString(),
      breakMinutes: (map['breakMinutes'] as num? ?? 0).toInt(),
    );
  }

  bool isInMonth(int year, int month) {
    final d = DateTime.tryParse(date);
    if (d == null) return false;
    return d.year == year && d.month == month;
  }

  double get hours {
    final s = _parseHHmm(start);
    final e = _parseHHmm(end);
    if (s == null || e == null) return 0.0;

    final startMin = s.$1 * 60 + s.$2;
    var endMin = e.$1 * 60 + e.$2;

    if (endMin < startMin) {
      endMin += 24 * 60;
    }

    final total = endMin - startMin - breakMinutes;
    if (total <= 0) return 0.0;

    return total / 60.0;
  }

  static (int, int)? _parseHHmm(String v) {
    final t = v.trim();
    final parts = t.split(':');
    if (parts.length != 2) return null;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);

    if (h == null || m == null) return null;
    if (h < 0 || h > 23) return null;
    if (m < 0 || m > 59) return null;

    return (h, m);
  }
}

class _ManualOtSaveResult {
  final bool ok;
  final int statusCode;
  final String message;
  final String savedStatus;

  const _ManualOtSaveResult({
    required this.ok,
    required this.statusCode,
    required this.message,
    this.savedStatus = '',
  });

  bool get isDuplicate => statusCode == 409;
}

class EmployeeDetailScreen extends StatefulWidget {
  final String clinicId;
  final EmployeeModel employee;

  const EmployeeDetailScreen({
    super.key,
    this.clinicId = '',
    required this.employee,
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  late EmployeeModel emp;

  bool _isEditUnlocked = false;
  bool _disposed = false;

  final ScrollController _scrollCtrl = ScrollController();

  DateTime selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  late final TextEditingController ssoPercentCtrl;
  late final TextEditingController withholdingPercentCtrl;

  final TextInputFormatter _decimalFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'));

  bool _savingSso = false;
  bool _savingTax = false;

  bool _workEntriesLoaded = false;

  List<WorkHourEntry> _allWorkEntries = [];
  DateTime? workDate;
  late final TextEditingController workHoursCtrl;

  List<WorkTimeEntry> _allWorkTimeEntries = [];
  DateTime? workTimeDate;
  TimeOfDay? workStart;
  TimeOfDay? workEnd;
  late final TextEditingController breakMinutesCtrl;

  DateTime? otDate;
  TimeOfDay? otStart;
  TimeOfDay? otEnd;

  bool isHolidayX2 = false;

  static const double _defaultOtNormalMultiplier = 1.5;
  static const double _defaultOtHolidayMultiplier = 2.0;
  static const double _defaultWithholdingPercent = 3.0;

  bool _loadingOtPolicy = false;
  String _otPolicyError = '';
  double? _policyOtMultiplier;
  double? _policyHolidayMultiplier;

  bool _loadingBackendOt = false;
  bool _savingManualOt = false;
  String _backendOtError = '';
  List<Map<String, dynamic>> _backendOtRows = [];

  bool _loadingClosedPayroll = false;
  String _closedPayrollError = '';
  Map<String, dynamic>? _closedPayrollRow;
  Map<String, dynamic>? _closedPayslipSummary;
  bool _recalculatingClosedPayroll = false;

  // ✅ Backend preview for open month.
  // Important for part-time: normal wage must come from backend Attendance
  // instead of local manual hours only.
  bool _loadingPayrollPreview = false;
  String _payrollPreviewError = '';
  Map<String, dynamic>? _payrollPreviewRow;
  Map<String, dynamic>? _payrollPreviewSummary;
  Map<String, dynamic>? _payrollPreviewInputs;

  String _backendOtStatus = 'approved';

  int _backendApprovedMinutes = 0;
  double _backendApprovedWeightedHours = 0.0;
  int _backendApprovedCount = 0;

  _EmployeeTaxMode _taxMode = _EmployeeTaxMode.none;

  bool _loadingClinicPayrollConfig = false;
  String _clinicPayrollConfigError = '';

  bool? _clinicSsoEnabled;
  double? _clinicSsoEmployeeRate;
  double? _clinicSsoMaxWageBase;

  double get _normalOtMultiplier {
    final v = _policyOtMultiplier;
    if (v == null || v <= 0) return _defaultOtNormalMultiplier;
    return v;
  }

  double get _holidayOtMultiplier {
    final v = _policyHolidayMultiplier;
    if (v == null || v <= 0) return _defaultOtHolidayMultiplier;
    return v;
  }

  double get _effectiveClinicSsoRate {
    final v = _clinicSsoEmployeeRate;
    if (v == null || v <= 0) return 0.05;
    return v;
  }

  double get _effectiveClinicSsoMaxWageBase {
    final v = _clinicSsoMaxWageBase;
    if (v == null || v <= 0) return 17500.0;
    return v;
  }

  bool get _effectiveClinicSsoEnabled {
    return _clinicSsoEnabled != false;
  }

  double _computeSsoFromClinicConfig(double salaryBase) {
    if (!_effectiveClinicSsoEnabled) return 0.0;
    final contributableBase = salaryBase
        .clamp(0.0, _effectiveClinicSsoMaxWageBase)
        .toDouble();
    return contributableBase * _effectiveClinicSsoRate;
  }

  String get _employeeTaxModeKey => 'employee_tax_mode_${emp.id}';
  String get _employeeWithholdingPercentKey =>
      'employee_withholding_percent_${emp.id}';

  @override
  void initState() {
    super.initState();

    ssoPercentCtrl = TextEditingController();
    withholdingPercentCtrl = TextEditingController(
      text: _defaultWithholdingPercent.toStringAsFixed(2),
    );
    workHoursCtrl = TextEditingController(text: '');
    breakMinutesCtrl = TextEditingController(text: '0');

    emp = widget.employee;
    selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

    _initTaxSettingsFromPrefs();
    _loadWorkEntriesIfNeeded();
    _loadClinicOtPolicy();
    _loadClinicPayrollConfig();
    _loadBackendOtForSelectedMonth();
    _loadClosedPayrollForSelectedMonth();
  }

  @override
  void dispose() {
    _disposed = true;
    _scrollCtrl.dispose();
    ssoPercentCtrl.dispose();
    withholdingPercentCtrl.dispose();
    workHoursCtrl.dispose();
    breakMinutesCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _empMapSafe() {
    try {
      final dyn = emp as dynamic;

      try {
        final m = dyn.toMap();
        if (m is Map) {
          return Map<String, dynamic>.from(
            m.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      } catch (_) {}

      try {
        final m = dyn.toJson();
        if (m is Map) {
          return Map<String, dynamic>.from(
            m.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      } catch (_) {}
    } catch (_) {}

    final out = <String, dynamic>{};

    try {
      out['id'] = (emp as dynamic).id?.toString() ?? '';
    } catch (_) {
      out['id'] = '';
    }

    try {
      final v = (emp as dynamic).fullName;
      if (v != null) out['fullName'] = v.toString();
    } catch (_) {}

    try {
      final v = (emp as dynamic).isPartTime;
      if (v != null) out['isPartTime'] = v == true;
    } catch (_) {}

    try {
      final v = (emp as dynamic).employeeCode;
      if (v != null) out['employeeCode'] = v.toString();
    } catch (_) {}

    try {
      final v = (emp as dynamic).staffId;
      if (v != null) out['staffId'] = v.toString();
    } catch (_) {}

    try {
      final v = (emp as dynamic).staffID;
      if (v != null) out['staffID'] = v.toString();
    } catch (_) {}

    try {
      final v = (emp as dynamic).staff_id;
      if (v != null) out['staff_id'] = v.toString();
    } catch (_) {}

    try {
      final v = (emp as dynamic).linkedUserId;
      if (v != null) out['linkedUserId'] = v.toString();
    } catch (_) {}

    try {
      final v = (emp as dynamic).linked_user_id;
      if (v != null) out['linked_user_id'] = v.toString();
    } catch (_) {}

    try {
      final v = (emp as dynamic).userId;
      if (v != null) out['userId'] = v.toString();
    } catch (_) {}

    try {
      final v = (emp as dynamic).user_id;
      if (v != null) out['user_id'] = v.toString();
    } catch (_) {}

    try {
      final v = (emp as dynamic).assignmentId;
      if (v != null) out['assignmentId'] = v.toString();
    } catch (_) {}

    try {
      final v = (emp as dynamic).shiftNeedId;
      if (v != null) out['shiftNeedId'] = v.toString();
    } catch (_) {}

    return out;
  }

  String _resolveLinkedUserId() {
    String pick(dynamic v) => (v ?? '').toString().trim();

    final m = _empMapSafe();

    final candidates = <String>[
      pick(m['linkedUserId']),
      pick(m['linked_user_id']),
      pick(m['userId']),
      pick(m['user_id']),
      if (m['user'] is Map) pick((m['user'] as Map)['id']),
      if (m['user'] is Map) pick((m['user'] as Map)['userId']),
      if (m['linkedUser'] is Map) pick((m['linkedUser'] as Map)['id']),
      if (m['linkedUser'] is Map) pick((m['linkedUser'] as Map)['userId']),
    ].where((x) => x.isNotEmpty).toList();

    return candidates.isEmpty ? '' : candidates.first;
  }

  String _resolveStaffIdForPayroll() {
    String pick(dynamic v) => (v ?? '').toString().trim();

    final m = _empMapSafe();

    final candidates = <String>[
      pick(m['staffId']),
      pick(m['staffID']),
      pick(m['staff_id']),
      pick(m['employeeId']),
      pick(m['employeeID']),
      pick(m['employee_id']),
      pick(m['principalId']),
      pick(m['principal_id']),
      pick(m['id']),
      pick(m['_id']),
      if (m['staff'] is Map) pick((m['staff'] as Map)['id']),
      if (m['staff'] is Map) pick((m['staff'] as Map)['staffId']),
      if (m['user'] is Map) pick((m['user'] as Map)['staffId']),
      if (m['user'] is Map) pick((m['user'] as Map)['id']),
    ].where((x) => x.isNotEmpty).toList();

    return candidates.isEmpty ? '' : candidates.first;
  }

  Future<void> _safePopOrGoClinicHome() async {
    if (!mounted) return;

    final nav = Navigator.of(context);

    if (nav.canPop()) {
      nav.pop();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ClinicHomeScreen()),
        (route) => false,
      );
    });
  }

  void _snack(String msg) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  String _fmtMonth(DateTime d) => '${d.year}-${_two(d.month)}';

  String _fmtCloseMonth(DateTime d) => _fmtMonth(d);

  String _fmtTOD(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  bool _isSameMonth(DateTime d, DateTime month) {
    return d.year == month.year && d.month == month.month;
  }

  DateTime _monthStart(DateTime month) {
    return DateTime(month.year, month.month, 1);
  }

  DateTime _monthEnd(DateTime month) {
    return DateTime(month.year, month.month + 1, 0);
  }

  DateTime _initialOtPickerDate() {
    final first = _monthStart(selectedMonth);
    final now = DateTime.now();

    if (otDate != null && _isSameMonth(otDate!, selectedMonth)) {
      return otDate!;
    }

    if (_isSameMonth(now, selectedMonth)) {
      return now;
    }

    return first;
  }

  Uri _uri(String path) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Future<String?> _getToken() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.trim().isNotEmpty) return t.trim();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();

      final t1 = (prefs.getString('auth_token') ?? '').trim();
      if (t1.isNotEmpty) return t1;

      final t2 = (prefs.getString('token') ?? '').trim();
      if (t2.isNotEmpty) return t2;
    } catch (_) {}

    return null;
  }

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) {
      return Map<String, dynamic>.from(
        v.map((k, val) => MapEntry(k.toString(), val)),
      );
    }

    return <String, dynamic>{};
  }

  double _readNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0.0;
  }

  Map<String, dynamic> _appendEmployeeIdentityToBody(
    Map<String, dynamic> body, {
    bool includeStaffId = true,
  }) {
    final out = Map<String, dynamic>.from(body);

    final linkedUserId = _resolveLinkedUserId();
    final staffId = _resolveStaffIdForPayroll();
    final empMap = _empMapSafe();

    if (linkedUserId.isNotEmpty) {
      out['linkedUserId'] = linkedUserId;
      out['employeeUserId'] = linkedUserId;
      out['userId'] = linkedUserId;
      out['principalUserId'] = linkedUserId;
    }

    if (includeStaffId && staffId.isNotEmpty) {
      out['staffId'] = staffId;
      out['employeeId'] = staffId;
      out['principalId'] = staffId;
    }

    final assignmentId = (empMap['assignmentId'] ?? '').toString().trim();
    if (assignmentId.isNotEmpty) {
      out['assignmentId'] = assignmentId;
      out['workAssignmentId'] = assignmentId;
    }

    final shiftNeedId = (empMap['shiftNeedId'] ?? '').toString().trim();
    if (shiftNeedId.isNotEmpty) {
      out['shiftNeedId'] = shiftNeedId;
      out['clinicShiftNeedId'] = shiftNeedId;
    }

    return out;
  }

  Future<void> _loadClinicOtPolicy() async {
    if (!mounted || _disposed) return;

    setState(() {
      _loadingOtPolicy = true;
      _otPolicyError = '';
    });

    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) {
        throw Exception('NO_TOKEN');
      }

      final candidates = <String>['/clinic-policy/me', '/api/clinic-policy/me'];

      http.Response? okRes;

      for (final p in candidates) {
        final res = await http.get(_uri(p), headers: _headers(token));

        if (res.statusCode == 200) {
          okRes = res;
          break;
        }

        if (res.statusCode == 401 || res.statusCode == 403) break;
      }

      if (okRes == null) {
        throw Exception('NO_POLICY');
      }

      final decoded = jsonDecode(okRes.body);
      final policyAny = (decoded is Map && decoded['policy'] is Map)
          ? decoded['policy']
          : decoded;

      if (policyAny is! Map) {
        throw Exception('BAD_POLICY');
      }

      final policy = Map<String, dynamic>.from(policyAny);

      final otMulAny = policy['otMultiplier'];
      final holidayMulAny = policy['holidayMultiplier'];

      final otMul = (otMulAny is num)
          ? otMulAny.toDouble()
          : double.tryParse('${otMulAny ?? ''}');

      final holidayMul = (holidayMulAny is num)
          ? holidayMulAny.toDouble()
          : double.tryParse('${holidayMulAny ?? ''}');

      if (!mounted || _disposed) return;

      setState(() {
        _policyOtMultiplier = (otMul != null && otMul > 0)
            ? otMul
            : _defaultOtNormalMultiplier;
        _policyHolidayMultiplier = (holidayMul != null && holidayMul > 0)
            ? holidayMul
            : _defaultOtHolidayMultiplier;
        _loadingOtPolicy = false;
        _otPolicyError = '';
      });
    } catch (_) {
      if (!mounted || _disposed) return;

      setState(() {
        _policyOtMultiplier = _defaultOtNormalMultiplier;
        _policyHolidayMultiplier = _defaultOtHolidayMultiplier;
        _loadingOtPolicy = false;
        _otPolicyError = 'โหลดเงื่อนไข OT ไม่สำเร็จ ระบบใช้ค่าเริ่มต้นชั่วคราว';
      });
    }
  }

  Future<void> _loadClinicPayrollConfig() async {
    if (!mounted || _disposed) return;

    setState(() {
      _loadingClinicPayrollConfig = true;
      _clinicPayrollConfigError = '';
    });

    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) {
        throw Exception('NO_TOKEN');
      }

      final clinicId = await _resolveClinicId();
      if (clinicId == null || clinicId.trim().isEmpty) {
        throw Exception('NO_CLINIC_ID');
      }

      final candidates = <String>[
        '/clinics/$clinicId',
        '/api/clinics/$clinicId',
      ];

      http.Response? okRes;

      for (final p in candidates) {
        final res = await http.get(_uri(p), headers: _headers(token));

        if (res.statusCode == 200) {
          okRes = res;
          break;
        }
      }

      if (okRes == null) {
        throw Exception('NO_OK_RESPONSE');
      }

      final decoded = jsonDecode(okRes.body);
      final clinicAny = (decoded is Map && decoded['clinic'] is Map)
          ? decoded['clinic']
          : decoded;

      if (clinicAny is! Map) {
        throw Exception('BAD_CLINIC_PAYLOAD');
      }

      final clinic = Map<String, dynamic>.from(
        clinicAny.map((k, v) => MapEntry(k.toString(), v)),
      );

      final socialSecurityAny = clinic['socialSecurity'];
      final socialSecurity = socialSecurityAny is Map
          ? Map<String, dynamic>.from(
              socialSecurityAny.map((k, v) => MapEntry(k.toString(), v)),
            )
          : <String, dynamic>{};

      final enabled = socialSecurity.containsKey('enabled')
          ? socialSecurity['enabled'] == true
          : true;

      final rate = (socialSecurity['employeeRate'] is num)
          ? (socialSecurity['employeeRate'] as num).toDouble()
          : double.tryParse('${socialSecurity['employeeRate'] ?? ''}');

      final maxWageBase = (socialSecurity['maxWageBase'] is num)
          ? (socialSecurity['maxWageBase'] as num).toDouble()
          : double.tryParse('${socialSecurity['maxWageBase'] ?? ''}');

      if (!mounted || _disposed) return;

      setState(() {
        _clinicSsoEnabled = enabled;
        _clinicSsoEmployeeRate = (rate != null && rate >= 0) ? rate : 0.05;
        _clinicSsoMaxWageBase = (maxWageBase != null && maxWageBase > 0)
            ? maxWageBase
            : 17500.0;

        ssoPercentCtrl.text = ((_clinicSsoEmployeeRate ?? 0.05) * 100)
            .toStringAsFixed(2);

        _loadingClinicPayrollConfig = false;
        _clinicPayrollConfigError = '';
      });
    } catch (_) {
      if (!mounted || _disposed) return;

      setState(() {
        _loadingClinicPayrollConfig = false;
        _clinicPayrollConfigError =
            'โหลดค่าประกันสังคมของคลินิกไม่สำเร็จ ระบบใช้ค่าเริ่มต้นชั่วคราว';
      });
    }
  }

  Future<void> _loadClosedPayrollForSelectedMonth() async {
    if (!mounted || _disposed) return;

    setState(() {
      _loadingClosedPayroll = true;
      _closedPayrollError = '';
      _closedPayrollRow = null;
      _closedPayslipSummary = null;

      _payrollPreviewError = '';
      _payrollPreviewRow = null;
      _payrollPreviewSummary = null;
      _payrollPreviewInputs = null;
    });

    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) {
        throw Exception('NO_TOKEN');
      }

      final employeeId = _resolveStaffIdForPayroll();
      if (employeeId.isEmpty) {
        throw Exception('NO_EMPLOYEE_ID');
      }

      final monthKey = _fmtMonth(selectedMonth);

      final candidates = <String>[
        '/payroll-close/close-month/$employeeId/$monthKey',
        '/api/payroll-close/close-month/$employeeId/$monthKey',
      ];

      http.Response? okRes;

      for (final p in candidates) {
        final res = await http.get(_uri(p), headers: _headers(token));

        if (res.statusCode == 200) {
          okRes = res;
          break;
        }

        if (res.statusCode == 404) {
          okRes = res;
          break;
        }
      }

      if (okRes == null) {
        throw Exception('NO_RESPONSE');
      }

      if (okRes.statusCode == 404) {
        if (!mounted || _disposed) return;

        setState(() {
          _loadingClosedPayroll = false;
          _closedPayrollError = '';
          _closedPayrollRow = null;
          _closedPayslipSummary = null;
        });

        // ✅ Month is not closed yet.
        // Load backend payroll preview so part-time hours come from Attendance.
        await _loadPayrollPreviewForSelectedMonth();

        return;
      }

      final decoded = jsonDecode(okRes.body);
      final row = _asMap(decoded['row']);
      final payslipSummary = _asMap(decoded['payslipSummary']);

      if (!mounted || _disposed) return;

      setState(() {
        _loadingClosedPayroll = false;
        _closedPayrollError = '';
        _closedPayrollRow = row;
        _closedPayslipSummary = payslipSummary;

        _payrollPreviewError = '';
        _payrollPreviewRow = null;
        _payrollPreviewSummary = null;
        _payrollPreviewInputs = null;
      });
    } catch (_) {
      if (!mounted || _disposed) return;

      setState(() {
        _loadingClosedPayroll = false;
        _closedPayrollError = 'โหลดข้อมูลงวดเงินเดือนไม่สำเร็จ';
        _closedPayrollRow = null;
        _closedPayslipSummary = null;

        _payrollPreviewError = '';
        _payrollPreviewRow = null;
        _payrollPreviewSummary = null;
        _payrollPreviewInputs = null;
      });
    }
  }

  Future<void> _loadPayrollPreviewForSelectedMonth() async {
    if (!mounted || _disposed) return;

    setState(() {
      _loadingPayrollPreview = true;
      _payrollPreviewError = '';
      _payrollPreviewRow = null;
      _payrollPreviewSummary = null;
      _payrollPreviewInputs = null;
    });

    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) {
        throw Exception('NO_TOKEN');
      }

      final clinicId = await _resolveClinicId();
      if (clinicId == null || clinicId.trim().isEmpty) {
        throw Exception('NO_CLINIC_ID');
      }

      final employeeId = _resolveStaffIdForPayroll();
      if (employeeId.isEmpty) {
        throw Exception('NO_EMPLOYEE_ID');
      }

      final monthKey = _fmtMonth(selectedMonth);
      final linkedUserId = _resolveLinkedUserId();

      final monthWorkEntries = _monthWorkEntries(selectedMonth);
      final monthWorkTimeEntries = _monthWorkTimeEntries(selectedMonth);
      final totalWorkHours =
          _sumWorkHours(monthWorkEntries) +
          _sumWorkTimeHours(monthWorkTimeEntries);

      final body = _appendEmployeeIdentityToBody({
        'clinicId': clinicId,
        'employeeId': employeeId,
        'month': monthKey,

        // Backend expects this format.
        'taxMode': _taxMode == _EmployeeTaxMode.withholding
            ? 'WITHHOLDING'
            : 'NO_WITHHOLDING',

        // Full-time uses staff_service salary first; this is fallback only.
        'grossBase': emp.isPartTime ? 0.0 : emp.baseSalary,

        // ✅ Production payroll hint:
        // Backend still uses staff_service as source of truth when available.
        // These fields are fallback only when staff_service is rate-limited/down.
        'employmentType': emp.isPartTime ? 'parttime' : 'fulltime',
        'isPartTime': emp.isPartTime,
        'hourlyRate': emp.isPartTime ? emp.hourlyWage : 0.0,
        'hourlyWage': emp.isPartTime ? emp.hourlyWage : 0.0,

        'bonus': emp.bonus,
        'otherAllowance': 0.0,
        'otherDeduction': emp.isPartTime ? 0.0 : emp.absentDeduction(),
        'pvdEmployeeMonthly': 0.0,

        if (linkedUserId.isNotEmpty) 'employeeUserId': linkedUserId,

        // Migration fallback only. Backend attendance wins for part-time.
        if (emp.isPartTime) 'regularWorkHours': totalWorkHours,
        if (emp.isPartTime) 'regularWorkMinutes': (totalWorkHours * 60).round(),
      });

      final candidates = <String>[
        '/payroll-close/preview/$employeeId/$monthKey',
        '/api/payroll-close/preview/$employeeId/$monthKey',
      ];

      http.Response? okRes;

      for (final p in candidates) {
        final res = await http.post(
          _uri(p),
          headers: _headers(token),
          body: jsonEncode(body),
        );

        if (res.statusCode == 200) {
          okRes = res;
          break;
        }

        if (res.statusCode == 401 || res.statusCode == 403) {
          okRes = res;
          break;
        }
      }

      if (okRes == null) throw Exception('NO_PREVIEW_RESPONSE');

      if (okRes.statusCode != 200) {
        throw Exception('PREVIEW_${okRes.statusCode}');
      }

      final decoded = jsonDecode(okRes.body);
      if (decoded is! Map) throw Exception('BAD_PREVIEW_PAYLOAD');

      final row = _asMap(decoded['row']);
      final payslipSummary = _asMap(decoded['payslipSummary']);
      final payrollInputsResolved = _asMap(decoded['payrollInputsResolved']);

      if (!mounted || _disposed) return;

      setState(() {
        _loadingPayrollPreview = false;
        _payrollPreviewError = '';
        _payrollPreviewRow = row;
        _payrollPreviewSummary = payslipSummary;
        _payrollPreviewInputs = payrollInputsResolved;
      });
    } catch (e) {
      if (!mounted || _disposed) return;

      setState(() {
        _loadingPayrollPreview = false;
        _payrollPreviewError = e.toString().contains('NO_TOKEN')
            ? 'ไม่พบสิทธิ์เข้าใช้งาน กรุณาออกจากระบบแล้วเข้าใหม่'
            : 'โหลดพรีวิวเงินเดือนจาก backend ไม่สำเร็จ';
        _payrollPreviewRow = null;
        _payrollPreviewSummary = null;
        _payrollPreviewInputs = null;
      });
    }
  }

  Future<void> _recalculateClosedPayrollForSelectedMonth() async {
    if (_recalculatingClosedPayroll) return;

    final employeeId = _resolveStaffIdForPayroll();
    final monthKey = _fmtMonth(selectedMonth);

    if (employeeId.isEmpty) {
      _snack('ไม่พบข้อมูลพนักงานสำหรับคำนวณเงินเดือน');
      return;
    }

    if (_closedPayrollRow == null || _closedPayslipSummary == null) {
      _snack('ยังไม่พบงวดที่ปิดแล้วสำหรับเดือนนี้');
      return;
    }

    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('คำนวณงวดนี้ใหม่?'),
        content: Text(
          'งวด $monthKey ถูกปิดแล้ว\n\n'
          'หากมีการสแกนเวลา OT หรือข้อมูลเงินเดือนเปลี่ยนหลังปิดงวด '
          'ระบบจะยกเลิกยอดเดิมและคำนวณงวดนี้ใหม่จากข้อมูลล่าสุด\n\n'
          'ต้องการดำเนินการหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            onPressed: () => Navigator.of(ctx).pop(true),
            label: const Text('คำนวณใหม่'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (!mounted || _disposed) return;

    final monthWorkEntries = _monthWorkEntries(selectedMonth);
    final monthWorkTimeEntries = _monthWorkTimeEntries(selectedMonth);
    final totalWorkHours =
        _sumWorkHours(monthWorkEntries) +
        _sumWorkTimeHours(monthWorkTimeEntries);

    final linkedUserId = _resolveLinkedUserId();

    setState(() => _recalculatingClosedPayroll = true);

    try {
      await PayrollCloseApi.recalculateClosedMonth(
        employeeId: employeeId,
        month: monthKey,
        grossBase: emp.isPartTime ? null : emp.baseSalary,
        bonus: emp.bonus,
        otherAllowance: 0,
        otherDeduction: emp.isPartTime ? 0.0 : emp.absentDeduction(),
        pvdEmployeeMonthly: 0,
        taxMode: _taxMode == _EmployeeTaxMode.withholding
            ? 'WITHHOLDING'
            : 'NO_WITHHOLDING',
        employeeUserId: linkedUserId.isEmpty ? null : linkedUserId,
        regularWorkHours: emp.isPartTime ? totalWorkHours : null,
        regularWorkMinutes: emp.isPartTime
            ? (totalWorkHours * 60).round()
            : null,
      );

      if (!mounted || _disposed) return;

      _snack('คำนวณงวด $monthKey ใหม่สำเร็จ ✅');

      await _loadBackendOtForSelectedMonth();
      await _loadClosedPayrollForSelectedMonth();
    } catch (e) {
      if (!mounted || _disposed) return;

      final msg = e.toString();

      if (msg.contains('404')) {
        _snack('ไม่พบงวดเงินเดือนที่ปิดแล้ว');
      } else if (msg.contains('401')) {
        _snack('สิทธิ์หมดอายุ กรุณาออกจากระบบแล้วเข้าใหม่');
      } else if (msg.contains('403')) {
        _snack('ไม่มีสิทธิ์คำนวณงวดใหม่');
      } else {
        _snack('คำนวณงวดใหม่ไม่สำเร็จ');
      }
    } finally {
      if (!mounted || _disposed) return;
      setState(() => _recalculatingClosedPayroll = false);
    }
  }

  List<DateTime> _buildMonthList({int back = 24, int forward = 6}) {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, 1);
    final out = <DateTime>[];

    for (int i = back; i >= 1; i--) {
      out.add(DateTime(base.year, base.month - i, 1));
    }

    out.add(base);

    for (int i = 1; i <= forward; i++) {
      out.add(DateTime(base.year, base.month + i, 1));
    }

    return out;
  }

  Future<DateTime?> _pickMonthDialog() async {
    final options = _buildMonthList(back: 36, forward: 0);
    final currentKey = _fmtMonth(selectedMonth);

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('เลือกเดือน'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final m = options[i];
              final key = _fmtMonth(m);
              final selected = key == currentKey;

              return ListTile(
                dense: true,
                title: Text(key),
                trailing: selected ? const Icon(Icons.check_circle) : null,
                onTap: () => Navigator.pop(context, m),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );

    return picked;
  }

  Future<void> _pickMonth() async {
    final picked = await _pickMonthDialog();
    if (picked == null) return;
    if (!mounted || _disposed) return;

    setState(() {
      selectedMonth = DateTime(picked.year, picked.month, 1);
      otDate = null;
      otStart = null;
      otEnd = null;
      isHolidayX2 = false;
    });

    await _loadWorkEntriesIfNeeded();
    await _loadBackendOtForSelectedMonth();
    await _loadClosedPayrollForSelectedMonth();

    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  List<Map<String, dynamic>> _extractOtRowsFromResponseBody(dynamic decoded) {
    dynamic data = decoded;

    if (decoded is Map && decoded['data'] != null) {
      data = decoded['data'];
    }

    List rows = [];

    if (data is List) {
      rows = data;
    } else if (data is Map) {
      if (data['rows'] is List) {
        rows = data['rows'];
      } else if (data['items'] is List) {
        rows = data['items'];
      } else if (data['data'] is List) {
        rows = data['data'];
      }
    } else if (decoded is Map) {
      if (decoded['rows'] is List) {
        rows = decoded['rows'];
      } else if (decoded['items'] is List) {
        rows = decoded['items'];
      }
    }

    final parsed = <Map<String, dynamic>>[];

    for (final r in rows) {
      if (r is Map) {
        parsed.add(
          Map<String, dynamic>.from(r.map((k, v) => MapEntry(k.toString(), v))),
        );
      }
    }

    return parsed;
  }

  Future<void> _loadBackendOtForSelectedMonth() async {
    if (!mounted || _disposed) return;

    setState(() {
      _loadingBackendOt = true;
      _backendOtError = '';
      _backendOtRows = [];
      _backendApprovedMinutes = 0;
      _backendApprovedWeightedHours = 0.0;
      _backendApprovedCount = 0;
    });

    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) throw Exception('NO_TOKEN');

      final monthKey = _fmtMonth(selectedMonth);
      final staffId = _resolveStaffIdForPayroll();

      if (staffId.isEmpty) throw Exception('NO_STAFF_ID');

      final statusParam =
          (_backendOtStatus.trim().isEmpty || _backendOtStatus == 'all')
          ? ''
          : '&status=${Uri.encodeQueryComponent(_backendOtStatus)}';

      final candidates = <String>[
        '/overtime?month=$monthKey&principalId=$staffId$statusParam',
        '/overtime?month=$monthKey&staffId=$staffId$statusParam',
        '/api/overtime?month=$monthKey&principalId=$staffId$statusParam',
        '/api/overtime?month=$monthKey&staffId=$staffId$statusParam',
        '/overtime/my?month=$monthKey${statusParam.isEmpty ? '' : statusParam.replaceFirst('&', '&')}',
        '/api/overtime/my?month=$monthKey${statusParam.isEmpty ? '' : statusParam.replaceFirst('&', '&')}',
      ];

      http.Response? chosenRes;
      List<Map<String, dynamic>> chosenRows = [];

      for (final path in candidates) {
        final res = await http.get(_uri(path), headers: _headers(token));

        if (res.statusCode != 200) continue;

        try {
          final decoded = jsonDecode(res.body);
          final rows = _extractOtRowsFromResponseBody(decoded);

          if (rows.isNotEmpty) {
            chosenRes = res;
            chosenRows = rows;
            break;
          }

          chosenRes ??= res;
          chosenRows = rows;
        } catch (_) {
          chosenRes ??= res;
        }
      }

      if (chosenRes == null) throw Exception('NO_OK_RESPONSE');

      int minutes = 0;
      double weightedHours = 0.0;
      int count = 0;

      for (final r in chosenRows) {
        final st = (r['status'] ?? '').toString().trim().toLowerCase();
        if (st != 'approved' && st != 'locked') continue;

        final approvedAny = r['approvedMinutes'];
        final minutesAny = r['minutes'];

        final m = approvedAny is num
            ? approvedAny.toInt()
            : int.tryParse('${approvedAny ?? minutesAny}') ??
                  (minutesAny is num ? minutesAny.toInt() : 0);

        final mul = (r['multiplier'] is num)
            ? (r['multiplier'] as num).toDouble()
            : double.tryParse('${r['multiplier']}') ?? _normalOtMultiplier;

        final safeMinutes = m < 0 ? 0 : m;
        final safeMul = mul <= 0 ? _normalOtMultiplier : mul;

        minutes += safeMinutes;
        weightedHours += (safeMinutes / 60.0) * safeMul;
        count += 1;
      }

      if (!mounted || _disposed) return;

      setState(() {
        _backendOtRows = chosenRows;
        _backendApprovedMinutes = minutes;
        _backendApprovedWeightedHours = weightedHours;
        _backendApprovedCount = count;
        _loadingBackendOt = false;
      });
    } catch (e) {
      if (!mounted || _disposed) return;

      setState(() {
        _loadingBackendOt = false;
        _backendOtError = e.toString().contains('NO_TOKEN')
            ? 'ไม่พบสิทธิ์เข้าใช้งาน กรุณาออกจากระบบแล้วเข้าใหม่'
            : e.toString().contains('NO_STAFF_ID')
            ? 'ไม่พบข้อมูลพนักงานสำหรับโหลด OT'
            : 'โหลด OT จากระบบไม่สำเร็จ';
      });
    }
  }

  int _minutesBetween(String startHHmm, String endHHmm) {
    final s = startHHmm.trim().split(':');
    final e = endHHmm.trim().split(':');

    if (s.length < 2 || e.length < 2) return 0;

    final sh = int.tryParse(s[0]) ?? 0;
    final sm = int.tryParse(s[1]) ?? 0;
    final eh = int.tryParse(e[0]) ?? 0;
    final em = int.tryParse(e[1]) ?? 0;

    final safeSh = sh.clamp(0, 23).toInt();
    final safeSm = sm.clamp(0, 59).toInt();
    final safeEh = eh.clamp(0, 23).toInt();
    final safeEm = em.clamp(0, 59).toInt();

    final startMin = safeSh * 60 + safeSm;
    var endMin = safeEh * 60 + safeEm;

    if (endMin < startMin) endMin += 24 * 60;

    final diff = endMin - startMin;
    return diff < 0 ? 0 : diff;
  }

  String _extractBackendMessage(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final keys = ['message', 'error', 'code'];
        for (final k in keys) {
          final v = decoded[k];
          if (v != null && v.toString().trim().isNotEmpty) {
            return v.toString().trim();
          }
        }
      }
    } catch (_) {}

    return '';
  }

  String _extractSavedOtStatus(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final overtime = decoded['overtime'];
        if (overtime is Map) {
          final st = (overtime['status'] ?? '').toString().trim().toLowerCase();
          if (st.isNotEmpty) return st;
        }

        final data = decoded['data'];
        if (data is Map) {
          final st = (data['status'] ?? '').toString().trim().toLowerCase();
          if (st.isNotEmpty) return st;
        }

        final st = (decoded['status'] ?? '').toString().trim().toLowerCase();
        if (st.isNotEmpty) return st;
      }
    } catch (_) {}

    return 'approved';
  }

  String _friendlyManualOtError({
    required int statusCode,
    required String backendMessage,
  }) {
    if (statusCode == 409) {
      return 'มีรายการ OT ของวันนี้อยู่แล้ว กรุณาลบหรือแก้ไขรายการเดิมก่อน';
    }

    if (statusCode == 400) {
      return backendMessage.isNotEmpty
          ? backendMessage
          : 'ข้อมูล OT ไม่ถูกต้อง';
    }

    if (statusCode == 401) {
      return 'สิทธิ์หมดอายุ กรุณาออกจากระบบแล้วเข้าใหม่';
    }

    if (statusCode == 403) {
      return 'ไม่มีสิทธิ์บันทึก OT';
    }

    if (statusCode == 404) {
      return 'ยังไม่สามารถเชื่อมต่อระบบบันทึก OT ได้';
    }

    if (statusCode >= 500) {
      return 'ระบบมีปัญหา กรุณาลองใหม่อีกครั้ง';
    }

    return backendMessage.isNotEmpty
        ? backendMessage
        : 'บันทึก OT เข้าระบบไม่สำเร็จ';
  }

  Future<_ManualOtSaveResult> _createOtManualViaApi({
    required String staffId,
    required String workDate,
    required String startHHmm,
    required String endHHmm,
    required double multiplier,
  }) async {
    if (staffId.trim().isEmpty) {
      return const _ManualOtSaveResult(
        ok: false,
        statusCode: 0,
        message: 'ไม่พบข้อมูลพนักงานสำหรับบันทึก OT',
      );
    }

    final token = await _getToken();
    if (token == null || token.trim().isEmpty) {
      return const _ManualOtSaveResult(
        ok: false,
        statusCode: 401,
        message: 'ไม่พบสิทธิ์เข้าใช้งาน กรุณาออกจากระบบแล้วเข้าใหม่',
      );
    }

    final minutes = _minutesBetween(startHHmm, endHHmm);
    if (minutes <= 0) {
      return const _ManualOtSaveResult(
        ok: false,
        statusCode: 400,
        message: 'ช่วงเวลา OT ไม่ถูกต้อง',
      );
    }

    final body = _appendEmployeeIdentityToBody({
      'workDate': workDate,
      'date': workDate,
      'start': startHHmm,
      'end': endHHmm,
      'startTime': startHHmm,
      'endTime': endHHmm,
      'minutes': minutes,
      'approvedMinutes': minutes,
      'multiplier': multiplier,
      'source': 'manual',
      'status': 'approved',
      'note': 'Admin manual OT',
      'asPending': false,
    });

    final candidates = <String>['/overtime/manual', '/api/overtime/manual'];

    int lastStatusCode = 0;
    String lastMessage = '';

    for (final p in candidates) {
      try {
        final res = await http.post(
          _uri(p),
          headers: _headers(token),
          body: jsonEncode(body),
        );

        lastStatusCode = res.statusCode;
        lastMessage = _extractBackendMessage(res);

        if (res.statusCode == 200 || res.statusCode == 201) {
          final savedStatus = _extractSavedOtStatus(res.body);
          return _ManualOtSaveResult(
            ok: true,
            statusCode: res.statusCode,
            message: 'บันทึก OT เข้าระบบแล้ว',
            savedStatus: savedStatus,
          );
        }

        if (res.statusCode == 409 ||
            res.statusCode == 400 ||
            res.statusCode == 401 ||
            res.statusCode == 403) {
          final friendly = _friendlyManualOtError(
            statusCode: res.statusCode,
            backendMessage: lastMessage,
          );

          return _ManualOtSaveResult(
            ok: false,
            statusCode: res.statusCode,
            message: friendly,
          );
        }

        if (res.statusCode == 404) {
          continue;
        }
      } catch (e) {
        lastMessage = e.toString();
      }
    }

    final friendly = _friendlyManualOtError(
      statusCode: lastStatusCode,
      backendMessage: lastMessage,
    );

    return _ManualOtSaveResult(
      ok: false,
      statusCode: lastStatusCode,
      message: friendly,
    );
  }

  Future<bool> _approveOtViaApi(String id) async {
    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) return false;

      final candidates = <String>[
        '/overtime/$id/approve',
        '/api/overtime/$id/approve',
      ];

      for (final p in candidates) {
        final res = await http.patch(_uri(p), headers: _headers(token));
        if (res.statusCode == 200) return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _rejectOtViaApi(String id) async {
    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) return false;

      final candidates = <String>[
        '/overtime/$id/reject',
        '/api/overtime/$id/reject',
      ];

      for (final p in candidates) {
        final res = await http.patch(_uri(p), headers: _headers(token));
        if (res.statusCode == 200) return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _bulkApproveMonthViaApi({
    required String month,
    required String staffId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) return false;

      if (staffId.trim().isEmpty) return false;

      final body = _appendEmployeeIdentityToBody({'month': month});

      final candidates = <String>[
        '/overtime/bulk-approve/month',
        '/api/overtime/bulk-approve/month',
      ];

      for (final p in candidates) {
        final res = await http.patch(
          _uri(p),
          headers: _headers(token),
          body: jsonEncode(body),
        );

        if (res.statusCode == 200) return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deleteOtViaApi(String id) async {
    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) return false;

      final candidates = <String>['/overtime/$id', '/api/overtime/$id'];

      for (final p in candidates) {
        final res = await http.delete(_uri(p), headers: _headers(token));
        if (res.statusCode == 200) return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _goEditEmployee() async {
    if (!mounted || _disposed) return;

    if (!_isEditUnlocked) {
      final ok = await _promptForPin();
      if (!mounted || _disposed) return;

      if (!ok) {
        _snack('รหัสไม่ถูกต้อง');
        return;
      }

      Future.microtask(() {
        if (!mounted || _disposed) return;
        setState(() => _isEditUnlocked = true);
      });
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditEmployeeScreen(employee: emp)),
    );

    if (!mounted || _disposed) return;

    if (result is EmployeeModel) {
      setState(() => emp = result);
      _snack('อัปเดตข้อมูลพนักงานแล้ว');

      await _loadClinicOtPolicy();
      await _loadClinicPayrollConfig();
      await _loadBackendOtForSelectedMonth();
      await _loadClosedPayrollForSelectedMonth();
      await _initTaxSettingsFromPrefs();
    }
  }

  Future<void> _toggleEditLock() async {
    if (_isEditUnlocked) {
      Future.microtask(() {
        if (!mounted || _disposed) return;
        setState(() => _isEditUnlocked = false);
        _snack('ล็อกโหมดแก้ไขแล้ว');
      });

      return;
    }

    final ok = await _promptForPin();
    if (!mounted || _disposed) return;

    Future.microtask(() {
      if (!mounted || _disposed) return;

      if (ok) {
        setState(() => _isEditUnlocked = true);
        _snack('ปลดล็อกโหมดแก้ไขแล้ว');
      } else {
        _snack('รหัสไม่ถูกต้อง');
      }
    });
  }

  Future<void> _setOrChangePin() async {
    final prefs = await SharedPreferences.getInstance();
    final oldPin = (prefs.getString('app_edit_pin') ?? '').trim();

    if (oldPin.isEmpty) {
      final ok = await _promptSetNewPin();
      if (!mounted || _disposed) return;
      _snack(ok ? 'ตั้งรหัส PIN แล้ว' : 'ยกเลิก');
      return;
    }

    final verified = await _promptVerifyPin(oldPin, title: 'ยืนยันรหัสเดิม');
    if (!mounted || _disposed) return;

    if (!verified) {
      _snack('รหัสเดิมไม่ถูกต้อง');
      return;
    }

    final ok = await _promptSetNewPin();
    if (!mounted || _disposed) return;
    _snack(ok ? 'เปลี่ยนรหัส PIN แล้ว' : 'ยกเลิก');
  }

  Future<bool> _promptForPin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = (prefs.getString('app_edit_pin') ?? '').trim();

    if (savedPin.isEmpty) {
      final setOk = await _promptSetNewPin();
      return setOk;
    }

    return _promptVerifyPin(savedPin);
  }

  Future<bool> _promptVerifyPin(
    String savedPin, {
    String title = 'ใส่รหัสเพื่อปลดล็อก',
  }) async {
    final TextEditingController pinCtrl = TextEditingController();
    bool submitted = false;

    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        void closeWith(bool v) {
          if (submitted) return;
          submitted = true;

          FocusScope.of(ctx).unfocus();
          Navigator.of(ctx, rootNavigator: true).pop(v);
        }

        void submit() {
          final pass = pinCtrl.text.trim() == savedPin;
          closeWith(pass);
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: pinCtrl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'PIN',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => closeWith(false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(onPressed: submit, child: const Text('ยืนยัน')),
          ],
        );
      },
    );

    return ok == true;
  }

  Future<bool> _promptSetNewPin() async {
    final TextEditingController p1 = TextEditingController();
    final TextEditingController p2 = TextEditingController();
    bool submitted = false;

    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        void closeWith(bool v) {
          if (submitted) return;
          submitted = true;

          FocusScope.of(ctx).unfocus();
          Navigator.of(ctx, rootNavigator: true).pop(v);
        }

        Future<void> submit() async {
          final a = p1.text.trim();
          final b = p2.text.trim();

          if (a.length < 4) {
            if (!mounted || _disposed) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PIN ต้องมีอย่างน้อย 4 หลัก')),
            );
            return;
          }

          if (a != b) {
            if (!mounted || _disposed) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('PIN ไม่ตรงกัน')));
            return;
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('app_edit_pin', a);

          closeWith(true);
        }

        return AlertDialog(
          title: const Text('ตั้งรหัส PIN ใหม่'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: p1,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'PIN ใหม่ (อย่างน้อย 4 หลัก)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: p2,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'ยืนยัน PIN ใหม่',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => closeWith(false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(onPressed: submit, child: const Text('บันทึก')),
          ],
        );
      },
    );

    return ok == true;
  }

  Future<void> _initTaxSettingsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawMode = (prefs.getString(_employeeTaxModeKey) ?? 'none').trim();
    final p =
        prefs.getDouble(_employeeWithholdingPercentKey) ??
        _defaultWithholdingPercent;

    if (!mounted || _disposed) return;

    setState(() {
      _taxMode = rawMode == 'withholding'
          ? _EmployeeTaxMode.withholding
          : _EmployeeTaxMode.none;
      withholdingPercentCtrl.text = p.toStringAsFixed(2);
    });
  }

  double _getWithholdingPercent() {
    final v = double.tryParse(withholdingPercentCtrl.text.trim());
    if (v == null || v < 0) return _defaultWithholdingPercent;
    return v;
  }

  Future<void> _saveSsoPercentFromUI() async {
    if (_savingSso) return;

    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    final percent = double.tryParse(ssoPercentCtrl.text.trim());

    if (percent == null || percent < 0 || percent > 100) {
      _snack('กรุณาใส่ % ให้ถูกต้อง (เช่น 5.00)');
      return;
    }

    final rateDecimal = percent / 100.0;

    if (!mounted || _disposed) return;
    setState(() => _savingSso = true);

    try {
      final token = await _getToken();

      if (token == null || token.trim().isEmpty) {
        throw Exception('NO_TOKEN');
      }

      final body = {
        'socialSecurityEnabled': true,
        'socialSecurityEmployeeRate': rateDecimal,
        'socialSecurityMaxWageBase': _effectiveClinicSsoMaxWageBase,
      };

      final candidates = <String>[
        '/clinics/me/profile',
        '/api/clinics/me/profile',
      ];

      http.Response? okRes;

      for (final p in candidates) {
        final res = await http.patch(
          _uri(p),
          headers: _headers(token),
          body: jsonEncode(body),
        );

        if (res.statusCode == 200) {
          okRes = res;
          break;
        }
      }

      if (okRes == null) {
        throw Exception('SAVE_FAILED');
      }

      if (!mounted || _disposed) return;

      setState(() {
        _clinicSsoEnabled = true;
        _clinicSsoEmployeeRate = rateDecimal;
      });

      _snack('บันทึกค่า SSO ของคลินิกแล้ว');
      await _loadClosedPayrollForSelectedMonth();
    } catch (_) {
      _snack('บันทึกค่า SSO ไม่สำเร็จ');
    } finally {
      if (!mounted || _disposed) return;
      setState(() => _savingSso = false);
    }
  }

  Future<void> _saveTaxSettingsFromUI() async {
    if (_savingTax) return;

    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    final pct = _getWithholdingPercent();

    if (_taxMode == _EmployeeTaxMode.withholding && (pct <= 0 || pct > 100)) {
      _snack('กรุณาใส่อัตราหักภาษีให้ถูกต้อง');
      return;
    }

    if (!mounted || _disposed) return;
    setState(() => _savingTax = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        _employeeTaxModeKey,
        _taxMode == _EmployeeTaxMode.withholding ? 'withholding' : 'none',
      );

      await prefs.setDouble(_employeeWithholdingPercentKey, pct);

      if (!mounted || _disposed) return;

      FocusScope.of(context).unfocus();
      setState(() {});
      _snack('บันทึกรูปแบบภาษีแล้ว');

      await _loadClosedPayrollForSelectedMonth();
    } catch (_) {
      _snack('บันทึกไม่สำเร็จ');
    } finally {
      if (!mounted || _disposed) return;
      setState(() => _savingTax = false);
    }
  }

  Widget _taxModeCard({
    required double totalMonthPayBeforeTax,
    required double withholdingAmount,
    required double netAfterTax,
    required bool hasClosedPayroll,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('รูปแบบภาษี', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        DropdownButtonFormField<_EmployeeTaxMode>(
          initialValue: _taxMode,
          decoration: const InputDecoration(
            labelText: 'เลือกการหักภาษี',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: _EmployeeTaxMode.none,
              child: Text('ไม่หักภาษี'),
            ),
            DropdownMenuItem(
              value: _EmployeeTaxMode.withholding,
              child: Text('หักภาษี ณ ที่จ่าย'),
            ),
          ],
          onChanged: hasClosedPayroll
              ? null
              : !_isEditUnlocked
              ? null
              : (v) async {
                  if (v == null) return;
                  if (!mounted || _disposed) return;
                  setState(() => _taxMode = v);
                  await _loadClosedPayrollForSelectedMonth();
                },
        ),
        const SizedBox(height: 10),
        if (_taxMode == _EmployeeTaxMode.withholding) ...[
          TextField(
            controller: withholdingPercentCtrl,
            enabled: !hasClosedPayroll && _isEditUnlocked && !_savingTax,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_decimalFormatter],
            decoration: const InputDecoration(
              labelText: 'อัตราหักภาษี (%)',
              hintText: 'เช่น 3.00',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: hasClosedPayroll || _savingTax
                ? null
                : _saveTaxSettingsFromUI,
            child: Text(_savingTax ? 'กำลังบันทึก...' : 'บันทึกรูปแบบภาษี'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _taxMode == _EmployeeTaxMode.none
              ? 'ภาษี: ไม่หัก'
              : 'ภาษีหัก ณ ที่จ่าย: -${withholdingAmount.toStringAsFixed(2)} บาท',
        ),
        Text(
          'สุทธิหลังภาษี: ${netAfterTax.toStringAsFixed(2)} บาท',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'ฐานคำนวณสุทธิก่อนภาษี: ${totalMonthPayBeforeTax.toStringAsFixed(2)} บาท',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        if (hasClosedPayroll)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'เดือนนี้ปิดงวดแล้ว ระบบแสดงค่าภาษีจากงวดที่ปิดแล้ว',
              style: TextStyle(fontSize: 12),
            ),
          )
        else if (!_isEditUnlocked)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'หมายเหตุ: ต้องปลดล็อกโหมดแก้ไขก่อนถึงจะเปลี่ยนรูปแบบภาษีได้',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _identityCard() {
    final staffId = _resolveStaffIdForPayroll();
    final ready = staffId.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ready ? Icons.check_circle_outline : Icons.info_outline,
              color: ready ? Colors.green.shade700 : Colors.orange.shade700,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ระบบเงินเดือนและ OT',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ready
                        ? 'ข้อมูลพนักงานนี้พร้อมใช้งานกับระบบเงินเดือนและ OT แล้ว\nสามารถเลือกเมนูที่ต้องการได้เลย'
                        : 'ข้อมูลพนักงานนี้ยังไม่พร้อมใช้งานกับระบบเงินเดือนและ OT\nกรุณาตรวจสอบหรือแก้ไขข้อมูลพนักงานก่อนใช้งาน',
                    style: TextStyle(
                      height: 1.35,
                      color: ready
                          ? Colors.grey.shade800
                          : Colors.orange.shade800,
                      fontWeight: ready ? FontWeight.w600 : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTaxSummaryOrPreview({
    required bool isParttime,
    required double grossBaseFallback,
    required double leaveDeductionInput,
    required double regularWorkHoursInput,
  }) async {
    try {
      final clinicId = await _resolveClinicId();
      if (!mounted) return;

      if (clinicId == null || clinicId.trim().isEmpty) {
        _snack('ไม่พบข้อมูลคลินิก กรุณาออกจากระบบแล้วเข้าใหม่');
        return;
      }

      final staffId = _resolveStaffIdForPayroll();

      if (staffId.isEmpty) {
        _snack('ไม่พบข้อมูลพนักงานสำหรับดูพรีวิวสลิปหรือปิดงวด');
        return;
      }

      final linkedUserId = _resolveLinkedUserId();

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PayrollAfterTaxPreviewScreen(
            grossMonthly: isParttime ? 0.0 : grossBaseFallback,
            year: selectedMonth.year,
            clinicId: clinicId,
            employeeId: staffId,
            ssoEmployeeMonthly: 0,
            otPay: 0,
            bonus: emp.bonus,
            otherAllowance: 0,
            otherDeduction: isParttime ? 0.0 : leaveDeductionInput,
            pvdEmployeeMonthly: 0,
            closeMonth: _fmtCloseMonth(selectedMonth),
            taxMode: _taxMode == _EmployeeTaxMode.withholding
                ? 'withholding'
                : 'none',
            withholdingPercent: _taxMode == _EmployeeTaxMode.withholding
                ? _getWithholdingPercent()
                : 0,
            withholdingAmount: null,
            detailNetBeforeOt: 0,
            detailLeaveDeduction: 0,
            detailOtAmount: 0,
            detailGrossBeforeTax: 0,
            detailSsoAmount: 0,
            detailTaxAmount: 0,
            detailNetPay: 0,
            detailOtHours: 0,
            employeeUserId: linkedUserId.isEmpty ? null : linkedUserId,
            regularWorkHours: isParttime ? regularWorkHoursInput : null,
            regularWorkMinutes: isParttime
                ? (regularWorkHoursInput * 60).round()
                : null,
            workItems: null,
          ),
        ),
      );

      if (!mounted || _disposed) return;

      await _loadBackendOtForSelectedMonth();
      await _loadClosedPayrollForSelectedMonth();
    } catch (_) {
      if (!mounted) return;
      _snack('เปิดหน้าพรีวิวสลิปไม่สำเร็จ กรุณาลองออกจากระบบแล้วเข้าใหม่');
    }
  }

  Future<String?> _resolveClinicId() async {
    final fromWidget = widget.clinicId.trim();
    if (fromWidget.isNotEmpty) return fromWidget;

    final prefs = await SharedPreferences.getInstance();

    final candidates = <String>[
      (prefs.getString('app_clinic_id') ?? '').trim(),
      (prefs.getString('clinicId') ?? '').trim(),
      (prefs.getString('clinic_id') ?? '').trim(),
      (prefs.getString('selected_clinic_id') ?? '').trim(),
    ].where((s) => s.isNotEmpty).toList();

    if (candidates.isNotEmpty) return candidates.first;
    return null;
  }

  String get _workEntriesKey => 'work_entries_${emp.id}';

  String get _workTimeEntriesKey => 'work_time_entries_${emp.id}';

  Future<void> _loadWorkEntriesIfNeeded() async {
    if (!emp.isPartTime) return;

    if (!mounted || _disposed) return;
    setState(() => _workEntriesLoaded = false);

    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_workEntriesKey);
    List<WorkHourEntry> legacy = [];

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is List) {
          for (final it in decoded) {
            if (it is Map) {
              final m = it.map((k, v) => MapEntry(k.toString(), v));
              legacy.add(WorkHourEntry.fromMap(Map<String, dynamic>.from(m)));
            }
          }
        }
      } catch (_) {}
    }

    final raw2 = prefs.getString(_workTimeEntriesKey);
    List<WorkTimeEntry> timeList = [];

    if (raw2 != null && raw2.trim().isNotEmpty) {
      try {
        final decoded2 = jsonDecode(raw2);

        if (decoded2 is List) {
          for (final it in decoded2) {
            if (it is Map) {
              final m = it.map((k, v) => MapEntry(k.toString(), v));
              timeList.add(WorkTimeEntry.fromMap(Map<String, dynamic>.from(m)));
            }
          }
        }
      } catch (_) {}
    }

    if (!mounted || _disposed) return;

    setState(() {
      _allWorkEntries = legacy;
      _allWorkTimeEntries = timeList;
      _workEntriesLoaded = true;
    });
  }

  Future<void> _persistWorkEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(_allWorkEntries.map((e) => e.toMap()).toList());
    await prefs.setString(_workEntriesKey, payload);
  }

  Future<void> _persistWorkTimeEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      _allWorkTimeEntries.map((e) => e.toMap()).toList(),
    );
    await prefs.setString(_workTimeEntriesKey, payload);
  }

  List<WorkHourEntry> _monthWorkEntries(DateTime month) {
    return _allWorkEntries
        .where((e) => e.isInMonth(month.year, month.month))
        .toList();
  }

  List<WorkTimeEntry> _monthWorkTimeEntries(DateTime month) {
    return _allWorkTimeEntries
        .where((e) => e.isInMonth(month.year, month.month))
        .toList();
  }

  double _sumWorkHours(List<WorkHourEntry> list) {
    double total = 0;

    for (final e in list) {
      total += e.hours;
    }

    return total;
  }

  double _sumWorkTimeHours(List<WorkTimeEntry> list) {
    double total = 0;

    for (final e in list) {
      total += e.hours;
    }

    return total;
  }

  Future<void> _pickWorkDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: workDate ?? now,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'เลือกวันที่ทำงาน',
    );

    if (picked == null) return;
    if (!mounted || _disposed) return;

    setState(() => workDate = picked);
  }

  Future<void> _addWorkEntry() async {
    if (!emp.isPartTime) return;

    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (workDate == null) {
      _snack('กรุณาเลือกวันที่');
      return;
    }

    final hours = double.tryParse(workHoursCtrl.text.trim());

    if (hours == null || hours <= 0 || hours > 24) {
      _snack('กรุณาใส่ชั่วโมงให้ถูกต้อง (เช่น 8.00)');
      return;
    }

    final entry = WorkHourEntry(date: _fmtDate(workDate!), hours: hours);

    if (!mounted || _disposed) return;

    setState(() {
      _allWorkEntries.add(entry);
      workDate = null;
      workHoursCtrl.text = '';
    });

    await _persistWorkEntries();
    await _loadWorkEntriesIfNeeded();
    await _loadClosedPayrollForSelectedMonth();

    _snack('บันทึกชั่วโมงทำงานแล้ว (${hours.toStringAsFixed(2)} ชม.)');
  }

  Future<void> _deleteWorkEntry(
    int indexInMonth,
    List<WorkHourEntry> monthList,
  ) async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (indexInMonth < 0 || indexInMonth >= monthList.length) return;

    final target = monthList[indexInMonth];

    if (!mounted || _disposed) return;

    setState(() {
      _allWorkEntries.removeWhere(
        (e) => e.date == target.date && e.hours == target.hours,
      );
    });

    await _persistWorkEntries();
    await _loadWorkEntriesIfNeeded();
    await _loadClosedPayrollForSelectedMonth();

    _snack('ลบรายการชั่วโมงทำงานแล้ว');
  }

  Future<void> _pickWorkTimeDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: workTimeDate ?? now,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'เลือกวันที่ทำงาน (แบบเวลาเริ่ม-จบ)',
    );

    if (picked == null) return;
    if (!mounted || _disposed) return;

    setState(() => workTimeDate = picked);
  }

  Future<void> _pickWorkStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: workStart ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: 'เวลาเริ่มงาน',
    );

    if (picked == null) return;
    if (!mounted || _disposed) return;

    setState(() => workStart = picked);
  }

  Future<void> _pickWorkEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: workEnd ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: 'เวลาจบงาน',
    );

    if (picked == null) return;
    if (!mounted || _disposed) return;

    setState(() => workEnd = picked);
  }

  int _parseBreakMinutes() {
    final v = breakMinutesCtrl.text.trim();
    final n = int.tryParse(v) ?? 0;

    if (n < 0) return 0;
    if (n > 8 * 60) return 8 * 60;

    return n;
  }

  Future<void> _addWorkTimeEntry() async {
    if (!emp.isPartTime) return;

    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (workTimeDate == null) {
      _snack('กรุณาเลือกวันที่');
      return;
    }

    if (workStart == null || workEnd == null) {
      _snack('กรุณาเลือกเวลาเริ่ม/เวลาจบ');
      return;
    }

    final entry = WorkTimeEntry(
      date: _fmtDate(workTimeDate!),
      start: _fmtTOD(workStart!),
      end: _fmtTOD(workEnd!),
      breakMinutes: _parseBreakMinutes(),
    );

    final h = entry.hours;

    if (h <= 0 || h > 24) {
      _snack('ช่วงเวลาไม่ถูกต้อง');
      return;
    }

    if (!mounted || _disposed) return;

    setState(() {
      _allWorkTimeEntries.add(entry);
      workTimeDate = null;
      workStart = null;
      workEnd = null;
      breakMinutesCtrl.text = '0';
    });

    await _persistWorkTimeEntries();
    await _loadWorkEntriesIfNeeded();
    await _loadClosedPayrollForSelectedMonth();

    _snack('บันทึกเวลาแล้ว (${h.toStringAsFixed(2)} ชม.)');
  }

  Future<void> _deleteWorkTimeEntry(
    int indexInMonth,
    List<WorkTimeEntry> monthList,
  ) async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (indexInMonth < 0 || indexInMonth >= monthList.length) return;

    final target = monthList[indexInMonth];

    if (!mounted || _disposed) return;

    setState(() {
      _allWorkTimeEntries.removeWhere(
        (e) =>
            e.date == target.date &&
            e.start == target.start &&
            e.end == target.end &&
            e.breakMinutes == target.breakMinutes,
      );
    });

    await _persistWorkTimeEntries();
    await _loadWorkEntriesIfNeeded();
    await _loadClosedPayrollForSelectedMonth();

    _snack('ลบรายการเวลาแล้ว');
  }

  Future<void> _pickOtDate() async {
    final first = _monthStart(selectedMonth);
    final last = _monthEnd(selectedMonth);

    final picked = await showDatePicker(
      context: context,
      initialDate: _initialOtPickerDate(),
      firstDate: first,
      lastDate: last,
      helpText: 'เลือกวันที่ทำ OT (${_fmtMonth(selectedMonth)})',
    );

    if (picked == null) return;
    if (!mounted || _disposed) return;

    setState(() => otDate = picked);
  }

  Future<void> _pickTimeStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: otStart ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: 'เวลาเริ่ม OT',
    );

    if (picked == null) return;
    if (!mounted || _disposed) return;

    setState(() => otStart = picked);
  }

  Future<void> _pickTimeEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: otEnd ?? const TimeOfDay(hour: 20, minute: 0),
      helpText: 'เวลาจบ OT',
    );

    if (picked == null) return;
    if (!mounted || _disposed) return;

    setState(() => otEnd = picked);
  }

  Future<void> _addOtEntry() async {
    if (_savingManualOt) return;

    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (otDate == null || otStart == null || otEnd == null) {
      _snack('กรุณาเลือก วันที่/เวลา OT ให้ครบ');
      return;
    }

    if (!_isSameMonth(otDate!, selectedMonth)) {
      _snack('วันที่ OT ต้องอยู่ในเดือนที่เลือก (${_fmtMonth(selectedMonth)})');
      return;
    }

    final staffId = _resolveStaffIdForPayroll();

    if (staffId.isEmpty) {
      _snack('ไม่พบข้อมูลพนักงานสำหรับบันทึก OT');
      return;
    }

    final selectedMultiplier = isHolidayX2
        ? _holidayOtMultiplier
        : _normalOtMultiplier;

    final workDate = _fmtDate(otDate!);
    final startHHmm = _fmtTOD(otStart!);
    final endHHmm = _fmtTOD(otEnd!);

    final minutes = _minutesBetween(startHHmm, endHHmm);
    if (minutes <= 0) {
      _snack('ช่วงเวลา OT ไม่ถูกต้อง');
      return;
    }

    if (!mounted || _disposed) return;

    setState(() {
      _savingManualOt = true;
    });

    try {
      final result = await _createOtManualViaApi(
        staffId: staffId,
        workDate: workDate,
        startHHmm: startHHmm,
        endHHmm: endHHmm,
        multiplier: selectedMultiplier,
      );

      if (!mounted || _disposed) return;

      if (!result.ok) {
        _snack(result.message);

        if (result.isDuplicate) {
          setState(() => _backendOtStatus = 'all');
          await _loadBackendOtForSelectedMonth();
        }

        return;
      }

      final savedStatus = result.savedStatus.trim().toLowerCase();
      final visibleStatus =
          ['approved', 'pending', 'rejected'].contains(savedStatus)
          ? savedStatus
          : 'approved';

      setState(() {
        otDate = null;
        otStart = null;
        otEnd = null;
        isHolidayX2 = false;
        _backendOtStatus = visibleStatus;
      });

      if (visibleStatus == 'pending') {
        _snack('บันทึก OT แล้ว แต่ยังรออนุมัติ ⏳');
      } else {
        _snack('บันทึก OT เข้าระบบแล้ว ✅');
      }

      await _loadBackendOtForSelectedMonth();
      await _loadClosedPayrollForSelectedMonth();
    } finally {
      if (!mounted || _disposed) return;
      setState(() => _savingManualOt = false);
    }
  }

  Future<void> _deleteOtEntryByMonthIndex(
    int indexInMonth,
    List<OTEntry> monthList,
  ) async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (indexInMonth < 0 || indexInMonth >= monthList.length) return;

    final target = monthList[indexInMonth];

    final realIndex = emp.otEntries.indexWhere(
      (e) =>
          e.date == target.date &&
          e.start == target.start &&
          e.end == target.end &&
          e.multiplier == target.multiplier,
    );

    if (realIndex < 0) return;

    if (!mounted || _disposed) return;

    setState(() {
      emp = emp.removeOtEntryAt(realIndex);
    });

    await _saveEmployeeLocal();

    _snack('ลบรายการ OT เดิมแล้ว');
  }

  Future<void> _saveEmployeeLocal() async {
    try {
      await StorageService.updateEmployeeById(emp.id, emp);
    } catch (_) {}
  }

  Future<void> _deleteBackendOtRow(int index) async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (index < 0 || index >= _backendOtRows.length) return;

    final row = _backendOtRows[index];
    final id = (row['_id'] ?? row['id'] ?? '').toString().trim();

    if (id.isEmpty) {
      _snack('ลบไม่ได้ เนื่องจากไม่พบรหัสรายการ');
      return;
    }

    final ok = await _deleteOtViaApi(id);

    if (ok) {
      _snack('ลบ OT ออกจากระบบแล้ว ✅');

      await _loadBackendOtForSelectedMonth();
      await _loadClosedPayrollForSelectedMonth();

      return;
    }

    _snack('ลบไม่สำเร็จ');
  }

  Future<void> _approveBackendOtRow(int index) async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (index < 0 || index >= _backendOtRows.length) return;

    final row = _backendOtRows[index];
    final id = (row['_id'] ?? row['id'] ?? '').toString().trim();

    if (id.isEmpty) {
      _snack('อนุมัติไม่ได้ เนื่องจากไม่พบรหัสรายการ');
      return;
    }

    final ok = await _approveOtViaApi(id);

    if (ok) {
      if (!mounted || _disposed) return;

      setState(() => _backendOtStatus = 'approved');
      _snack('อนุมัติแล้ว ✅');

      await _loadBackendOtForSelectedMonth();
      await _loadClosedPayrollForSelectedMonth();

      return;
    }

    _snack('อนุมัติไม่สำเร็จ');
  }

  Future<void> _rejectBackendOtRow(int index) async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    if (index < 0 || index >= _backendOtRows.length) return;

    final row = _backendOtRows[index];
    final id = (row['_id'] ?? row['id'] ?? '').toString().trim();

    if (id.isEmpty) {
      _snack('ปฏิเสธไม่ได้ เนื่องจากไม่พบรหัสรายการ');
      return;
    }

    final ok = await _rejectOtViaApi(id);

    if (ok) {
      if (!mounted || _disposed) return;

      setState(() => _backendOtStatus = 'rejected');
      _snack('ปฏิเสธแล้ว ✅');

      await _loadBackendOtForSelectedMonth();
      await _loadClosedPayrollForSelectedMonth();

      return;
    }

    _snack('ปฏิเสธไม่สำเร็จ');
  }

  Future<void> _bulkApproveThisMonth() async {
    if (!_isEditUnlocked) {
      _snack('ต้องปลดล็อกโหมดแก้ไขก่อน');
      return;
    }

    final staffId = _resolveStaffIdForPayroll();

    if (staffId.isEmpty) {
      _snack('ไม่พบข้อมูลพนักงานสำหรับอนุมัติ OT');
      return;
    }

    final monthKey = _fmtMonth(selectedMonth);
    final ok = await _bulkApproveMonthViaApi(month: monthKey, staffId: staffId);

    if (ok) {
      _snack('อนุมัติทั้งเดือนแล้ว ✅');

      setState(() => _backendOtStatus = 'approved');

      await _loadBackendOtForSelectedMonth();
      await _loadClosedPayrollForSelectedMonth();

      return;
    }

    _snack('อนุมัติทั้งเดือนไม่สำเร็จ');
  }

  String _safeS(dynamic v) => (v ?? '').toString().trim();

  double _rowMultiplier(Map<String, dynamic> r) {
    final mul = r['multiplier'];
    if (mul is num) return mul.toDouble();
    return double.tryParse('$mul') ?? _normalOtMultiplier;
  }

  int _rowMinutes(Map<String, dynamic> r) {
    final status = _safeS(r['status']).toLowerCase();

    final approvedRaw = r['approvedMinutes'];
    final approvedMinutes = approvedRaw is num
        ? approvedRaw.toInt()
        : int.tryParse('${approvedRaw ?? ''}');

    final minutesRaw = r['minutes'];
    final minutes = minutesRaw is num
        ? minutesRaw.toInt()
        : int.tryParse('${minutesRaw ?? ''}') ?? 0;

    if (status == 'approved' || status == 'locked') {
      return approvedMinutes ?? minutes;
    }

    return minutes;
  }

  String _rowWorkDate(Map<String, dynamic> r) {
    final d = _safeS(r['workDate']);
    if (d.isNotEmpty) return d;

    final d2 = _safeS(r['date']);
    if (d2.isNotEmpty) return d2;

    return '-';
  }

  String _rowStatus(Map<String, dynamic> r) {
    final st = _safeS(r['status']).toLowerCase();
    if (st.isEmpty) return '-';
    return st;
  }

  String _otStatusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'approved':
      case 'locked':
        return 'อนุมัติแล้ว';
      case 'pending':
        return 'รออนุมัติ';
      case 'rejected':
        return 'ไม่อนุมัติ';
      case 'all':
        return 'ทั้งหมด';
      default:
        return status.trim().isEmpty ? '-' : status;
    }
  }

  String _otMulLabel(double mul) {
    if (mul >= 1.99) return '×${mul.toStringAsFixed(1)}';
    if (mul >= 1.49 && mul < 1.99) return '×${mul.toStringAsFixed(1)}';
    return '×${mul.toStringAsFixed(2)}';
  }

  String _otTimeLabel(String start, String end) => '$start - $end';

  Widget _otMultiplierToggle() {
    final selectedMul = isHolidayX2
        ? _holidayOtMultiplier
        : _normalOtMultiplier;
    final mulText = _otMulLabel(selectedMul);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ตัวคูณ OT',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isHolidayX2
                        ? 'วันหยุด/พิเศษ (ตามเงื่อนไขคลินิก)'
                        : 'วันปกติ (ตามเงื่อนไขคลินิก)',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Text(
                mulText,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Switch.adaptive(
              value: isHolidayX2,
              onChanged: (v) {
                if (!mounted || _disposed) return;
                setState(() => isHolidayX2 = v);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'ปกติ: ${_otMulLabel(_normalOtMultiplier)}   •   วันหยุด: ${_otMulLabel(_holidayOtMultiplier)}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        if (_otPolicyError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _otPolicyError,
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
      ],
    );
  }
    @override
  Widget build(BuildContext context) {
    final bool isParttime = emp.isPartTime;

    final monthWorkEntries = _monthWorkEntries(selectedMonth);
    final monthWorkTimeEntries = _monthWorkTimeEntries(selectedMonth);

    final legacyHours = _sumWorkHours(monthWorkEntries);
    final timeHours = _sumWorkTimeHours(monthWorkTimeEntries);
    final totalWorkHours = legacyHours + timeHours;

    final hourlyWage = emp.hourlyWage;

    final localTotalOtHours = emp.totalOtHoursOfMonth(
      selectedMonth.year,
      selectedMonth.month,
    );
    final localTotalOtAmount = emp.totalOtAmountOfMonth(
      selectedMonth.year,
      selectedMonth.month,
    );

    final backendTotalOtHours = _backendApprovedMinutes / 60.0;

    final otBaseHourlyEstimate = isParttime
        ? hourlyWage
        : (emp.baseSalary > 0 ? emp.baseSalary / 30.0 / 8.0 : 0.0);

    final backendOtPayEstimate =
        _backendApprovedWeightedHours * otBaseHourlyEstimate;

    final closedRow = _closedPayrollRow ?? <String, dynamic>{};
    final closedAmounts = _asMap(_closedPayslipSummary?['amounts']);
    final hasClosedPayroll =
        _closedPayslipSummary != null && closedAmounts.isNotEmpty;

    final closedSalary = _readNum(closedAmounts['salary']);
    final closedSso = _readNum(closedAmounts['socialSecurity']);
    final closedOt = _readNum(closedAmounts['ot']);
    final closedBonus = _readNum(closedAmounts['bonus']);
    final closedLeaveDeduction = _readNum(closedAmounts['leaveDeduction']);
    final closedTax = _readNum(closedAmounts['tax']);
    final closedNetPay = _readNum(closedAmounts['netPay']);
    final closedOtHours = _readNum(closedRow['displayOtHours']);
    final closedGrossBeforeTax = _readNum(closedRow['displayGrossBeforeTax']);

    final closedSnapshot = _asMap(closedRow['snapshot']);
    final closedRegularWorkPayableHours = _readNum(
      closedSnapshot['regularWorkPayableHours'],
    );
    final closedRegularWorkHours = closedRegularWorkPayableHours > 0
        ? closedRegularWorkPayableHours
        : _readNum(closedSnapshot['regularWorkHours']);

    final previewRow = _payrollPreviewRow ?? <String, dynamic>{};
    final previewSummary = _payrollPreviewSummary ?? <String, dynamic>{};
    final previewInputs = _payrollPreviewInputs ?? <String, dynamic>{};
    final previewAmounts = _asMap(previewSummary['amounts']);
    final previewRegularWork = _asMap(previewInputs['regularWork']);

    final hasBackendPayrollPreview =
        !hasClosedPayroll && previewAmounts.isNotEmpty;

    final previewSalary = _readNum(previewAmounts['salary']);
    final previewSso = _readNum(previewAmounts['socialSecurity']);
    final previewOt = _readNum(previewAmounts['ot']);
    final previewBonus = _readNum(previewAmounts['bonus']);
    final previewLeaveDeduction = _readNum(previewAmounts['leaveDeduction']);
    final previewTax = _readNum(previewAmounts['tax']);
    final previewNetPay = _readNum(previewAmounts['netPay']);

    final previewGrossBeforeTaxFromSummary = _readNum(
      previewAmounts['grossBeforeTax'],
    );
    final previewGrossBeforeTax = previewGrossBeforeTaxFromSummary > 0
        ? previewGrossBeforeTaxFromSummary
        : _readNum(previewRow['displayGrossBeforeTax']);

    final previewOtHours = _readNum(previewRow['displayOtHours']);
    final previewRegularWorkHours = _readNum(previewRegularWork['hours']);

    final fallbackTotalOtHours = (!_loadingBackendOt && _backendOtError.isEmpty)
        ? backendTotalOtHours
        : 0.0;

    final fallbackOtPay = (!_loadingBackendOt && _backendOtError.isEmpty)
        ? backendOtPayEstimate
        : 0.0;

    final fallbackSsoAmount = isParttime
        ? 0.0
        : _computeSsoFromClinicConfig(emp.baseSalary);
    final fallbackAbsentDeduction = isParttime ? 0.0 : emp.absentDeduction();

    final normalPay = isParttime ? (totalWorkHours * hourlyWage) : 0.0;
    final grossBaseFulltime = isParttime ? 0.0 : emp.baseSalary;

    final fallbackAfterSsoAndLeaveNoOtFulltime = isParttime
        ? 0.0
        : (grossBaseFulltime - fallbackSsoAmount - fallbackAbsentDeduction)
              .clamp(0.0, double.infinity)
              .toDouble();

    final fallbackTotalMonthPayFulltime = isParttime
        ? 0.0
        : (grossBaseFulltime -
                  fallbackSsoAmount -
                  fallbackAbsentDeduction +
                  fallbackOtPay +
                  emp.bonus)
              .clamp(0.0, double.infinity)
              .toDouble();

    final fallbackTotalMonthPayParttime = isParttime
        ? (normalPay + fallbackOtPay + emp.bonus)
        : 0.0;

    final fallbackGrossMonthlyForTax = isParttime
        ? normalPay
        : grossBaseFulltime;
    final fallbackTotalMonthPayBeforeTax = isParttime
        ? fallbackTotalMonthPayParttime
        : fallbackTotalMonthPayFulltime;

    final fallbackWithholdingPercent = _getWithholdingPercent();
    final fallbackWithholdingAmount = _taxMode == _EmployeeTaxMode.withholding
        ? fallbackTotalMonthPayBeforeTax * (fallbackWithholdingPercent / 100.0)
        : 0.0;
    final fallbackNetAfterTax =
        fallbackTotalMonthPayBeforeTax - fallbackWithholdingAmount;

    final totalOtHours = hasClosedPayroll
        ? closedOtHours
        : hasBackendPayrollPreview && previewOtHours > 0
        ? previewOtHours
        : fallbackTotalOtHours;

    final otPay = hasClosedPayroll
        ? closedOt
        : hasBackendPayrollPreview
        ? previewOt
        : fallbackOtPay;

    final ssoAmount = hasClosedPayroll
        ? closedSso
        : hasBackendPayrollPreview
        ? previewSso
        : fallbackSsoAmount;

    final absentDeduction = hasClosedPayroll
        ? closedLeaveDeduction
        : hasBackendPayrollPreview
        ? previewLeaveDeduction
        : fallbackAbsentDeduction;

    final shownBonus = hasClosedPayroll
        ? closedBonus
        : hasBackendPayrollPreview
        ? previewBonus
        : emp.bonus;

    final grossMonthlyForTax = hasClosedPayroll
        ? closedSalary
        : hasBackendPayrollPreview
        ? previewSalary
        : fallbackGrossMonthlyForTax;

    final totalMonthPayBeforeTax = hasClosedPayroll
        ? closedGrossBeforeTax
        : hasBackendPayrollPreview
        ? previewGrossBeforeTax
        : fallbackTotalMonthPayBeforeTax;

    final withholdingAmount = hasClosedPayroll
        ? closedTax
        : hasBackendPayrollPreview
        ? previewTax
        : fallbackWithholdingAmount;

    final netAfterTax = hasClosedPayroll
        ? closedNetPay
        : hasBackendPayrollPreview
        ? previewNetPay
        : fallbackNetAfterTax;

    final afterSsoAndLeaveNoOtFulltime = hasClosedPayroll
        ? (closedSalary - closedSso - closedLeaveDeduction)
              .clamp(0.0, double.infinity)
              .toDouble()
        : hasBackendPayrollPreview
        ? (previewSalary - previewSso - previewLeaveDeduction)
              .clamp(0.0, double.infinity)
              .toDouble()
        : fallbackAfterSsoAndLeaveNoOtFulltime;

    final totalMonthPayFulltime = hasClosedPayroll
        ? closedGrossBeforeTax
        : hasBackendPayrollPreview
        ? previewGrossBeforeTax
        : fallbackTotalMonthPayFulltime;

    final totalMonthPayParttime = hasClosedPayroll
        ? closedGrossBeforeTax
        : hasBackendPayrollPreview
        ? previewGrossBeforeTax
        : fallbackTotalMonthPayParttime;

    final parttimeWorkHoursForDisplay =
        hasClosedPayroll && closedRegularWorkHours > 0
        ? closedRegularWorkHours
        : hasBackendPayrollPreview && previewRegularWorkHours > 0
        ? previewRegularWorkHours
        : totalWorkHours;

    final parttimeNormalPayForDisplay = hasClosedPayroll
        ? closedSalary
        : hasBackendPayrollPreview
        ? previewSalary
        : normalPay;

    final monthOtEntries = emp.otEntries
        .where((e) => e.isInMonth(selectedMonth.year, selectedMonth.month))
        .toList();

    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return WillPopScope(
      onWillPop: () async {
        await _safePopOrGoClinicHome();
        return false;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text('รายละเอียด: ${emp.fullName}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _safePopOrGoClinicHome,
          ),
          actions: [
            IconButton(
              tooltip: 'ตั้ง/เปลี่ยนรหัส PIN',
              onPressed: _setOrChangePin,
              icon: const Icon(Icons.password),
            ),
            IconButton(
              tooltip: 'แก้ไขข้อมูลพนักงาน',
              onPressed: _goEditEmployee,
              icon: const Icon(Icons.edit),
            ),
            IconButton(
              tooltip: _isEditUnlocked ? 'ล็อกโหมดแก้ไข' : 'ปลดล็อกโหมดแก้ไข',
              onPressed: _toggleEditLock,
              icon: Icon(_isEditUnlocked ? Icons.lock_open : Icons.lock),
            ),
          ],
        ),
        body: SafeArea(
          bottom: true,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboard),
            child: ListView(
              controller: _scrollCtrl,
              primary: false,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(14, 14, 14, bottomSafe + 80),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          _isEditUnlocked ? Icons.lock_open : Icons.lock,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isEditUnlocked
                                ? 'โหมดแก้ไข: ปลดล็อกแล้ว'
                                : 'โหมดแก้ไข: ล็อกอยู่ (กดรูปกุญแจเพื่อใส่รหัส)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _identityCard(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'เดือนที่เลือก: ${_fmtMonth(selectedMonth)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _pickMonth,
                      child: const Text('เปลี่ยนเดือน'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'OT จากระบบ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('สถานะ:'),
                            DropdownButton<String>(
                              value: _backendOtStatus,
                              items: const [
                                DropdownMenuItem(
                                  value: 'approved',
                                  child: Text('อนุมัติแล้ว'),
                                ),
                                DropdownMenuItem(
                                  value: 'pending',
                                  child: Text('รออนุมัติ'),
                                ),
                                DropdownMenuItem(
                                  value: 'rejected',
                                  child: Text('ไม่อนุมัติ'),
                                ),
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text('ทั้งหมด'),
                                ),
                              ],
                              onChanged: (v) async {
                                if (v == null) return;
                                if (!mounted || _disposed) return;

                                setState(() => _backendOtStatus = v);
                                await _loadBackendOtForSelectedMonth();
                                await _loadClosedPayrollForSelectedMonth();
                              },
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await _loadBackendOtForSelectedMonth();
                                await _loadClosedPayrollForSelectedMonth();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('รีเฟรช'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _bulkApproveThisMonth,
                              icon: const Icon(Icons.done_all),
                              label: const Text('อนุมัติทั้งเดือน'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_loadingBackendOt)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_backendOtError.isNotEmpty)
                          Text(_backendOtError)
                        else ...[
                          Text('แสดงรายการ: ${_backendOtRows.length} รายการ'),
                          const SizedBox(height: 6),
                          const Text('สรุปรายการที่อนุมัติในเดือนนี้:'),
                          Text(' • จำนวน: $_backendApprovedCount รายการ'),
                          Text(' • รวมเวลา: $_backendApprovedMinutes นาที'),
                          Text(
                            ' • ชั่วโมงถ่วงน้ำหนัก: ${_backendApprovedWeightedHours.toStringAsFixed(2)} ชม.',
                          ),
                          if (!hasClosedPayroll)
                            Text(
                              ' • พรีวิวค่า OT: ${backendOtPayEstimate.toStringAsFixed(2)} บาท',
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'สรุปเดือน ${_fmtMonth(selectedMonth)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (_loadingClosedPayroll || _loadingPayrollPreview)
                          const LinearProgressIndicator(minHeight: 3)
                        else if (_closedPayrollError.isNotEmpty)
                          Text(
                            _closedPayrollError,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          )
                        else if (hasClosedPayroll)
                          Text(
                            'เดือนนี้แสดงยอดจากงวดเงินเดือนที่ปิดแล้ว',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else if (hasBackendPayrollPreview)
                          Text(
                            'เดือนนี้ยังไม่ปิดงวด — ยอดด้านล่างเป็นพรีวิวจาก backend และข้อมูล attendance ล่าสุด',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          Text(
                            'เดือนนี้ยังไม่ปิดงวด — ยอดด้านล่างเป็นพรีวิวจากข้อมูลที่บันทึกในระบบ เมื่อปิดงวด ระบบจะคำนวณยอดจริงอีกครั้ง',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (_payrollPreviewError.isNotEmpty &&
                            !hasClosedPayroll) ...[
                          const SizedBox(height: 6),
                          Text(
                            _payrollPreviewError,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        if (!isParttime) ...[
                          const Text('ประเภท: Full-time'),
                          const SizedBox(height: 6),
                          const Text('อัตราประกันสังคมของคลินิก (%)'),
                          const SizedBox(height: 6),
                          if (_loadingClinicPayrollConfig)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: LinearProgressIndicator(minHeight: 3),
                            ),
                          if (_clinicPayrollConfigError.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _clinicPayrollConfigError,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: ssoPercentCtrl,
                                enabled:
                                    !hasClosedPayroll &&
                                    _isEditUnlocked &&
                                    !_savingSso &&
                                    !_loadingClinicPayrollConfig,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [_decimalFormatter],
                                decoration: InputDecoration(
                                  labelText: 'เช่น 5.00',
                                  helperText:
                                      'เพดานฐานค่าจ้าง: ${_effectiveClinicSsoMaxWageBase.toStringAsFixed(0)} บาท',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed:
                                    hasClosedPayroll ||
                                        _savingSso ||
                                        _loadingClinicPayrollConfig
                                    ? null
                                    : _saveSsoPercentFromUI,
                                child: Text(
                                  _savingSso ? 'กำลังบันทึก...' : 'บันทึก',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'เงินเดือนฐาน: ${grossMonthlyForTax.toStringAsFixed(2)} บาท',
                          ),
                          Text(
                            'หักประกันสังคม: -${ssoAmount.toStringAsFixed(2)} บาท',
                          ),
                          Text(
                            'หักวันลา/ขาด: -${absentDeduction.toStringAsFixed(2)} บาท',
                          ),
                          const Divider(height: 18),
                          Text(
                            'ชั่วโมง OT รวม: ${totalOtHours.toStringAsFixed(2)} ชม.',
                          ),
                          Text('ค่า OT รวม: ${otPay.toStringAsFixed(2)} บาท'),
                          Text('โบนัส: ${shownBonus.toStringAsFixed(2)} บาท'),
                          const SizedBox(height: 10),
                          Text(
                            'ยอดหลังหักประกันสังคมและหักลา/ขาด (ไม่รวม OT/โบนัส): ${afterSsoAndLeaveNoOtFulltime.toStringAsFixed(2)} บาท',
                          ),
                          Text(
                            'ยอดรวมก่อนภาษี: ${totalMonthPayFulltime.toStringAsFixed(2)} บาท',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ] else ...[
                          const Text('ประเภท: Part-time'),
                          const SizedBox(height: 6),
                          Text(
                            'อัตราค่าจ้าง: ${hourlyWage.toStringAsFixed(2)} บาท/ชม.',
                          ),
                          Text(
                            'ชั่วโมงทำงานปกติรวม: ${parttimeWorkHoursForDisplay.toStringAsFixed(2)} ชม.',
                          ),
                          if (_loadingPayrollPreview)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'กำลังโหลดชั่วโมงทำงานจาก backend...',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          if (hasBackendPayrollPreview)
                            const Text(
                              ' • จาก backend attendance/check-in checkout',
                              style: TextStyle(fontSize: 12),
                            ),
                          if (timeHours > 0)
                            Text(
                              ' • จากเวลาเริ่ม-จบที่บันทึกในเครื่อง: ${timeHours.toStringAsFixed(2)} ชม.',
                            ),
                          if (legacyHours > 0)
                            Text(
                              ' • จากแบบเดิมในเครื่อง (ชั่วโมง): ${legacyHours.toStringAsFixed(2)} ชม.',
                            ),
                          Text(
                            'ค่าแรงปกติรวม: ${parttimeNormalPayForDisplay.toStringAsFixed(2)} บาท',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'ชั่วโมง OT รวม: ${totalOtHours.toStringAsFixed(2)} ชม.',
                          ),
                          Text('ค่า OT รวม: ${otPay.toStringAsFixed(2)} บาท'),
                          Text('โบนัส: ${shownBonus.toStringAsFixed(2)} บาท'),
                          const Divider(height: 18),
                          Text(
                            'รวมทั้งเดือน (ก่อนหักภาษี): ${totalMonthPayParttime.toStringAsFixed(2)} บาท',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _taxModeCard(
                          totalMonthPayBeforeTax: totalMonthPayBeforeTax,
                          withholdingAmount: withholdingAmount,
                          netAfterTax: netAfterTax,
                          hasClosedPayroll: hasClosedPayroll,
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.receipt_long),
                            label: Text(
                              _taxMode == _EmployeeTaxMode.none
                                  ? 'ดูพรีวิวสลิป (ไม่หักภาษี)'
                                  : 'ดูพรีวิวสลิป / ปิดงวด',
                            ),
                            onPressed: () async {
                              await _openTaxSummaryOrPreview(
                                isParttime: isParttime,
                                grossBaseFallback: grossBaseFulltime,
                                leaveDeductionInput: fallbackAbsentDeduction,
                                regularWorkHoursInput:
                                    parttimeWorkHoursForDisplay,
                              );
                            },
                          ),
                        ),
                        if (hasClosedPayroll) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: _recalculatingClosedPayroll
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.restart_alt),
                              label: Text(
                                _recalculatingClosedPayroll
                                    ? 'กำลังคำนวณงวดใหม่...'
                                    : 'คำนวณงวดนี้ใหม่',
                              ),
                              onPressed: _recalculatingClosedPayroll
                                  ? null
                                  : _recalculateClosedPayrollForSelectedMonth,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isEditUnlocked
                                ? 'ใช้เมื่อมีการสแกนเวลา OT หรือข้อมูลเงินเดือนเปลี่ยนหลังปิดงวด'
                                : 'ต้องปลดล็อกโหมดแก้ไขก่อนจึงจะคำนวณงวดใหม่ได้',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isEditUnlocked
                                  ? Colors.grey.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (isParttime) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'บันทึกชั่วโมงทำงาน (Part-time)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'หมายเหตุ: ถ้ามีพนักงานสแกนเข้า-ออก ระบบเงินเดือนจะใช้ชั่วโมงจาก backend attendance เป็นหลัก',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (!_workEntriesLoaded)
                            const Center(child: CircularProgressIndicator())
                          else ...[
                            const Text(
                              'แบบใหม่: เวลาเริ่ม-จบ (คำนวณชั่วโมงอัตโนมัติ)',
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: _pickWorkTimeDate,
                                  child: Text(
                                    workTimeDate == null
                                        ? 'เลือกวันที่'
                                        : _fmtDate(workTimeDate!),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: _pickWorkStart,
                                  child: Text(
                                    workStart == null
                                        ? 'เวลาเริ่ม'
                                        : _fmtTOD(workStart!),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: _pickWorkEnd,
                                  child: Text(
                                    workEnd == null
                                        ? 'เวลาจบ'
                                        : _fmtTOD(workEnd!),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: breakMinutesCtrl,
                                    enabled: _isEditUnlocked,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'พัก (นาที)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed: _addWorkTimeEntry,
                                  child: const Text('เพิ่ม'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(),
                            const Text('แบบเดิม: ใส่จำนวนชั่วโมง'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: _pickWorkDate,
                                  child: Text(
                                    workDate == null
                                        ? 'เลือกวันที่'
                                        : _fmtDate(workDate!),
                                  ),
                                ),
                                SizedBox(
                                  width: 150,
                                  child: TextField(
                                    controller: workHoursCtrl,
                                    enabled: _isEditUnlocked,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: [_decimalFormatter],
                                    decoration: const InputDecoration(
                                      labelText: 'ชั่วโมง',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: _addWorkEntry,
                                  child: const Text('เพิ่ม'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(),
                            const Text('รายการในเดือนนี้'),
                            const SizedBox(height: 8),
                            if (monthWorkTimeEntries.isNotEmpty) ...[
                              const Text('• จากเวลาเริ่ม-จบ'),
                              const SizedBox(height: 6),
                              ...List.generate(monthWorkTimeEntries.length, (
                                i,
                              ) {
                                final e = monthWorkTimeEntries[i];

                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('${e.date}  ${e.start}-${e.end}'),
                                  subtitle: Text(
                                    'พัก ${e.breakMinutes} นาที • ${e.hours.toStringAsFixed(2)} ชม.',
                                  ),
                                  trailing: IconButton(
                                    onPressed: () => _deleteWorkTimeEntry(
                                      i,
                                      monthWorkTimeEntries,
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                );
                              }),
                              const SizedBox(height: 8),
                            ],
                            if (monthWorkEntries.isNotEmpty) ...[
                              const Text('• จากแบบเดิม (ชั่วโมง)'),
                              const SizedBox(height: 6),
                              ...List.generate(monthWorkEntries.length, (i) {
                                final e = monthWorkEntries[i];

                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(e.date),
                                  subtitle: Text(
                                    '${e.hours.toStringAsFixed(2)} ชม.',
                                  ),
                                  trailing: IconButton(
                                    onPressed: () =>
                                        _deleteWorkEntry(i, monthWorkEntries),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                );
                              }),
                            ],
                            if (monthWorkEntries.isEmpty &&
                                monthWorkTimeEntries.isEmpty)
                              const Text('ยังไม่มีข้อมูลในเดือนนี้'),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'เพิ่ม OT รายวัน',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'บันทึก OT เข้าระบบตามเดือนที่เลือก: ${_fmtMonth(selectedMonth)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _pickOtDate,
                              child: Text(
                                otDate == null
                                    ? 'เลือกวันที่'
                                    : _fmtDate(otDate!),
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _pickTimeStart,
                              child: Text(
                                otStart == null
                                    ? 'เวลาเริ่ม'
                                    : _fmtTOD(otStart!),
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _pickTimeEnd,
                              child: Text(
                                otEnd == null ? 'เวลาจบ' : _fmtTOD(otEnd!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_loadingOtPolicy)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: LinearProgressIndicator(minHeight: 3),
                          ),
                        _otMultiplierToggle(),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _savingManualOt ? null : _addOtEntry,
                            child: Text(
                              _savingManualOt
                                  ? 'กำลังบันทึก...'
                                  : 'บันทึก OT เข้าระบบ',
                            ),
                          ),
                        ),
                        if (!_isEditUnlocked)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'หมายเหตุ: ต้องปลดล็อกโหมดแก้ไขก่อนถึงจะบันทึกได้',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'รายการ OT เดือนนี้',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        if (_loadingBackendOt)
                          const Center(child: CircularProgressIndicator())
                        else if (_backendOtError.isNotEmpty)
                          Text(_backendOtError)
                        else if (_backendOtRows.isEmpty)
                          const Text('ยังไม่มีรายการ OT ในเดือนนี้')
                        else ...[
                          ...List.generate(_backendOtRows.length, (i) {
                            final r = _backendOtRows[i];
                            final date = _rowWorkDate(r);
                            final start = _safeS(r['start'] ?? r['startTime']);
                            final end = _safeS(r['end'] ?? r['endTime']);
                            final minutes = _rowMinutes(r);
                            final mul = _rowMultiplier(r);
                            final st = _rowStatus(r);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$date  ${start.isNotEmpty && end.isNotEmpty ? _otTimeLabel(start, end) : ''}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text('สถานะ: ${_otStatusLabel(st)}'),
                                    Text(
                                      'เวลา: $minutes นาที  •  ตัวคูณ: ${_otMulLabel(mul)}',
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: _isEditUnlocked
                                              ? () => _approveBackendOtRow(i)
                                              : null,
                                          icon: const Icon(Icons.check),
                                          label: const Text('อนุมัติ'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _isEditUnlocked
                                              ? () => _rejectBackendOtRow(i)
                                              : null,
                                          icon: const Icon(Icons.close),
                                          label: const Text('ปฏิเสธ'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _isEditUnlocked
                                              ? () => _deleteBackendOtRow(i)
                                              : null,
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          label: const Text('ลบ'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ประวัติ OT เดิม (ไม่ถูกนำไปคำนวณเงินเดือน)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        if (monthOtEntries.isEmpty)
                          const Text('ไม่มีประวัติ OT เดิมในเดือนนี้')
                        else ...[
                          ...List.generate(monthOtEntries.length, (i) {
                            final e = monthOtEntries[i];

                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${e.date}  ${e.start}-${e.end}'),
                              subtitle: Text(
                                'ตัวคูณ: ${_otMulLabel(e.multiplier)}  •  ${e.hours.toStringAsFixed(2)} ชม.',
                              ),
                              trailing: IconButton(
                                onPressed: () => _deleteOtEntryByMonthIndex(
                                  i,
                                  monthOtEntries,
                                ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            );
                          }),
                          const SizedBox(height: 6),
                          Text(
                            'รวมประวัติ OT เดิม: ${localTotalOtHours.toStringAsFixed(2)} ชม. (ไม่ใช้ปิดงวด)',
                          ),
                          Text(
                            'ค่า OT เดิม: ${localTotalOtAmount.toStringAsFixed(2)} บาท (ไม่ใช้ปิดงวด)',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}