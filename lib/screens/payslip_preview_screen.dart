// lib/screens/payslip_preview_screen.dart
//
// ✅ Payslip Preview (PRODUCTION CLEAN)
// - ✅ ใช้งวดปิดจริงจาก backend ถ้ามี
// - ✅ ถ้าไม่มี -> fallback local calculator + ดึง OT approved จาก backend
// - ✅ Month Picker จริง (เลือกเดือนตรง ๆ)
// - ✅ ซ่อน OT Snapshot ถ้าค่าเป็น 0/ว่างทั้งหมด
// - ✅ เก็บข้อความเชิง debug / tech ออกจาก UI
// - ✅ รองรับ Part-time work hours
// - ✅ PDF ไทยด้วย NotoSansThai
//
// IMPORTANT:
// - backend employeeId in payroll_service = staffId (stf_...)
// - endpoints:
//   GET /payroll-close/close-month/:employeeId/:month
//   GET /overtime/my?month=yyyy-MM&status=approved

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart' show PdfColor, PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/employee_model.dart';
import '../utils/payroll_calculator.dart';

class _WorkHourEntryLite {
  final String date; // yyyy-MM-dd
  final double hours;

  const _WorkHourEntryLite({
    required this.date,
    required this.hours,
  });

  factory _WorkHourEntryLite.fromMap(Map<String, dynamic> map) {
    return _WorkHourEntryLite(
      date: (map['date'] ?? '').toString(),
      hours: (map['hours'] as num? ?? 0).toDouble(),
    );
  }

  bool isInMonth(int year, int month) {
    final parts = date.split('-');
    if (parts.length < 2) return false;
    final y = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return y == year && m == month;
  }
}

class _ClinicBrand {
  final String clinicId;
  final String name;
  final String phone;
  final String address;
  final String brandAbbr;
  final String brandColor;

  const _ClinicBrand({
    required this.clinicId,
    required this.name,
    required this.phone,
    required this.address,
    required this.brandAbbr,
    required this.brandColor,
  });

  factory _ClinicBrand.fromMap(Map<String, dynamic> m) {
    final c = (m['clinic'] is Map) ? Map<String, dynamic>.from(m['clinic']) : m;
    return _ClinicBrand(
      clinicId: (c['clinicId'] ?? c['id'] ?? c['_id'] ?? '').toString(),
      name: (c['name'] ?? '').toString(),
      phone: (c['phone'] ?? '').toString(),
      address: (c['address'] ?? '').toString(),
      brandAbbr: (c['brandAbbr'] ?? '').toString(),
      brandColor: (c['brandColor'] ?? '').toString(),
    );
  }
}

class _PayslipVM {
  final bool isPartTime;
  final String monthKey; // yyyy-MM

  final double grossBase;
  final double otPay;
  final double bonus;
  final double otherAllowance;
  final double otherDeduction;

  final double grossMonthly;
  final double withheldTaxMonthly;
  final double ssoEmployeeMonthly;
  final double pvdEmployeeMonthly;
  final double netPay;

  final int? otApprovedMinutes;
  final double? otApprovedWeightedHours;
  final int? otApprovedCount;

  final bool fromBackend;
  final String sourceLabel;

  const _PayslipVM({
    required this.isPartTime,
    required this.monthKey,
    required this.grossBase,
    required this.otPay,
    required this.bonus,
    required this.otherAllowance,
    required this.otherDeduction,
    required this.grossMonthly,
    required this.withheldTaxMonthly,
    required this.ssoEmployeeMonthly,
    required this.pvdEmployeeMonthly,
    required this.netPay,
    required this.fromBackend,
    required this.sourceLabel,
    this.otApprovedMinutes,
    this.otApprovedWeightedHours,
    this.otApprovedCount,
  });

