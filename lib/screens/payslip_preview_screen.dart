// lib/screens/payslip_preview_screen.dart
//
// ✅ Payslip Preview PDF (เลือกเดือนได้ + แสดงรายละเอียด)
// - โหลด SSO% จาก prefs: settings_sso_percent
// - โหลด Part-time work hours รายวันจาก prefs: work_entries_{emp.id} (List<{date,hours}>)
// - แสดง OT รายการไหนบ้างในเดือนนั้น (ตารางใน PDF)
// - แสดง Part-time ทำงานวันไหนกี่ชั่วโมงบ้าง (ตารางใน PDF)
// - ใช้ relative import ทั้งหมด

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart'; // ✅ PdfColors
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/employee_model.dart';
import '../utils/payroll_calculator.dart';

class _WorkHourEntryLite {
  final String date; // yyyy-MM-dd
  final double hours;

  const _WorkHourEntryLite({required this.date, required this.hours});

  factory _WorkHourEntryLite.fromMap(Map<String, dynamic> map) {
    return _WorkHourEntryLite(
      date: map['date'] ?? '',
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

class PayslipPreviewScreen extends StatefulWidget {
  final EmployeeModel emp;

  const PayslipPreviewScreen({super.key, required this.emp});

  @override
  State<PayslipPreviewScreen> createState() => _PayslipPreviewScreenState();
}

class _PayslipPreviewScreenState extends State<PayslipPreviewScreen> {
  static const String _ssoKey = 'settings_sso_percent';

  // ให้ตรงกับ PayrollCalculator default
  static const int _workDaysPerMonth = 26;
  static const int _hoursPerDay = 8;

  bool _loading = true;
  double _ssoPercent = 5.0;
  double _parttimeRegularHours = 0.0;

  // ✅ list รายวันสำหรับ Part-time (ไว้ทำตาราง)
  List<_WorkHourEntryLite> _parttimeWorkEntriesOfMonth = [];

  // ✅ เลือกเดือน
  late DateTime _selectedMonth; // ใช้วันที่ 1 ของเดือนเสมอ

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _loadSettingsAndWorkHours();
  }

  int get _year => _selectedMonth.year;
  int get _month => _selectedMonth.month;

  String _fmtMonth(DateTime d) => '${d.month}/${d.year}';

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
      helpText: 'เลือกเดือน (เลือกวันใดก็ได้ ระบบจะใช้เฉพาะเดือน/ปี)',
    );

    if (picked == null) return;

    setState(() {
      _loading = true;
      _selectedMonth = DateTime(picked.year, picked.month, 1);
    });

    await _loadSettingsAndWorkHours();
  }

