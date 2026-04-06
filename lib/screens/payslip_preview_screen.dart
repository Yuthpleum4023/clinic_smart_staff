import 'dart:convert';

import 'package:flutter/foundation.dart';
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
import '../utils/payroll_calculator.dart';

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

class PayslipPreviewScreen extends StatefulWidget {
  final EmployeeModel emp;

  const PayslipPreviewScreen({super.key, required this.emp});

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
  String? _error;
  PayslipSummaryModel? _summary;
  bool _remoteTried = false;

  pw.Font? _pdfFontRegular;
  pw.Font? _pdfFontBold;

  void _log(String message, [Object? data]) {
    if (!kDebugMode) return;
    try {
      if (data == null) {
        debugPrint('[PAYSLIP_PREVIEW] $message');
      } else if (data is String) {
        debugPrint('[PAYSLIP_PREVIEW] $message: $data');
      } else {
        debugPrint('[PAYSLIP_PREVIEW] $message: ${jsonEncode(data)}');
      }
    } catch (_) {
      debugPrint('[PAYSLIP_PREVIEW] $message: $data');
    }
  }

  void _logSummary(String label, PayslipSummaryModel? s) {
    if (!kDebugMode || s == null) return;
    _log(label, {
      'month': s.month,
      'source': s.source,
      'isClosedPayroll': s.isClosedPayroll,
      'salary': s.salary,
      'socialSecurity': s.socialSecurity,
      'ot': s.ot,
      'commission': s.commission,
      'bonus': s.bonus,
      'leaveDeduction': s.leaveDeduction,
      'tax': s.tax,
      'netPay': s.netPay,
      'recomputedNet': s.recomputedNet,
      'hasMismatch': s.hasMismatch,
      'grossBaseModeApplied': s.grossBaseModeApplied,
      'lineItems': s.lineItems
          .map(
            (e) => {
              'keyName': e.keyName,
              'label': e.label,
              'amount': e.amount,
              'sign': e.sign,
            },
          )
          .toList(),
    });
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _log('INIT', {
      'selectedMonth': _monthKey(_selectedMonth),
      'employeeName': widget.emp.fullName,
      'employeeStaffId': widget.emp.staffId,
      'employeeId': widget.emp.id,
    });
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

    _log('MONTH PICKED', {
      'selectedMonth': _monthKey(_selectedMonth),
    });

    await _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    _log('BOOTSTRAP START', {
      'month': _monthKey(_selectedMonth),
      'employeeName': widget.emp.fullName,
      'safePayrollEmployeeId': _safeStaffIdForPayrollOrNull(),
    });

    try {
      await _loadPdfFonts();
      await _loadClinicBrand();
      await _loadRemoteClosedMonth();
    } catch (e, st) {
      _log('BOOTSTRAP ERROR', {
        'error': e.toString(),
        'stack': st.toString(),
      });
      _error = 'โหลดข้อมูลสลิปไม่สำเร็จ';
    }

    if (!mounted) return;
    setState(() => _loading = false);

    _log('BOOTSTRAP DONE', {
      'month': _monthKey(_selectedMonth),
      'hasSummary': _summary != null,
      'error': _error,
      'remoteTried': _remoteTried,
    });
    _logSummary('BOOTSTRAP SUMMARY', _summary);
  }

  Future<void> _loadPdfFonts() async {
    try {
      final dataRegular =
          await rootBundle.load('assets/fonts/NotoSansThai_Condensed-Regular.ttf');
      final dataBold =
          await rootBundle.load('assets/fonts/NotoSansThai_Condensed-Bold.ttf');

      _pdfFontRegular = pw.Font.ttf(dataRegular);
      _pdfFontBold = pw.Font.ttf(dataBold);

      _log('PDF FONTS LOADED');
    } catch (e) {
      _pdfFontRegular = null;
      _pdfFontBold = null;
      _log('PDF FONTS LOAD FAILED', e.toString());
    }
  }

