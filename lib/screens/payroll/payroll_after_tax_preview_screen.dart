// lib/screens/payroll/payroll_after_tax_preview_screen.dart
//
// PRODUCTION — Payroll Preview Screen
//
// หน้านี้ทำหน้าที่:
// - ส่งข้อมูลประกอบการปิดงวด
// - แสดงผลเงินเดือนจากระบบเงินเดือน
// - ยืนยันปิดงวดเงินจริง
//
// หมายเหตุ:
// - หน้านี้ไม่คำนวณยอดเงินจริงเอง
// - ยอดเงินเดือน, OT, ประกันสังคม, ภาษี และเงินรับจริงมาจากระบบเงินเดือน

import 'package:flutter/material.dart';

import '../../api/payroll_close_api.dart';

class PayrollAfterTaxPreviewScreen extends StatefulWidget {
  final double grossMonthly;
  final double ssoEmployeeMonthly;

  final int? year;

  final String clinicId;
  final String employeeId;

  final double otPay;
  final double bonus;
  final double otherAllowance;
  final double otherDeduction;
  final double pvdEmployeeMonthly;

  final String? closeMonth;

  final String taxMode;
  final double withholdingPercent;
  final double? withholdingAmount;

  final bool allowSelfAnnualTaxEngine;

  final double detailNetBeforeOt;
  final double detailLeaveDeduction;
  final double detailOtAmount;
  final double detailGrossBeforeTax;
  final double detailSsoAmount;
  final double detailTaxAmount;
  final double detailNetPay;
  final double detailOtHours;

  final String? employeeUserId;

  final double? regularWorkHours;
  final int? regularWorkMinutes;
  final List<Map<String, dynamic>>? workItems;

  const PayrollAfterTaxPreviewScreen({
    super.key,
    required this.grossMonthly,
    this.ssoEmployeeMonthly = 0,
    this.year,
    required this.clinicId,
    required this.employeeId,
    this.otPay = 0,
    this.bonus = 0,
    this.otherAllowance = 0,
    this.otherDeduction = 0,
    this.pvdEmployeeMonthly = 0,
    this.closeMonth,
    this.taxMode = 'annual',
    this.withholdingPercent = 0,
    this.withholdingAmount,
    this.allowSelfAnnualTaxEngine = false,
    this.detailNetBeforeOt = 0,
    this.detailLeaveDeduction = 0,
    this.detailOtAmount = 0,
    this.detailGrossBeforeTax = 0,
    this.detailSsoAmount = 0,
    this.detailTaxAmount = 0,
    this.detailNetPay = 0,
    this.detailOtHours = 0,
    this.employeeUserId,
    this.regularWorkHours,
    this.regularWorkMinutes,
    this.workItems,
  });

  @override
  State<PayrollAfterTaxPreviewScreen> createState() =>
      _PayrollAfterTaxPreviewScreenState();
}

class _LineItem {
  final String label;
  final String sign;
  final double amount;

  const _LineItem({
    required this.label,
    required this.sign,
    required this.amount,
  });
}

class _PayrollPreviewData {
  final Map<String, dynamic> raw;
  final Map<String, dynamic> payslipSummary;
  final Map<String, dynamic> amounts;
  final Map<String, dynamic> displaySnapshot;
  final Map<String, dynamic> otSummary;
  final Map<String, dynamic> payrollInputsResolved;
  final Map<String, dynamic> row;
  final Map<String, dynamic> snapshot;

  const _PayrollPreviewData({
    required this.raw,
    required this.payslipSummary,
    required this.amounts,
    required this.displaySnapshot,
    required this.otSummary,
    required this.payrollInputsResolved,
    required this.row,
    required this.snapshot,
  });

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;

    if (v is Map) {
      return Map<String, dynamic>.from(
        v.map((k, val) => MapEntry(k.toString(), val)),
      );
    }