  // ---------- PDF helpers ----------
  pw.Widget _otTable({
    required List<OTEntry> ots,
    required double hourlyRate,
  }) {
    if (ots.isEmpty) {
      return pw.Text('ไม่มี OT ในเดือนนี้');
    }

    // sort by date then start
    ots.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      return a.start.compareTo(b.start);
    });

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(2), // date
        1: pw.FlexColumnWidth(2), // time
        2: pw.FlexColumnWidth(1), // hours
        3: pw.FlexColumnWidth(1), // x
        4: pw.FlexColumnWidth(2), // amount
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('วันที่', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('เวลา', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('ชม.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('x', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('จำนวนเงิน', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
        ...ots.map((e) {
          final pay = e.hours * hourlyRate * e.multiplier;
          return pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(e.date)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${e.start}–${e.end}')),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(e.hours.toStringAsFixed(2))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(e.multiplier.toStringAsFixed(1))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(pay.toStringAsFixed(2))),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _parttimeWorkTable(List<_WorkHourEntryLite> works) {
    if (works.isEmpty) {
      return pw.Text('ไม่มีเวลางานในเดือนนี้');
    }

    // sort by date
    works.sort((a, b) => a.date.compareTo(b.date));

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('วันที่', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('ชั่วโมง', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
        ...works.map(
          (e) => pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(e.date)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(e.hours.toStringAsFixed(2))),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Load prefs ----------
  Future<void> _loadSettingsAndWorkHours() async {
    final prefs = await SharedPreferences.getInstance();
    final sso = prefs.getDouble(_ssoKey) ?? 5.0;

    double partHours = 0.0;
    List<_WorkHourEntryLite> partEntriesMonth = [];

    if (PayrollCalculator.isPartTime(widget.emp)) {
      final key = 'work_entries_${widget.emp.id}';
      final raw = prefs.getString(key);

      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = json.decode(raw);
          if (decoded is List) {
            final all = decoded
                .whereType<Map>()
                .map((m) => _WorkHourEntryLite.fromMap(
                      Map<String, dynamic>.from(m),
                    ))
                .toList();

            for (final e in all) {
              if (e.isInMonth(_year, _month)) {
                partHours += e.hours;
                partEntriesMonth.add(e);
              }
            }
          }
        } catch (_) {
          partHours = 0.0;
          partEntriesMonth = [];
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _ssoPercent = sso;
      _parttimeRegularHours = partHours;
      _parttimeWorkEntriesOfMonth = partEntriesMonth;
      _loading = false;
    });
  }

  // ---------- Build PDF ----------
  pw.Document _buildPdf(PayrollMonthResult r) {
    final pdf = pw.Document();
    String monthLabel() => '${r.month}/${r.year}';

    // OT list ของเดือนที่เลือก
    final otOfMonth = widget.emp.otEntries
        .where((e) => e.isInMonth(r.year, r.month))
        .toList();

    // อัตราต่อชั่วโมงที่ใช้คำนวณ “แถว OT” ในตาราง
    final hourlyRate = r.isPartTime
        ? r.hourlyWage
        : widget.emp.hourlyRate(
            workDaysPerMonth: _workDaysPerMonth,
            hoursPerDay: _hoursPerDay,
          );

    pdf.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'PAYSLIP - CLINIC PAYROLL',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text('Month: ${monthLabel()}'),
            pw.Divider(),

            pw.Text('Employee: ${widget.emp.fullName}'),
            pw.Text('Position: ${widget.emp.position}'),
            pw.SizedBox(height: 10),

            // ---------- Summary ----------
            if (!r.isPartTime) ...[
              pw.Text('Type: Full-time'),
              pw.Text('Base Salary: ${r.monthlyBaseSalary.toStringAsFixed(2)} THB'),
              pw.Text('Bonus/Other: ${r.bonus.toStringAsFixed(2)} THB'),
              pw.Text('OT Hours: ${r.otHours.toStringAsFixed(2)} hrs'),
              pw.Text('OT Pay: ${r.otPay.toStringAsFixed(2)} THB'),
              pw.Text(
                'Social Security (${_ssoPercent.toStringAsFixed(2)}%, cap 750): -${r.socialSecurity.toStringAsFixed(2)} THB',
              ),
              pw.Text(
                'Absent Deduction (${widget.emp.absentDays} days): -${r.absentDeduction.toStringAsFixed(2)} THB',
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Hourly rate (from salary): ${hourlyRate.toStringAsFixed(2)} THB/hr',
                style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
              ),
            ] else ...[
              pw.Text('Type: Part-time'),
              pw.Text('Hourly Wage: ${r.hourlyWage.toStringAsFixed(2)} THB/hr'),
              pw.Text('Regular Hours: ${r.regularHours.toStringAsFixed(2)} hrs'),
              pw.Text('Regular Pay: ${r.regularPay.toStringAsFixed(2)} THB'),
              pw.Text('OT Hours: ${r.otHours.toStringAsFixed(2)} hrs'),
              pw.Text('OT Pay: ${r.otPay.toStringAsFixed(2)} THB'),
              if (r.bonus > 0) pw.Text('Bonus/Other: ${r.bonus.toStringAsFixed(2)} THB'),
              pw.Text('Note: Part-time has no Social Security deduction.'),
            ],

            pw.Divider(),
            pw.Text(
              'NET PAYABLE: ${r.net.toStringAsFixed(2)} THB',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),

            // ---------- Details ----------
            pw.SizedBox(height: 14),

            if (r.isPartTime) ...[
              pw.Text(
                'รายละเอียดเวลางาน (Part-time) — เดือน ${monthLabel()}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              _parttimeWorkTable(_parttimeWorkEntriesOfMonth),
              pw.SizedBox(height: 14),
            ],

            pw.Text(
              'รายละเอียด OT — เดือน ${monthLabel()}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            _otTable(
              ots: otOfMonth,
              hourlyRate: hourlyRate,
            ),
          ],
        ),
      ),
    );

    return pdf;
  }

  @override
  Widget build(BuildContext context) {
    // ✅ คำนวณตามเดือนที่เลือก
    final r = PayrollCalculator.computeMonth(
      emp: widget.emp,
      year: _year,
      month: _month,
      ssoPercent: _ssoPercent,
      parttimeRegularHours: _parttimeRegularHours,
      workDaysPerMonth: _workDaysPerMonth,
      hoursPerDay: _hoursPerDay,
    );

    final pdf = _buildPdf(r);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตัวอย่างสลิปเงินเดือน'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'เลือกเดือน',
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickMonth,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ✅ แถบแสดงเดือนที่เลือก
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  color: Colors.blue.withOpacity(0.08),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'เดือนที่เลือก: ${_fmtMonth(_selectedMonth)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: _pickMonth,
                        child: const Text('เปลี่ยนเดือน'),
                      ),
                    ],
                  ),
                ),

                // ✅ PDF Preview
                Expanded(
                  child: PdfPreview(
                    build: (format) => pdf.save(),
                    allowPrinting: true,
                    allowSharing: true,
                    canChangePageFormat: true,
                    canChangeOrientation: true,
                    useActions: true,
                  ),
                ),
              ],
            ),
    );
  }
}