  Future<String> _getTokenRobust() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.trim().isNotEmpty) {
        _log('TOKEN FOUND FROM AuthStorage', {
          'length': t.trim().length,
          'preview': t.trim().length >= 16
              ? '${t.trim().substring(0, 16)}...'
              : t.trim(),
        });
        return t.trim();
      }
    } catch (e) {
      _log('TOKEN READ FROM AuthStorage FAILED', e.toString());
    }

    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = (prefs.getString(k) ?? '').trim();
      if (v.isNotEmpty && v.toLowerCase() != 'null') {
        _log('TOKEN FOUND FROM SharedPreferences', {
          'key': k,
          'length': v.length,
          'preview': v.length >= 16 ? '${v.substring(0, 16)}...' : v,
        });
        return v;
      }
    }

    _log('TOKEN NOT FOUND');
    return '';
  }

  Future<String> _getClinicIdRobust() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _clinicIdKeys) {
      final v = (prefs.getString(k) ?? '').trim();
      if (v.isNotEmpty && v.toLowerCase() != 'null') {
        _log('CLINIC ID FOUND', {'key': k, 'clinicId': v});
        return v;
      }
    }
    _log('CLINIC ID NOT FOUND');
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

    _log('LOAD CLINIC BRAND START', {
      'clinicId': clinicId,
      'hasToken': token.isNotEmpty,
    });

    if (clinicId.isEmpty || token.isEmpty) {
      _log('LOAD CLINIC BRAND SKIPPED', {
        'reason': clinicId.isEmpty ? 'clinicId empty' : 'token empty',
      });
      return;
    }

    try {
      final uri = Uri.parse('$_payrollBaseUrl/clinics/$clinicId');
      _log('CLINIC GET REQUEST', {
        'url': uri.toString(),
      });

      final resp =
          await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      _log('CLINIC GET RESPONSE', {
        'statusCode': resp.statusCode,
        'url': uri.toString(),
        'body': resp.body,
      });

      if (resp.statusCode >= 400) return;

      final decoded = json.decode(resp.body);
      if (decoded is Map<String, dynamic>) {
        final c = _ClinicBrand.fromMap(decoded);
        _log('CLINIC PARSED', {
          'clinicId': c.clinicId,
          'name': c.name,
          'phone': c.phone,
          'address': c.address,
          'brandAbbr': c.brandAbbr,
          'brandColor': c.brandColor,
        });

        if (!mounted) return;
        setState(() => _clinic = c);
      }
    } catch (e, st) {
      _log('LOAD CLINIC BRAND ERROR', {
        'error': e.toString(),
        'stack': st.toString(),
      });
    }
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

    _log('PAYROLL EMPLOYEE ID CANDIDATES', {
      'candidates': candidates,
    });

    for (final c in candidates) {
      if (_hasPayrollEmployeeId(c)) return c;
    }

    return null;
  }

  Map<String, dynamic>? _extractClosedRowFromDecoded(dynamic decoded) {
    if (decoded is! Map) {
      _log('EXTRACT CLOSED ROW FAILED', {
        'reason': 'decoded is not Map',
        'runtimeType': decoded.runtimeType.toString(),
      });
      return null;
    }

    final m = Map<String, dynamic>.from(decoded);

    _log('EXTRACT CLOSED ROW ROOT KEYS', {
      'keys': m.keys.toList(),
    });

    final candidates = [
      m['payslipSummary'],
      m['row'],
      m['data'],
      m['payrollClose'],
      if (m['data'] is Map) (m['data'] as Map)['payslipSummary'],
      if (m['data'] is Map) (m['data'] as Map)['row'],
      if (m['data'] is Map) (m['data'] as Map)['payrollClose'],
    ];

    for (int i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      if (c is Map) {
        final row = Map<String, dynamic>.from(c);
        _log('EXTRACT CLOSED ROW SUCCESS FROM CANDIDATE', {
          'candidateIndex': i,
          'keys': row.keys.toList(),
          'row': row,
        });
        return row;
      }
    }

    final looksLikeRow = m.containsKey('amounts') ||
        m.containsKey('salary') ||
        m.containsKey('socialSecurity') ||
        m.containsKey('ot') ||
        m.containsKey('bonus') ||
        m.containsKey('commission') ||
        m.containsKey('leaveDeduction') ||
        m.containsKey('tax') ||
        m.containsKey('netPay') ||
        m.containsKey('grossBase');

    if (looksLikeRow) {
      _log('EXTRACT CLOSED ROW SUCCESS FROM ROOT MAP', {
        'keys': m.keys.toList(),
        'row': m,
      });
      return m;
    }

    _log('EXTRACT CLOSED ROW FAILED', {
      'reason': 'no known row shape found',
      'root': m,
    });

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

    _log('FETCH CLOSED MONTH START', {
      'employeeId': employeeId,
      'monthKey': monthKey,
      'candidateUrls': candidates.map((e) => e.toString()).toList(),
    });

    for (final u in candidates) {
      try {
        _log('GET CLOSED MONTH REQUEST', {
          'url': u.toString(),
          'headers': {
            'Authorization': 'Bearer ***',
            'Content-Type': headers['Content-Type'],
          },
        });

        final resp =
            await http.get(u, headers: headers).timeout(const Duration(seconds: 15));

        _log('GET CLOSED MONTH RESPONSE', {
          'url': u.toString(),
          'statusCode': resp.statusCode,
          'body': resp.body,
        });

        if (resp.statusCode == 404) {
          _log('GET CLOSED MONTH NOT FOUND', {'url': u.toString()});
          continue;
        }
        if (resp.statusCode != 200) {
          _log('GET CLOSED MONTH NON-200', {
            'url': u.toString(),
            'statusCode': resp.statusCode,
          });
          continue;
        }

        final decoded = json.decode(resp.body);
        _log('GET CLOSED MONTH DECODED', {
          'url': u.toString(),
          'decodedType': decoded.runtimeType.toString(),
          'decoded': decoded,
        });

        final row = _extractClosedRowFromDecoded(decoded);
        if (row != null) {
          _log('GET CLOSED MONTH FINAL ROW', {
            'url': u.toString(),
            'row': row,
          });
          return row;
        }

        _log('GET CLOSED MONTH ROW NOT EXTRACTED', {'url': u.toString()});
      } catch (e, st) {
        _log('GET CLOSED MONTH ERROR', {
          'url': u.toString(),
          'error': e.toString(),
          'stack': st.toString(),
        });
      }
    }

    _log('FETCH CLOSED MONTH FAILED', {
      'employeeId': employeeId,
      'monthKey': monthKey,
    });
    return null;
  }

  Future<void> _loadRemoteClosedMonth() async {
    final token = await _getTokenRobust();
    final monthKey = _monthKey(_selectedMonth);
    final staffId = _safeStaffIdForPayrollOrNull();

    _log('LOAD REMOTE CLOSED MONTH START', {
      'monthKey': monthKey,
      'staffId': staffId,
      'hasToken': token.isNotEmpty,
    });

    if (token.isEmpty || staffId == null || staffId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _remoteTried = true;
        _summary = null;
        _error = 'ไม่พบ token หรือ employeeId สำหรับโหลดสลิป';
      });

      _log('LOAD REMOTE CLOSED MONTH SKIPPED', {
        'reason': token.isEmpty ? 'token empty' : 'staffId empty',
        'monthKey': monthKey,
        'staffId': staffId,
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
        _error = 'ไม่พบข้อมูลงวดปิดจริงสำหรับเดือนนี้';
      });

      _log('LOAD REMOTE CLOSED MONTH NO ROW', {
        'monthKey': monthKey,
        'staffId': staffId,
      });
      return;
    }

    _log('LOAD REMOTE CLOSED MONTH ROW RECEIVED', row);

    final summary = PayslipSummaryModel.fromMap(row);
    _logSummary('SUMMARY FROM MAP', summary);

    if (!mounted) return;
    setState(() {
      _summary = summary;
    });

    _logSummary('SUMMARY SETSTATE DONE', _summary);
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

  bool _isPartTime() => PayrollCalculator.isPartTime(widget.emp);

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

    final srcText = (_summary?.isClosedPayroll == true)
        ? 'ใช้ข้อมูลงวดปิดจริง'
        : (_remoteTried ? (_summary?.source ?? 'ไม่พบข้อมูล') : 'กำลังเตรียมข้อมูล...');

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

  pw.Document _buildPdf(PayslipSummaryModel summary) {
    _logSummary('PDF BUILD INPUT SUMMARY', summary);

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

    _log('PDF BUILD META', {
      'clinicId': clinicId,
      'clinicName': clinicName,
      'abbr': abbr,
      'issueDate': issueDate,
      'period': period,
      'empId': empId,
      'empPos': empPos,
      'empBranch': empBranch,
      'payslipNo': payslipNo,
      'lineItems': summary.lineItems
          .map(
            (e) => {
              'keyName': e.keyName,
              'label': e.label,
              'amount': e.amount,
              'sign': e.sign,
              'included': e.amount > 0 || e.keyName == 'salary',
            },
          )
          .toList(),
      'netPay': summary.netPay,
      'recomputedNet': summary.recomputedNet,
      'hasMismatch': summary.hasMismatch,
    });

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
                    _kv('Source', summary.source),
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
          _kv('Employment Type', _isPartTime() ? 'Part-time' : 'Full-time'),
          if (empBranch.isNotEmpty) _kv('Branch/Clinic', empBranch),

          pw.Divider(),

          _section('Summary'),
          for (final item in summary.lineItems)
            if (item.amount > 0 || item.keyName == 'salary')
              _kv(
                item.label,
                '${item.sign}${_money(item.amount)} THB',
              ),

          pw.Divider(),
          _kv('เงินรับจริง', '${_money(summary.netPay)} THB', bold: true),

          if (summary.hasMismatch) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Recomputed Net: ${_money(summary.recomputedNet)} THB',
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColors.red700,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],

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

  Widget _buildSummaryCard(PayslipSummaryModel summary) {
    _logSummary('SUMMARY CARD INPUT', summary);

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
            if (summary.hasMismatch) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ตรวจสอบ: ยอดรวมจากรายการ = ${_money(summary.recomputedNet)}',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final summary = _summary;

    _log('BUILD', {
      'loading': _loading,
      'error': _error,
      'hasSummary': summary != null,
      'selectedMonth': _monthKey(_selectedMonth),
      'remoteTried': _remoteTried,
    });
    _logSummary('BUILD SUMMARY', summary);

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
              : summary == null
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
                        _buildSummaryCard(summary),
                        const SizedBox(height: 4),
                        Expanded(
                          child: PdfPreview(
                            key: ValueKey(_pdfPreviewKey(summary)),
                            canChangePageFormat: false,
                            canChangeOrientation: false,
                            build: (format) {
                              _log('PDF PREVIEW BUILD TRIGGERED', {
                                'pageFormat': format.toString(),
                                'selectedMonth': _monthKey(_selectedMonth),
                              });
                              _logSummary('PDF PREVIEW CURRENT SUMMARY', summary);
                              return _buildPdf(summary).save();
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}