// lib/screens/payslip_preview_screen.dart
//
// PRODUCTION — Backend-only Payslip Preview

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart' show PdfColor, PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';
import '../models/employee_model.dart';
import '../models/payslip_summary_model.dart';
import '../services/auth_storage.dart';

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
    final dynamic rawClinic = m['clinic'];
    final c = rawClinic is Map
        ? Map<String, dynamic>.from(rawClinic)
        : Map<String, dynamic>.from(m);

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

class PayslipPreviewScreen extends StatefulWidget {
  final EmployeeModel emp;

  const PayslipPreviewScreen({
    super.key,
    required this.emp,
  });

  @override
  State<PayslipPreviewScreen> createState() => _PayslipPreviewScreenState();
}

class _PayslipPreviewScreenState extends State<PayslipPreviewScreen> {
  String get _payrollBaseUrl =>
      ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');

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
  late DateTime _selectedMonth;

  _ClinicBrand? _clinic;
  PayslipSummaryModel? _summary;

  String? _error;
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

  String _fmtMonthShort(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtMonthLong(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.year}';

  String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  String _pdfPreviewKey(PayslipSummaryModel summary) {
    return [
      summary.month,
      summary.source,
      summary.salary.toStringAsFixed(2),
      summary.socialSecurity.toStringAsFixed(2),
      summary.ot.toStringAsFixed(2),
      summary.commission.toStringAsFixed(2),
      summary.bonus.toStringAsFixed(2),
      summary.leaveDeduction.toStringAsFixed(2),
      summary.tax.toStringAsFixed(2),
      summary.netPay.toStringAsFixed(2),
      summary.grossBaseModeApplied,
    ].join('|');
  }

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
      _summary = null;
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
      await _loadClinicBrand();
      await _loadRemoteClosedMonth();
    } catch (_) {
      _error = 'โหลดข้อมูลสลิปไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadPdfFonts() async {
    try {
      final dataRegular = await rootBundle.load(
        'assets/fonts/NotoSansThai_Condensed-Regular.ttf',
      );
      final dataBold = await rootBundle.load(
        'assets/fonts/NotoSansThai_Condensed-Bold.ttf',
      );

      _pdfFontRegular = pw.Font.ttf(dataRegular);
      _pdfFontBold = pw.Font.ttf(dataBold);
    } catch (_) {
      _pdfFontRegular = null;
      _pdfFontBold = null;
    }
  }