    return <String, dynamic>{};
  }

  static double _readNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0.0;
  }

  static String _readStr(dynamic v) => (v ?? '').toString().trim();

  factory _PayrollPreviewData.fromMap(Map<String, dynamic> m) {
    final payslipSummary = _asMap(m['payslipSummary']);
    final amounts = _asMap(payslipSummary['amounts']);
    final displaySnapshot = _asMap(m['displaySnapshot']);
    final otSummary = _asMap(m['otSummary']);
    final payrollInputsResolved = _asMap(m['payrollInputsResolved']);
    final row = _asMap(m['row']);
    final snapshot = _asMap(row['snapshot']);

    return _PayrollPreviewData(
      raw: m,
      payslipSummary: payslipSummary,
      amounts: amounts,
      displaySnapshot: displaySnapshot,
      otSummary: otSummary,
      payrollInputsResolved: payrollInputsResolved,
      row: row,
      snapshot: snapshot,
    );
  }

  int get taxYear {
    final y = _readNum(snapshot['taxYear']).toInt();
    if (y > 0) return y;
    return DateTime.now().year;
  }

  String get taxMode => _readStr(raw['taxMode']);

  String get employmentType =>
      _readStr(payrollInputsResolved['employmentType']);

  double get salary => _readNum(amounts['salary']);
  double get socialSecurity => _readNum(amounts['socialSecurity']);
  double get ot => _readNum(amounts['ot']);
  double get commission => _readNum(amounts['commission']);
  double get bonus => _readNum(amounts['bonus']);
  double get leaveDeduction => _readNum(amounts['leaveDeduction']);
  double get tax => _readNum(amounts['tax']);
  double get pvd => _readNum(amounts['pvd']);
  double get netPay => _readNum(amounts['netPay']);

  double get grossBeforeTax {
    final fromAmounts = _readNum(amounts['grossBeforeTax']);
    if (fromAmounts > 0) return fromAmounts;

    return _readNum(displaySnapshot['grossBeforeTax']);
  }

  double get otHours => _readNum(displaySnapshot['otHours']);

  int get approvedMinutes => _readNum(otSummary['approvedMinutes']).toInt();
  int get approvedCount => _readNum(otSummary['count']).toInt();

  double get approvedWeightedHours =>
      _readNum(otSummary['approvedWeightedHours']);
}