  factory _PayslipVM.fromBackendRow({
    required bool isPartTime,
    required String monthKey,
    required Map<String, dynamic> row,
  }) {
    double n(dynamic v) =>
        (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;

    return _PayslipVM(
      isPartTime: isPartTime,
      monthKey: monthKey,
      grossBase: n(row['grossBase']),
      otPay: n(row['otPay']),
      bonus: n(row['bonus']),
      otherAllowance: n(row['otherAllowance']),
      otherDeduction: n(row['otherDeduction']),
      grossMonthly: n(row['grossMonthly']),
      withheldTaxMonthly: n(row['withheldTaxMonthly']),
      ssoEmployeeMonthly: n(row['ssoEmployeeMonthly']),
      pvdEmployeeMonthly: n(row['pvdEmployeeMonthly']),
      netPay: n(row['netPay']),
      otApprovedMinutes:
          row.containsKey('otApprovedMinutes') ? i(row['otApprovedMinutes']) : null,
      otApprovedWeightedHours: row.containsKey('otApprovedWeightedHours')
          ? n(row['otApprovedWeightedHours'])
          : null,
      otApprovedCount:
          row.containsKey('otApprovedCount') ? i(row['otApprovedCount']) : null,
      fromBackend: true,
      sourceLabel: 'งวดปิดจริง',
    );
  }
}

class _OtSummary {
  final int approvedMinutes;
  final double weightedHours;
  final int count;

  const _OtSummary({
    required this.approvedMinutes,
    required this.weightedHours,
    required this.count,
  });
}

class PayslipPreviewScreen extends StatefulWidget {
  final EmployeeModel emp;

  const PayslipPreviewScreen({super.key, required this.emp});

  @override
  State<PayslipPreviewScreen> createState() => _PayslipPreviewScreenState();
}

class _PayslipPreviewScreenState extends State<PayslipPreviewScreen> {
  static const String _ssoKey = 'settings_sso_percent';
  static const String _payrollBaseUrl =
      'https://payroll-service-808t.onrender.com';

  static const int _workDaysPerMonth = 26;
  static const int _hoursPerDay = 8;

  static const List<String> _tokenKeys = [
    'auth_token',
    'token',
    'jwtToken',
    'authToken',
    'userToken',
    'jwt_token',
  ];

  static const List<String> _clinicIdKeys = [
    'app_clinic_id',
    'clinicId',
    'currentClinicId',
    'myClinicId',
    'appClinicId',
  ];

  bool _loading = true;

  double _ssoPercent = 5.0;
  double _parttimeRegularHours = 0.0;
  List<_WorkHourEntryLite> _parttimeWorkEntriesOfMonth = [];

  late DateTime _selectedMonth;
  _ClinicBrand? _clinic;
  String? _error;

  _PayslipVM? _vm;
  bool _remoteTried = false;

  pw.Font? _pdfFontRegular;
  pw.Font? _pdfFontBold;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _bootstrap();
  }

  int get _year => _selectedMonth.year;
  int get _month => _selectedMonth.month;