  Future<String> _getTokenRobust() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.trim().isNotEmpty) return t.trim();
    } catch (_) {}

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

  String tryGetString(dynamic Function() getter) {
    try {
      return (getter() ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadClinicBrand() async {
    final token = await _getTokenRobust();
    final clinicId = await _getClinicIdRobust();

    if (clinicId.isEmpty || token.isEmpty) return;

    try {
      final uri = Uri.parse('$_payrollBaseUrl/clinics/$clinicId');
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 400) return;

      final decoded = json.decode(resp.body);
      if (decoded is Map) {
        final c = _ClinicBrand.fromMap(
          Map<String, dynamic>.from(decoded),
        );

        if (!mounted) return;
        setState(() => _clinic = c);
      }
    } catch (_) {}
  }

  bool _hasPayrollEmployeeId(String v) => v.trim().isNotEmpty;

  String? _safeStaffIdForPayrollOrNull() {
    final candidates = <String>[
      widget.emp.staffId.trim(),
      widget.emp.id.trim(),
      tryGetString(() => (widget.emp as dynamic).employeeId),
      tryGetString(() => (widget.emp as dynamic).staffID),
      tryGetString(() => (widget.emp as dynamic).staff_id),
    ].where((e) => e.isNotEmpty).toList();

    for (final c in candidates) {
      if (_hasPayrollEmployeeId(c)) return c;
    }

    return null;
  }

  Map<String, dynamic>? _extractClosedRowFromDecoded(dynamic decoded) {
    if (decoded is! Map) return null;

    final m = Map<String, dynamic>.from(decoded);

    final candidates = [
      m['payslipSummary'],
      m['row'],
      m['payrollClose'],
      m['data'],
      if (m['data'] is Map) (m['data'] as Map)['payslipSummary'],
      if (m['data'] is Map) (m['data'] as Map)['row'],
      if (m['data'] is Map) (m['data'] as Map)['payrollClose'],
    ];

    for (final c in candidates) {
      if (c is Map) {
        return Map<String, dynamic>.from(
          c.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    }

    final looksLikeSummary = m.containsKey('amounts') ||
        m.containsKey('salary') ||
        m.containsKey('socialSecurity') ||
        m.containsKey('ot') ||
        m.containsKey('bonus') ||
        m.containsKey('commission') ||
        m.containsKey('leaveDeduction') ||
        m.containsKey('tax') ||
        m.containsKey('netPay') ||
        m.containsKey('grossBase');

    return looksLikeSummary ? m : null;
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
      Uri.parse(
        '$_payrollBaseUrl/payroll-close/close-month/$employeeId/$monthKey',
      ),
      Uri.parse(
        '$_payrollBaseUrl/api/payroll-close/close-month/$employeeId/$monthKey',
      ),
    ];

    for (final u in candidates) {
      try {
        final resp = await http
            .get(u, headers: headers)
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode == 404) continue;
        if (resp.statusCode != 200) continue;

        final decoded = json.decode(resp.body);
        final row = _extractClosedRowFromDecoded(decoded);

        if (row != null) return row;
      } catch (_) {}
    }

    return null;
  }

  Future<void> _loadRemoteClosedMonth() async {
    final token = await _getTokenRobust();
    final monthKey = _monthKey(_selectedMonth);
    final staffId = _safeStaffIdForPayrollOrNull();

    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _remoteTried = true;
        _summary = null;
        _error = 'ไม่พบสิทธิ์เข้าใช้งาน กรุณาออกจากระบบแล้วเข้าใหม่';
      });
      return;
    }

    if (staffId == null || staffId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _remoteTried = true;
        _summary = null;
        _error = 'ไม่พบข้อมูลพนักงานสำหรับโหลดสลิป';
      });
      return;
    }

    final row = await _fetchClosedMonth(
      token: token,
      employeeId: staffId,
      monthKey: monthKey,
    );

    _remoteTried = true;

    if (row == null) {
      if (!mounted) return;
      setState(() {
        _summary = null;
        _error = 'ยังไม่มีสลิปเงินเดือนที่ปิดงวดแล้วสำหรับเดือนนี้';
      });
      return;
    }

    final summary = PayslipSummaryModel.fromMap(row);

    if (!mounted) return;
    setState(() {
      _summary = summary;
      _error = null;
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

  bool _isPartTime() => widget.emp.isPartTime;

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

  String _summarySourceText(PayslipSummaryModel? summary) {
    if (summary == null) {
      return _remoteTried ? 'ไม่พบข้อมูลงวดนี้' : 'กำลังโหลดข้อมูล';
    }

    if (summary.isClosedPayroll) {
      return 'งวดเงินเดือนที่ปิดแล้ว';
    }

    return 'ข้อมูลจากระบบเงินเดือน';
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
                    'สลิปเงินเดือน • ${_fmtMonthShort(_selectedMonth)}',
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
                    _summarySourceText(_summary),
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

  pw.Document _buildPdf(PayslipSummaryModel summary) {
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
                    _kv('เลขที่สลิป', payslipNo, bold: true),
                    _kv('วันที่ออกเอกสาร', issueDate),
                    _kv('งวดเงินเดือน', period),
                    _kv('แหล่งข้อมูล', 'ระบบเงินเดือน'),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(),
          _section('ข้อมูลพนักงาน'),
          _kv('ชื่อ-นามสกุล', widget.emp.fullName, bold: true),
          if (empId.isNotEmpty) _kv('รหัสพนักงาน', empId),
          if (empPos.isNotEmpty) _kv('ตำแหน่ง', empPos),
          _kv('ประเภทพนักงาน', _isPartTime() ? 'Part-time' : 'Full-time'),
          if (empBranch.isNotEmpty) _kv('สาขา/คลินิก', empBranch),
          pw.Divider(),
          _section('สรุปรายการ'),
          for (final item in summary.lineItems)
            if (item.amount > 0 || item.keyName == 'salary')
              _kv(
                item.label,
                '${item.sign}${_money(item.amount)} บาท',
              ),
          pw.Divider(),
          _kv('เงินรับจริง', '${_money(summary.netPay)} บาท', bold: true),
          _signatureLine(label: 'ผู้อนุมัติ'),
          pw.SizedBox(height: 14),
          pw.Text(
            'เอกสารนี้สร้างจากระบบ Clinic Smart Staff',
            style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    return pdf;
  }

  Widget _buildSummaryCard(PayslipSummaryModel summary) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            for (final item in summary.lineItems)
              if (item.amount > 0 || item.keyName == 'salary')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${item.sign}${_money(item.amount)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            const Divider(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'เงินรับจริง',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  _money(summary.netPay),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final msg = _error ?? 'ไม่พบข้อมูลสำหรับสร้างสลิป';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 46),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองโหลดใหม่'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final summary = _summary;

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
          : summary == null || _error != null
              ? _buildErrorState()
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
                    _buildSummaryCard(summary),
                    const SizedBox(height: 4),
                    Expanded(
                      child: PdfPreview(
                        key: ValueKey(_pdfPreviewKey(summary)),
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        build: (_) => _buildPdf(summary).save(),
                      ),
                    ),
                  ],
                ),
    );
  }
}