class _PayrollAfterTaxPreviewScreenState
    extends State<PayrollAfterTaxPreviewScreen> {
  bool _loading = true;
  bool _closing = false;

  String? _error;
  late String _pickedCloseMonth;

  _PayrollPreviewData? _preview;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    final cm = (widget.closeMonth ?? '').trim();

    _pickedCloseMonth = cm.isNotEmpty
        ? cm
        : '${now.year}-${now.month.toString().padLeft(2, '0')}';

    _load();
  }

  String _money(num n) => n.toStringAsFixed(2);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  bool _isYm(String v) => RegExp(r'^\d{4}-\d{2}$').hasMatch(v.trim());

  bool _isValidStaffId(String v) => v.trim().isNotEmpty;

  String get _safeTaxMode {
    final v = widget.taxMode.trim().toLowerCase();

    if (v == 'none' || v == 'no_withholding') return 'none';
    if (v == 'withholding') return 'withholding';

    return 'annual';
  }

  String get _apiTaxMode {
    return _safeTaxMode == 'none' ? 'NO_WITHHOLDING' : 'WITHHOLDING';
  }

  String _taxModeLabel(String mode) {
    final raw = mode.trim();
    final m = raw.toUpperCase();

    if (m == 'NO_WITHHOLDING' || raw == 'none') {
      return 'ไม่หักภาษี';
    }

    if (raw == 'withholding' || m == 'WITHHOLDING') {
      return 'หักภาษี ณ ที่จ่าย';
    }

    return 'คำนวณภาษีตามระบบเงินเดือน';
  }

  String _employmentTypeLabel(String raw) {
    final t = raw.trim().toLowerCase();

    if (t == 'parttime' ||
        t == 'part-time' ||
        t == 'part_time' ||
        t == 'part time' ||
        t == 'hourly') {
      return 'Part-time';
    }

    if (t == 'fulltime' ||
        t == 'full-time' ||
        t == 'full_time' ||
        t == 'full time' ||
        t == 'monthly') {
      return 'Full-time';
    }

    return raw.trim().isEmpty ? '-' : raw.trim();
  }

  List<_LineItem> _buildLineItems(_PayrollPreviewData p) {
    return [
      _LineItem(label: 'เงินเดือน/ค่าจ้าง', sign: '', amount: p.salary),
      _LineItem(label: 'ประกันสังคม', sign: '-', amount: p.socialSecurity),
      _LineItem(label: 'ค่า OT', sign: '+', amount: p.ot),
      _LineItem(
        label: 'ค่าคอมมิชชั่น/รายได้อื่น',
        sign: '+',
        amount: p.commission,
      ),
      _LineItem(label: 'โบนัส', sign: '+', amount: p.bonus),
      _LineItem(label: 'หักวันลา/ขาด', sign: '-', amount: p.leaveDeduction),
      _LineItem(label: 'ภาษี', sign: '-', amount: p.tax),
      _LineItem(label: 'กองทุนสำรองเลี้ยงชีพ (PVD)', sign: '-', amount: p.pvd),
    ];
  }

  String _friendlyLoadError(Object e) {
    final msg = e.toString();

    if (msg.contains('401')) {
      return 'สิทธิ์หมดอายุ กรุณาออกจากระบบแล้วเข้าใหม่';
    }

    if (msg.contains('403')) {
      return 'ไม่มีสิทธิ์ดูข้อมูลเงินเดือน';
    }

    if (msg.contains('404')) {
      return 'ไม่พบข้อมูลงวดเงินเดือนนี้';
    }

    if (msg.contains('timeout') || msg.contains('SocketException')) {
      return 'เชื่อมต่อระบบไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ต';
    }

    return 'โหลดข้อมูลเงินเดือนไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  String _friendlyCloseError(Object e) {
    final msg = e.toString();

    if (msg.contains('409') || msg.toLowerCase().contains('already closed')) {
      return 'เดือนนี้ถูกปิดงวดไปแล้ว';
    }

    if (msg.contains('401')) {
      return 'สิทธิ์หมดอายุ กรุณาออกจากระบบแล้วเข้าใหม่';
    }

    if (msg.contains('403')) {
      return 'ไม่มีสิทธิ์ปิดงวดเงินเดือน';
    }

    if (msg.contains('404')) {
      return 'ไม่พบข้อมูลพนักงานหรืองวดเงินเดือน';
    }

    if (msg.contains('timeout') || msg.contains('SocketException')) {
      return 'เชื่อมต่อระบบไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ต';
    }

    return 'ปิดงวดไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  Future<void> _load() async {
    if (!mounted) return;

    final clinicId = widget.clinicId.trim();
    final staffId = widget.employeeId.trim();
    final month = _pickedCloseMonth.trim();

    if (clinicId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'ไม่พบข้อมูลคลินิก กรุณาออกจากระบบแล้วเข้าใหม่';
      });
      return;
    }

    if (!_isValidStaffId(staffId)) {
      setState(() {
        _loading = false;
        _error = 'ไม่พบข้อมูลพนักงานสำหรับคำนวณเงินเดือน';
      });
      return;
    }

    if (!_isYm(month)) {
      setState(() {
        _loading = false;
        _error = 'รูปแบบเดือนไม่ถูกต้อง';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
    });

    try {
      final res = await PayrollCloseApi.previewMonth(
        clinicId: clinicId,
        employeeId: staffId,
        month: month,
        grossBase: widget.grossMonthly,
        bonus: widget.bonus,
        otherAllowance: widget.otherAllowance,
        otherDeduction: widget.otherDeduction,
        pvdEmployeeMonthly: widget.pvdEmployeeMonthly,
        taxMode: _apiTaxMode,
        grossBaseMode: 'PRE_DEDUCTION',
        employeeUserId: widget.employeeUserId,
        regularWorkHours: widget.regularWorkHours,
        regularWorkMinutes: widget.regularWorkMinutes,
        workItems: widget.workItems,
      );

      if (!mounted) return;

      setState(() {
        _preview = _PayrollPreviewData.fromMap(res);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _preview = null;
        _error = _friendlyLoadError(e);
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<String> _buildMonthOptions({int backMonths = 24}) {
    final now = DateTime.now();
    final out = <String>[];

    for (int i = 0; i <= backMonths; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      out.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    }

    return out;
  }

  Future<void> _pickMonthBottomSheet() async {
    final options = _buildMonthOptions(backMonths: 24);
    final current = _pickedCloseMonth;

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Text(
                    'เลือกเดือน',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = options[i];
                      final selected = m == current;

                      return ListTile(
                        title: Text(m),
                        trailing: selected
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, m),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || picked == null) return;

    final v = picked.trim();
    if (v.isEmpty || !_isYm(v)) return;

    setState(() => _pickedCloseMonth = v);

    await _load();
  }

  Future<void> _closePayroll() async {
    if (_closing || _loading) return;

    final p = _preview;
    if (p == null) {
      _snack('ยังไม่มีข้อมูลเงินเดือน กรุณาโหลดใหม่อีกครั้ง');
      return;
    }

    final staffId = widget.employeeId.trim();
    if (!_isValidStaffId(staffId)) {
      _snack('ไม่พบข้อมูลพนักงานสำหรับปิดงวด');
      return;
    }

    final month = _pickedCloseMonth.trim();
    if (month.isEmpty || !_isYm(month)) {
      _snack('รูปแบบเดือนไม่ถูกต้อง');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('ยืนยันการปิดงวดเงินเดือน'),
        content: Text(
          'เดือน: $month\n\n'
          'รูปแบบภาษี: ${_taxModeLabel(p.taxMode)}\n'
          'เงินเดือน/ค่าจ้าง: ${_money(p.salary)} บาท\n'
          'ค่า OT: ${_money(p.ot)} บาท\n'
          'ประกันสังคม: ${_money(p.socialSecurity)} บาท\n'
          'ภาษี: ${_money(p.tax)} บาท\n'
          'เงินรับจริง: ${_money(p.netPay)} บาท\n\n'
          'ระบบจะบันทึกยอดเงินเดือนของเดือนนี้เป็นงวดจริง '
          'หากมีการแก้ไขข้อมูลภายหลัง ผู้ดูแลต้องใช้เมนูคำนวณงวดใหม่\n\n'
          'ต้องการปิดงวดนี้หรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.lock),
            label: const Text('ยืนยันปิดงวด'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (!mounted) return;

    setState(() => _closing = true);

    try {
      await PayrollCloseApi.closeMonth(
        clinicId: widget.clinicId,
        employeeId: staffId,
        month: month,
        grossBase: widget.grossMonthly,
        bonus: widget.bonus,
        otherAllowance: widget.otherAllowance,
        otherDeduction: widget.otherDeduction,
        pvdEmployeeMonthly: widget.pvdEmployeeMonthly,
        taxMode: _apiTaxMode,
        grossBaseMode: 'PRE_DEDUCTION',
        employeeUserId: widget.employeeUserId,
        regularWorkHours: widget.regularWorkHours,
        regularWorkMinutes: widget.regularWorkMinutes,
        workItems: widget.workItems,
      );

      if (!mounted) return;

      _snack('ปิดงวดเรียบร้อย');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack(_friendlyCloseError(e));
    } finally {
      if (mounted) {
        setState(() => _closing = false);
      }
    }
  }

  Widget _row({
    required String label,
    required String value,
    bool bold = false,
    Color? valueColor,
  }) {
    final style = TextStyle(
      fontSize: 14,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Text(
              label,
              style: style,
              softWrap: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: style.copyWith(color: valueColor),
              textAlign: TextAlign.right,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    final msg = _error ?? 'ไม่พบข้อมูลเงินเดือน';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
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
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองโหลดใหม่'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(_PayrollPreviewData p) {
    final lineItems = _buildLineItems(p);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'สรุปสลิปเงินเดือน',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            _row(label: 'ปีภาษี', value: '${p.taxYear}'),
            _row(label: 'เดือนที่จะปิดงวด', value: _pickedCloseMonth),
            _row(label: 'รูปแบบภาษี', value: _taxModeLabel(p.taxMode)),
            if (p.employmentType.isNotEmpty)
              _row(
                label: 'ประเภทพนักงาน',
                value: _employmentTypeLabel(p.employmentType),
              ),
            const Divider(height: 24),
            Text(
              'OT ในงวดนี้',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            _row(
              label: 'รายการ OT ที่อนุมัติ',
              value: '${p.approvedCount} รายการ',
            ),
            _row(
              label: 'เวลา OT ที่อนุมัติ',
              value: '${p.approvedMinutes} นาที',
            ),
            _row(
              label: 'ชั่วโมง OT สำหรับคำนวณเงิน',
              value: '${p.approvedWeightedHours.toStringAsFixed(2)} ชม.',
            ),
            const Divider(height: 24),
            Text(
              'รายการเงินเดือน',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            for (final item in lineItems)
              if (item.amount > 0 || item.label == 'เงินเดือน/ค่าจ้าง')
                _row(
                  label: item.label,
                  value: '${item.sign}${_money(item.amount)} บาท',
                ),
            const Divider(height: 24),
            _row(
              label: 'ยอดรวมก่อนภาษี',
              value: '${_money(p.grossBeforeTax)} บาท',
              bold: true,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.green.withValues(alpha: 0.10),
              ),
              child: _row(
                label: 'เงินรับจริง',
                value: '${_money(p.netPay)} บาท',
                bold: true,
                valueColor: Colors.green.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calculationInfoCard(_PayrollPreviewData p) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'รายละเอียดการคำนวณ',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            _row(
              label: 'แหล่งข้อมูล',
              value: 'ระบบเงินเดือน',
            ),
            _row(
              label: 'สถานะข้อมูล',
              value: 'พร้อมปิดงวด',
            ),
            if (widget.withholdingPercent > 0 && _safeTaxMode == 'withholding')
              _row(
                label: 'อัตราหักภาษีที่เลือกไว้',
                value: '${widget.withholdingPercent.toStringAsFixed(2)}%',
              ),
            const SizedBox(height: 12),
            const Text(
              'หมายเหตุ: ตัวเลขเงินเดือน OT ประกันสังคม ภาษี และยอดสุทธิทั้งหมดมาจากระบบเงินเดือน',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthHeaderCard(_PayrollPreviewData preview) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'เดือนที่เลือก',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _pickedCloseMonth,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'รูปแบบภาษี: ${_taxModeLabel(preview.taxMode)}',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.70),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickMonthBottomSheet,
              icon: const Icon(Icons.calendar_month),
              label: const Text('เปลี่ยนเดือน'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(
        title: const Text('พรีวิวสลิปเงินเดือน'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'โหลดใหม่',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : preview == null
                  ? const Center(child: Text('ไม่มีข้อมูลเงินเดือน'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _monthHeaderCard(preview),
                              const SizedBox(height: 12),
                              _summaryCard(preview),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed:
                                    (_closing || _loading) ? null : _closePayroll,
                                icon: _closing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.lock),
                                label: Text(
                                  _closing
                                      ? 'กำลังปิดงวด...'
                                      : 'ปิดงวดเงินเดือน $_pickedCloseMonth',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _calculationInfoCard(preview),
                            ],
                          ),
                        ),
                      ),
                    ),
    );
  }
}