  String _fmtMonthShort(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtMonthLong(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.year}';

  String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  List<DateTime> _buildMonthList({int back = 36, int forward = 0}) {
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
    final currentKey = _monthKey(_selectedMonth);

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เลือกเดือนสลิป'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final m = options[i];
              final key = _monthKey(m);
              final selected = key == currentKey;

              return ListTile(
                dense: true,
                title: Text(key),
                trailing: selected ? const Icon(Icons.check_circle) : null,
                onTap: () => Navigator.pop(ctx, m),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMonth() async {
    final picked = await _pickMonthDialog();
    if (picked == null) return;

    if (!mounted) return;
    setState(() {
      _loading = true;
      _selectedMonth = DateTime(picked.year, picked.month, 1);
      _vm = null;
      _remoteTried = false;
      _error = null;
    });

    await _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadPdfFonts();
      await _loadSettingsAndWorkHours();
      await _loadClinicBrand();
      await _loadRemoteClosedMonthOrFallback();
    } catch (_) {
      _error = 'โหลดข้อมูลสลิปไม่สำเร็จ';
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadPdfFonts() async {
    try {
      final dataRegular =
          await rootBundle.load('assets/fonts/NotoSansThai_Condensed-Regular.ttf');
      final dataBold =
          await rootBundle.load('assets/fonts/NotoSansThai_Condensed-Bold.ttf');

      _pdfFontRegular = pw.Font.ttf(dataRegular);
      _pdfFontBold = pw.Font.ttf(dataBold);
    } catch (_) {
      _pdfFontRegular = null;
      _pdfFontBold = null;
    }
  }

  Future<void> _loadSettingsAndWorkHours() async {
    final prefs = await SharedPreferences.getInstance();
    final sso = prefs.getDouble(_ssoKey) ?? 5.0;

    double partHours = 0.0;
    final partEntriesMonth = <_WorkHourEntryLite>[];

    if (PayrollCalculator.isPartTime(widget.emp)) {
      final key = 'work_entries_${widget.emp.id}';
      final raw = prefs.getString(key);

      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = json.decode(raw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                final e = _WorkHourEntryLite.fromMap(
                  Map<String, dynamic>.from(item),
                );
                if (e.isInMonth(_year, _month)) {
                  partHours += e.hours;
                  partEntriesMonth.add(e);
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() {
      _ssoPercent = sso;
      _parttimeRegularHours = partHours;
      _parttimeWorkEntriesOfMonth = partEntriesMonth;
    });
  }

  Future<String> _getTokenRobust() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = (prefs.getString(k) ?? '').trim();
      if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return '';
  }

  Future<String> _getClinicIdRobust() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _clinicIdKeys) {
      final v = (prefs.getString(k) ?? '').trim();
      if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return '';
  }

  Future<void> _loadClinicBrand() async {
    final token = await _getTokenRobust();
    final clinicId = await _getClinicIdRobust();

    if (clinicId.isEmpty || token.isEmpty) return;

    try {
      final uri = Uri.parse('$_payrollBaseUrl/clinics/$clinicId');
      final resp =
          await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode >= 400) return;

      final decoded = json.decode(resp.body);
      if (decoded is Map<String, dynamic>) {
        final c = _ClinicBrand.fromMap(decoded);
        if (!mounted) return;
        setState(() => _clinic = c);
      }
    } catch (_) {}
  }

  bool _isStaffId(String v) => v.trim().startsWith('stf_');

  String? _safeStaffIdForPayrollOrNull() {
    final candidates = <String>[
      widget.emp.staffId.trim(),
      widget.emp.id.trim(),
    ];

    for (final c in candidates) {
      if (_isStaffId(c)) return c;
    }

    try {
      final v = (widget.emp as dynamic).employeeId;
      final s = (v ?? '').toString().trim();
      if (_isStaffId(s)) return s;
    } catch (_) {}

    return null;
  }

  Map<String, dynamic>? _extractClosedRowFromDecoded(dynamic decoded) {
    if (decoded is! Map) return null;
    final m = Map<String, dynamic>.from(decoded);

    final candidates = [
      m['row'],
      m['data'],
      m['payrollClose'],
      if (m['data'] is Map) (m['data'] as Map)['row'],
      if (m['data'] is Map) (m['data'] as Map)['payrollClose'],
    ];

    for (final c in candidates) {
      if (c is Map) return Map<String, dynamic>.from(c);
    }

    final looksLikeRow = m.containsKey('grossMonthly') ||
        m.containsKey('netPay') ||
        m.containsKey('grossBase') ||
        m.containsKey('withheldTaxMonthly');

    if (looksLikeRow) return m;

    return null;
  }

  Future<Map<String, dynamic>?> _fetchClosedMonth({
    required String token,
    required String employeeId,
    required String monthKey,
  }) async {
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    final candidates = <Uri>[
      Uri.parse('$_payrollBaseUrl/payroll-close/close-month/$employeeId/$monthKey'),
      Uri.parse(
        '$_payrollBaseUrl/api/payroll-close/close-month/$employeeId/$monthKey',
      ),
    ];

    for (final u in candidates) {
      try {
        final resp =
            await http.get(u, headers: headers).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 404) continue;
        if (resp.statusCode != 200) continue;

        final decoded = json.decode(resp.body);
        final row = _extractClosedRowFromDecoded(decoded);
        if (row != null) return row;
      } catch (_) {}
    }
    return null;
  }

  Future<_OtSummary?> _fetchOtApprovedSummary({
    required String token,
    required String monthKey,
  }) async {
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    final candidates = <Uri>[
      Uri.parse('$_payrollBaseUrl/overtime/my?month=$monthKey&status=approved'),
      Uri.parse(
        '$_payrollBaseUrl/api/overtime/my?month=$monthKey&status=approved',
      ),
    ];

    for (final u in candidates) {
      try {
        final resp =
            await http.get(u, headers: headers).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 404) continue;
        if (resp.statusCode != 200) continue;

        final decoded = json.decode(resp.body);
        if (decoded is! Map) continue;

        final m = Map<String, dynamic>.from(decoded);

        final itemsAny = m['items'];
        if (itemsAny is List) {
          int minutesSum = 0;
          double weightedHours = 0.0;
          int cnt = 0;

          for (final it in itemsAny) {
            if (it is! Map) continue;
            final row = Map<String, dynamic>.from(it);

            final minutes = (row['minutes'] is num)
                ? (row['minutes'] as num).toInt()
                : int.tryParse('${row['minutes']}') ?? 0;

            final mul = (row['multiplier'] is num)
                ? (row['multiplier'] as num).toDouble()
                : double.tryParse('${row['multiplier']}') ?? 1.0;

            if (minutes > 0) {
              minutesSum += minutes;
              weightedHours += (minutes / 60.0) * (mul <= 0 ? 1.0 : mul);
              cnt += 1;
            }
          }

          return _OtSummary(
            approvedMinutes: minutesSum,
            weightedHours: weightedHours,
            count: cnt,
          );
        }

        final sumAny = m['summary'];
        if (sumAny is Map) {
          final sm = Map<String, dynamic>.from(sumAny);

          final approvedMinutes = (sm['approvedMinutes'] is num)
              ? (sm['approvedMinutes'] as num).toInt()
              : int.tryParse('${sm['approvedMinutes']}') ?? 0;

          final weighted = (sm['weightedHours'] is num)
              ? (sm['weightedHours'] as num).toDouble()
              : (approvedMinutes / 60.0);

          final count = (sm['approvedCount'] is num)
              ? (sm['approvedCount'] as num).toInt()
              : int.tryParse('${sm['approvedCount']}') ?? 0;

          return _OtSummary(
            approvedMinutes: approvedMinutes,
            weightedHours: weighted,
            count: count,
          );
        }
      } catch (_) {}
    }

    return null;
  }

  double _inferHourlyRate({
    required bool isPartTime,
    required double grossBase,
    required PayrollMonthResult local,
  }) {
    if (isPartTime) {
      final wage = widget.emp.hourlyWage;
      if (wage > 0) return wage;

      final hours = _parttimeRegularHours;
      if (hours > 0 && local.regularPay > 0) {
        return local.regularPay / hours;
      }
    }

    if (!isPartTime && grossBase > 0) {
      final denom = (_workDaysPerMonth * _hoursPerDay).toDouble();
      if (denom > 0) return grossBase / denom;
    }

    return 0.0;
  }

  bool _hasMeaningfulOtSnapshot(_PayslipVM vm) {
    final minutes = vm.otApprovedMinutes ?? 0;
    final weighted = vm.otApprovedWeightedHours ?? 0.0;
    final count = vm.otApprovedCount ?? 0;

    return minutes > 0 || weighted > 0 || count > 0;
  }

  Future<void> _loadRemoteClosedMonthOrFallback() async {
    final token = await _getTokenRobust();
    final monthKey = _monthKey(_selectedMonth);
    final isPT = PayrollCalculator.isPartTime(widget.emp);

    Map<String, dynamic>? row;
    final staffId = _safeStaffIdForPayrollOrNull();

    if (token.isNotEmpty && staffId != null) {
      row = await _fetchClosedMonth(
        token: token,
        employeeId: staffId,
        monthKey: monthKey,
      );
    }

    _remoteTried = true;

    if (row != null) {
      if (!mounted) return;
      setState(() {
        _vm = _PayslipVM.fromBackendRow(
          isPartTime: isPT,
          monthKey: monthKey,
          row: row!,
        );
      });
      return;
    }

    final local = PayrollCalculator.computeMonth(
      emp: widget.emp,
      year: _year,
      month: _month,
      ssoPercent: _ssoPercent,
      parttimeRegularHours: _parttimeRegularHours,
      workDaysPerMonth: _workDaysPerMonth,
      hoursPerDay: _hoursPerDay,
    );

    _OtSummary? otSum;
    if (token.isNotEmpty) {
      otSum = await _fetchOtApprovedSummary(token: token, monthKey: monthKey);
    }

    double otPayFinal = local.otPay;
    int? approvedMinutes;
    double? weightedHours;
    int? approvedCount;

    if (otSum != null && otSum.approvedMinutes > 0) {
      final grossBaseForRate = isPT ? local.regularPay : local.monthlyBaseSalary;

      final hourly = _inferHourlyRate(
        isPartTime: isPT,
        grossBase: grossBaseForRate,
        local: local,
      );

      approvedMinutes = otSum.approvedMinutes;
      weightedHours = otSum.weightedHours;
      approvedCount = otSum.count;

      if (hourly > 0) {
        otPayFinal = otSum.weightedHours * hourly;
      }
    }

    final isPTLocal = local.isPartTime;
    final grossBaseLocal =
        isPTLocal ? local.regularPay : local.monthlyBaseSalary;

    final grossLocalWithOverride = isPTLocal
        ? (local.regularPay + local.bonus + otPayFinal)
        : (local.monthlyBaseSalary + local.bonus + otPayFinal);

    final netLocalWithOverride = (grossLocalWithOverride -
            local.socialSecurity -
            local.absentDeduction)
        .clamp(0.0, double.infinity);

    if (!mounted) return;
    setState(() {
      _vm = _PayslipVM(
        isPartTime: isPTLocal,
        monthKey: monthKey,
        grossBase: grossBaseLocal,
        otPay: otPayFinal,
        bonus: local.bonus,
        otherAllowance: 0,
        otherDeduction: 0,
        grossMonthly: grossLocalWithOverride,
        withheldTaxMonthly: 0,
        ssoEmployeeMonthly: local.socialSecurity,
        pvdEmployeeMonthly: 0,
        netPay: netLocalWithOverride,
        fromBackend: false,
        sourceLabel: 'ประมาณการ',
        otApprovedMinutes: approvedMinutes,
        otApprovedWeightedHours: weightedHours,
        otApprovedCount: approvedCount,
      );
    });
  }

  String _abbrFromName(String name) {
    final t = name.trim();
    if (t.isEmpty) return 'CL';
    final parts =
        t.split(RegExp(r'\s+')).where((x) => x.trim().isNotEmpty).toList();
    if (parts.isEmpty) return 'CL';

    if (parts.length == 1) {
      final s = parts.first.replaceAll(RegExp(r'[^A-Za-z0-9ก-๙]'), '');
      if (s.length >= 2) return s.substring(0, 2).toUpperCase();
      return s.isEmpty ? 'CL' : s.substring(0, 1).toUpperCase();
    }

    final a = parts[0].isNotEmpty ? parts[0][0] : 'C';
    final b = parts[1].isNotEmpty ? parts[1][0] : 'L';
    return ('$a$b').toUpperCase();
  }

  Color _parseHexToColor(
    String? hex, {
    Color fallback = const Color(0xFF6D28D9),
  }) {
    final h = (hex ?? '').trim();
    if (h.isEmpty) return fallback;
    final v = h.replaceAll('#', '');
    try {
      if (v.length == 6) return Color(int.parse('FF$v', radix: 16));
      if (v.length == 8) return Color(int.parse(v, radix: 16));
    } catch (_) {}
    return fallback;
  }

  PdfColor _pdfColorFromHex(
    String? hex, {
    PdfColor fallback = PdfColors.deepPurple,
  }) {
    final h = (hex ?? '').trim();
    if (h.isEmpty) return fallback;

    final v = h.replaceAll('#', '');
    try {
      if (v.length == 6) {
        final i = int.parse(v, radix: 16);
        final r = (i >> 16) & 0xFF;
        final g = (i >> 8) & 0xFF;
        final b = i & 0xFF;
        return PdfColor(r / 255.0, g / 255.0, b / 255.0);
      }
    } catch (_) {}
    return fallback;
  }

  String _money(num n) => n.toStringAsFixed(2);

  String _fmtIssueDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  String _payrollPeriodLabel(DateTime monthStart) => _fmtMonthLong(monthStart);

  String _genPayslipNo({
    required String clinicId,
    required DateTime monthStart,
    required String empId,
  }) {
    final y = monthStart.year.toString().padLeft(4, '0');
    final m = monthStart.month.toString().padLeft(2, '0');
    final c = clinicId.isNotEmpty ? clinicId : 'CLN';
    final e = empId.isNotEmpty ? empId : 'EMP';
    return 'PS-$y$m-$c-$e';
  }

  String _safeEmpId() {
    final staffId = _safeStaffIdForPayrollOrNull();
    if (staffId != null && staffId.isNotEmpty) return staffId;
    return widget.emp.id.trim();
  }

  String _safeEmpPosition() {
    return widget.emp.position.trim();
  }

  String _safeBranch() {
    try {
      final v = (widget.emp as dynamic).branch;
      return (v ?? '').toString().trim();
    } catch (_) {}
    try {
      final v = (widget.emp as dynamic).clinicName;
      return (v ?? '').toString().trim();
    } catch (_) {}
    return '';
  }

  Widget _brandHeaderCard(Color csPrimary) {
    final clinicName = (_clinic?.name.trim().isNotEmpty == true)
        ? _clinic!.name.trim()
        : 'Clinic';

    final abbr = (_clinic?.brandAbbr.trim().isNotEmpty == true)
        ? _clinic!.brandAbbr.trim().toUpperCase()
        : _abbrFromName(clinicName);

    final brandColor = _parseHexToColor(
      _clinic?.brandColor,
      fallback: csPrimary,
    );

    final srcText = (_vm?.fromBackend == true)
        ? 'ใช้ข้อมูลงวดปิดจริง'
        : (_remoteTried ? (_vm?.sourceLabel ?? 'ประมาณการ') : 'กำลังเตรียมข้อมูล...');

    return Card(
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: brandColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  abbr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clinicName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Payslip • ${_fmtMonthShort(_selectedMonth)}',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.65),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'พนักงาน: ${widget.emp.fullName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    srcText,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.55),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
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

  pw.Widget _kv(String k, String v, {bool bold = false}) {
    final st = pw.TextStyle(
      fontSize: 10.5,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 6, child: pw.Text(k, style: st)),
          pw.SizedBox(width: 8),
          pw.Expanded(
            flex: 6,
            child: pw.Text(v, style: st, textAlign: pw.TextAlign.right),
          ),
        ],
      ),
    );
  }

  pw.Widget _section(String t) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
      child: pw.Text(
        t,
        style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _signatureLine({required String label}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Container(width: 220, height: 1, color: PdfColors.grey500),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  pw.Document _buildPdf(_PayslipVM vm) {
    final pdf = pw.Document();

    final clinicId = _clinic?.clinicId.trim() ?? '';
    final clinicName = (_clinic?.name.trim().isNotEmpty == true)
        ? _clinic!.name.trim()
        : 'Clinic';

    final abbr = (_clinic?.brandAbbr.trim().isNotEmpty == true)
        ? _clinic!.brandAbbr.trim().toUpperCase()
        : _abbrFromName(clinicName);

    final PdfColor brandColor =
        _pdfColorFromHex(_clinic?.brandColor, fallback: PdfColors.deepPurple);

    final now = DateTime.now();
    final issueDate = _fmtIssueDate(now);
    final period = _payrollPeriodLabel(_selectedMonth);

    final empId = _safeEmpId();
    final empPos = _safeEmpPosition();
    final empBranch = _safeBranch();

    final payslipNo = _genPayslipNo(
      clinicId: clinicId,
      monthStart: _selectedMonth,
      empId: empId,
    );

    final themeData = (_pdfFontRegular != null && _pdfFontBold != null)
        ? pw.ThemeData.withFont(base: _pdfFontRegular!, bold: _pdfFontBold!)
        : null;

    final hasOtSnapshot = _hasMeaningfulOtSnapshot(vm);

    pdf.addPage(
      pw.MultiPage(
        theme: themeData,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 48,
                height: 48,
                decoration: pw.BoxDecoration(
                  color: brandColor,
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Center(
                  child: pw.Text(
                    abbr,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      clinicName,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'PAYSLIP • $period',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    _kv('Payslip No.', payslipNo, bold: true),
                    _kv('Issue Date', issueDate),
                    _kv('Payroll Period', period),
                    _kv('Source', vm.sourceLabel),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(),

          _section('Employee Info'),
          _kv('Name', widget.emp.fullName, bold: true),
          if (empId.isNotEmpty) _kv('Employee ID', empId),
          if (empPos.isNotEmpty) _kv('Position', empPos),
          _kv('Employment Type', vm.isPartTime ? 'Part-time' : 'Full-time'),
          if (empBranch.isNotEmpty) _kv('Branch/Clinic', empBranch),

          pw.Divider(),

          _section('Earnings'),
          _kv(
            vm.isPartTime ? 'Regular Pay' : 'Base Salary',
            '${_money(vm.grossBase)} THB',
          ),
          if (vm.bonus > 0) _kv('Bonus', '${_money(vm.bonus)} THB'),
          if (vm.otherAllowance > 0)
            _kv('Other Allowance', '${_money(vm.otherAllowance)} THB'),
          if (vm.otherDeduction > 0)
            _kv('Other Deduction', '-${_money(vm.otherDeduction)} THB'),
          if (vm.otPay > 0) _kv('OT Pay', '${_money(vm.otPay)} THB'),

          if (hasOtSnapshot) ...[
            pw.SizedBox(height: 6),
            pw.Container(height: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 6),
            pw.Text(
              'OT Approved',
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if ((vm.otApprovedMinutes ?? 0) > 0)
              _kv('Approved Minutes', '${vm.otApprovedMinutes} min'),
            if ((vm.otApprovedWeightedHours ?? 0) > 0)
              _kv(
                'Weighted Hours',
                vm.otApprovedWeightedHours!.toStringAsFixed(2),
              ),
            if ((vm.otApprovedCount ?? 0) > 0)
              _kv('Records', '${vm.otApprovedCount}'),
          ],

          pw.Divider(),
          _kv('Gross', '${_money(vm.grossMonthly)} THB', bold: true),

          _section('Deductions'),
          if (vm.withheldTaxMonthly > 0)
            _kv('Withholding Tax', '-${_money(vm.withheldTaxMonthly)} THB'),
          if (vm.ssoEmployeeMonthly > 0)
            _kv('Social Security', '-${_money(vm.ssoEmployeeMonthly)} THB'),
          if (vm.pvdEmployeeMonthly > 0)
            _kv('PVD', '-${_money(vm.pvdEmployeeMonthly)} THB'),
          pw.Divider(),

          _kv('Net Pay', '${_money(vm.netPay)} THB', bold: true),

          if (vm.isPartTime) _section('Work Hours (Part-time)'),
          if (vm.isPartTime)
            _kv(
              'Total Regular Hours',
              _parttimeRegularHours.toStringAsFixed(2),
              bold: true,
            ),
          if (vm.isPartTime && _parttimeWorkEntriesOfMonth.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          'Date',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          'Hours',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  ..._parttimeWorkEntriesOfMonth.map(
                    (e) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            e.date,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            e.hours.toStringAsFixed(2),
                            style: const pw.TextStyle(fontSize: 10),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          _signatureLine(label: 'Approved by (Signature)'),

          pw.SizedBox(height: 14),
          pw.Text(
            'Generated by Clinic Payroll • This document is for record purpose.',
            style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    return pdf;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vm = _vm;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตัวอย่างสลิปเงินเดือน'),
        actions: [
          TextButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month),
            label: Text(
              _monthKey(_selectedMonth),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'รีเฟรชข้อมูล',
            icon: const Icon(Icons.refresh),
            onPressed: _bootstrap,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : vm == null
                  ? const Center(child: Text('ไม่พบข้อมูลสำหรับสร้างสลิป'))
                  : Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          color: cs.primary.withOpacity(0.08),
                          child: Text(
                            'เดือนที่เลือก: ${_fmtMonthShort(_selectedMonth)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          child: _brandHeaderCard(cs.primary),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: PdfPreview(
                            canChangePageFormat: false,
                            canChangeOrientation: false,
                            build: (format) => _buildPdf(vm).save(),
                          ),
                        ),
                      ],
                    ),
    );
  }
}