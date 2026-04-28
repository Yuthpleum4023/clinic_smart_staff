// lib/screens/payroll/payroll_after_tax_preview_screen.dart
//
// ✅ PRODUCTION — Backend-only Payroll Preview Screen
//
// หลักการ:
// - Flutter ส่ง input / intent เท่านั้น
// - Backend คำนวณเงินเดือน / OT / SSO / ภาษี / Net Pay ทั้งหมด
// - หน้านี้แสดงผลจาก backend preview เท่านั้น
//
// ส่งเข้า backend ได้:
// - clinicId, employeeId, month
// - bonus
// - otherAllowance / commission
// - otherDeduction / รายการหัก
// - pvdEmployeeMonthly
// - taxMode
// - employeeUserId
// - grossMonthly เป็น fallback ชั่วคราว หาก staff_service ยังไม่มี salary
//
// ไม่ใช้ Flutter คำนวณยอดจริง:
// - OT amount
// - SSO amount
// - grossBeforeTax
// - tax
// - netPay
//

import 'package:flutter/material.dart';

import '../../api/payroll_close_api.dart';

class PayrollAfterTaxPreviewScreen extends StatefulWidget {
  /// เดิมใช้เป็น grossMonthly จากหน้า employee detail
  /// ตอนนี้ใช้เป็น fallback ให้ backend เท่านั้น หาก staff_service ยังไม่มี salary
  final double grossMonthly;

  /// compatibility only — ไม่ใช้เป็นยอดจริงแล้ว
  final double ssoEmployeeMonthly;

  final int? year;

  // required for Close Payroll
  final String clinicId;
  final String employeeId; // ใช้ staffId จริงจาก backend

  // compatibility/input components
  final double otPay; // ignored as computed value
  final double bonus;
  final double otherAllowance;
  final double otherDeduction;
  final double pvdEmployeeMonthly;

  // ถ้าส่งมา จะใช้เป็นเดือนปิดงวดโดยตรง (yyyy-MM)
  final String? closeMonth;

  // none = ไม่หักภาษี
  // withholding = หักภาษี ณ ที่จ่าย
  // annual = backend withholding flow
  final String taxMode;
  final double withholdingPercent; // compatibility display only
  final double? withholdingAmount; // ignored as computed value

  // compatibility only
  final bool allowSelfAnnualTaxEngine;

  // detail snapshot จากหน้า employee detail — compatibility only
  // หน้านี้จะไม่เอา snapshot พวกนี้มาคำนวณยอดจริง
  final double detailNetBeforeOt;
  final double detailLeaveDeduction;
  final double detailOtAmount;
  final double detailGrossBeforeTax;
  final double detailSsoAmount;
  final double detailTaxAmount;
  final double detailNetPay;
  final double detailOtHours;

  // optional: userId ของพนักงานจริง ถ้าหน้า detail ส่งมาได้
  final String? employeeUserId;

  // optional: สำหรับ part-time ในอนาคต ถ้าหน้า detail ส่งชั่วโมงดิบมา
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

class _BackendPayrollPreview {
  final Map<String, dynamic> raw;
  final Map<String, dynamic> payslipSummary;
  final Map<String, dynamic> amounts;
  final Map<String, dynamic> displaySnapshot;
  final Map<String, dynamic> otSummary;
  final Map<String, dynamic> payrollInputsResolved;
  final Map<String, dynamic> row;
  final Map<String, dynamic> snapshot;

  const _BackendPayrollPreview({
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

  factory _BackendPayrollPreview.fromMap(Map<String, dynamic> m) {
    final payslipSummary = _asMap(m['payslipSummary']);
    final amounts = _asMap(payslipSummary['amounts']);
    final displaySnapshot = _asMap(m['displaySnapshot']);
    final otSummary = _asMap(m['otSummary']);
    final payrollInputsResolved = _asMap(m['payrollInputsResolved']);
    final row = _asMap(m['row']);
    final snapshot = _asMap(row['snapshot']);

    return _BackendPayrollPreview(
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

  bool get backendOnly => raw['backendOnly'] == true;

  String get sourceLabel {
    final meta = _asMap(payslipSummary['meta']);
    final source = _readStr(meta['source']);
    if (backendOnly) return 'คำนวณจาก backend';
    if (source.isNotEmpty) return source;
    return 'backend preview';
  }

  int get taxYear {
    final y = _readNum(snapshot['taxYear']).toInt();
    if (y > 0) return y;
    return DateTime.now().year;
  }

  String get taxMode => _readStr(raw['taxMode']);

  String get grossBaseSource =>
      _readStr(payrollInputsResolved['grossBaseSource']);

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

  double get netBeforeOt => _readNum(displaySnapshot['netBeforeOt']);
  double get otHours => _readNum(displaySnapshot['otHours']);

  int get approvedMinutes => _readNum(otSummary['approvedMinutes']).toInt();
  int get approvedCount => _readNum(otSummary['count']).toInt();
  double get approvedWeightedHours =>
      _readNum(otSummary['approvedWeightedHours']);

  double get projectedAnnualIncome => grossBeforeTax * 12.0;
  double get projectedAnnualTax => tax * 12.0;
}

class _PayrollAfterTaxPreviewScreenState
    extends State<PayrollAfterTaxPreviewScreen> {
  bool _loading = true;
  String? _error;

  bool _closing = false;
  late String _pickedCloseMonth;

  _BackendPayrollPreview? _preview;

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _isYm(String v) => RegExp(r'^\d{4}-\d{2}$').hasMatch(v.trim());

  bool _isValidStaffId(String v) => v.trim().isNotEmpty;

  String get _safeTaxMode {
    final v = widget.taxMode.trim().toLowerCase();
    if (v == 'none' || v == 'no_withholding') return 'none';
    if (v == 'withholding') return 'withholding';
    return 'annual';
  }

  String get _backendTaxMode {
    return _safeTaxMode == 'none' ? 'NO_WITHHOLDING' : 'WITHHOLDING';
  }

  String _taxModeLabel(String mode) {
    final m = mode.trim().toUpperCase();

    if (m == 'NO_WITHHOLDING' || mode == 'none') {
      return 'ไม่หักภาษี';
    }

    if (mode == 'withholding' || m == 'WITHHOLDING') {
      return 'หักภาษี ณ ที่จ่าย';
    }

    return 'คำนวณภาษีตาม backend';
  }

  List<_LineItem> _buildLineItems(_BackendPayrollPreview p) {
    return [
      _LineItem(label: 'เงินเดือน', sign: '', amount: p.salary),
      _LineItem(label: 'ประกันสังคม', sign: '-', amount: p.socialSecurity),
      _LineItem(label: 'OT', sign: '+', amount: p.ot),
      _LineItem(
        label: 'Commission / รายได้อื่น',
        sign: '+',
        amount: p.commission,
      ),
      _LineItem(label: 'โบนัส', sign: '+', amount: p.bonus),
      _LineItem(label: 'หักวันลา/ขาด', sign: '-', amount: p.leaveDeduction),
      _LineItem(label: 'ภาษี', sign: '-', amount: p.tax),
      _LineItem(label: 'PVD', sign: '-', amount: p.pvd),
    ];
  }

  Future<void> _load() async {
    if (!mounted) return;

    final clinicId = widget.clinicId.trim();
    final staffId = widget.employeeId.trim();
    final month = _pickedCloseMonth.trim();

    if (clinicId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'ไม่พบ clinicId';
      });
      return;
    }

    if (!_isValidStaffId(staffId)) {
      setState(() {
        _loading = false;
        _error = 'ไม่พบ employeeId/staffId';
      });
      return;
    }

    if (!_isYm(month)) {
      setState(() {
        _loading = false;
        _error = 'เดือนไม่ถูกต้อง ต้องเป็น yyyy-MM';
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

        // fallback only: backend จะใช้ staff_service ก่อน
        grossBase: widget.grossMonthly,

        // accounting inputs
        bonus: widget.bonus,
        otherAllowance: widget.otherAllowance,
        otherDeduction: widget.otherDeduction,
        pvdEmployeeMonthly: widget.pvdEmployeeMonthly,

        // tax
        taxMode: _backendTaxMode,
        grossBaseMode: 'PRE_DEDUCTION',
        employeeUserId: widget.employeeUserId,

        // part-time raw input in future
        regularWorkHours: widget.regularWorkHours,
        regularWorkMinutes: widget.regularWorkMinutes,
        workItems: widget.workItems,
      );

      if (!mounted) return;

      setState(() {
        _preview = _BackendPayrollPreview.fromMap(res);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
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
                      final selected = (m == current);

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

    if (!mounted) return;
    if (picked == null) return;

    final v = picked.trim();
    if (v.isEmpty || !_isYm(v)) return;

    setState(() => _pickedCloseMonth = v);

    await _load();
  }

  Future<void> _closePayroll() async {
    if (_closing || _loading) return;

    final p = _preview;
    if (p == null) {
      _snack('ยังไม่มีข้อมูลจาก backend กรุณาโหลดใหม่');
      return;
    }

    final staffId = widget.employeeId.trim();
    if (!_isValidStaffId(staffId)) {
      _snack('ปิดงวดไม่สำเร็จ: ไม่พบ employeeId/staffId');
      return;
    }

    final month = _pickedCloseMonth.trim();
    if (month.isEmpty || !_isYm(month)) {
      _snack('เดือนไม่ถูกต้อง');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ยืนยันการปิดงวดเงินจริง'),
        content: Text(
          'เดือน: $month\n\n'
          'รูปแบบภาษี: ${_taxModeLabel(p.taxMode)}\n'
          'เงินเดือน: ${_money(p.salary)} บาท\n'
          'OT: ${_money(p.ot)} บาท\n'
          'ประกันสังคม: ${_money(p.socialSecurity)} บาท\n'
          'ภาษี: ${_money(p.tax)} บาท\n'
          'เงินรับจริง: ${_money(p.netPay)} บาท\n\n'
          'ยอดทั้งหมดคำนวณจาก backend\n'
          'การปิดงวดจะ “ล็อกข้อมูล” และไม่สามารถแก้ไขย้อนหลังได้\n'
          'คุณแน่ใจหรือไม่?',
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

    setState(() => _closing = true);

    try {
      await PayrollCloseApi.closeMonth(
        clinicId: widget.clinicId,
        employeeId: staffId,
        month: month,

        // fallback only: backend จะใช้ staff_service ก่อน
        grossBase: widget.grossMonthly,

        // accounting inputs
        bonus: widget.bonus,
        otherAllowance: widget.otherAllowance,
        otherDeduction: widget.otherDeduction,
        pvdEmployeeMonthly: widget.pvdEmployeeMonthly,

        // tax
        taxMode: _backendTaxMode,
        grossBaseMode: 'PRE_DEDUCTION',
        employeeUserId: widget.employeeUserId,

        // part-time raw input in future
        regularWorkHours: widget.regularWorkHours,
        regularWorkMinutes: widget.regularWorkMinutes,
        workItems: widget.workItems,
      );

      if (!mounted) return;

      _snack('✅ ปิดงวดเรียบร้อย');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      final msg = e.toString();
      final friendly = (msg.contains('409') || msg.contains('already closed'))
          ? 'เดือนนี้ถูกปิดงวดไปแล้ว'
          : 'ปิดงวดไม่สำเร็จ: $msg';

      _snack(friendly);
    } finally {
      if (!mounted) return;
      setState(() => _closing = false);
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 10),
              Text(
                'ผิดพลาด: $_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(_BackendPayrollPreview p) {
    final lineItems = _buildLineItems(p);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'สรุปสลิป (${p.sourceLabel})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            _row(label: 'ปีภาษี', value: '${p.taxYear}'),
            _row(label: 'เดือนที่จะปิดงวด', value: _pickedCloseMonth),
            _row(label: 'รูปแบบภาษี', value: _taxModeLabel(p.taxMode)),
            if (p.employmentType.isNotEmpty)
              _row(label: 'ประเภทพนักงาน', value: p.employmentType),
            if (p.grossBaseSource.isNotEmpty)
              _row(label: 'แหล่งฐานเงินเดือน', value: p.grossBaseSource),
            const Divider(height: 24),
            Text(
              'OT จากระบบ',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            _row(label: 'รายการ OT ที่อนุมัติ', value: '${p.approvedCount} รายการ'),
            _row(label: 'นาที OT ที่อนุมัติ', value: '${p.approvedMinutes} นาที'),
            _row(
              label: 'ชั่วโมงถ่วงน้ำหนัก',
              value: '${p.approvedWeightedHours.toStringAsFixed(2)} ชม.',
            ),
            const Divider(height: 24),
            Text(
              'สรุปรายการ',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            for (final item in lineItems)
              if (item.amount > 0 || item.label == 'เงินเดือน')
                _row(
                  label: item.label,
                  value: '${item.sign}${_money(item.amount)} บาท',
                ),
            const Divider(height: 24),
            _row(
              label: 'ยอดก่อนภาษี',
              value: '${_money(p.grossBeforeTax)} บาท',
              bold: true,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.green.withOpacity(0.10),
              ),
              child: _row(
                label: 'เงินรับจริง (Net Pay)',
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

  Widget _backendInfoCard(_BackendPayrollPreview p) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'รายละเอียดจาก backend',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            _row(
              label: 'รายได้ทั้งปี (ประมาณจาก backend)',
              value: '${_money(p.projectedAnnualIncome)} บาท',
            ),
            _row(
              label: 'ภาษีทั้งปี (ประมาณจาก backend)',
              value: '${_money(p.projectedAnnualTax)} บาท',
            ),
            if (widget.withholdingPercent > 0 && _safeTaxMode == 'withholding')
              _row(
                label: 'อัตราหักภาษีที่เลือกไว้',
                value: '${widget.withholdingPercent.toStringAsFixed(2)}%',
              ),
            const SizedBox(height: 12),
            const Text(
              'หมายเหตุ: หน้านี้ไม่คำนวณยอดเงินเดือนเองแล้ว ตัวเลขเงินเดือน OT ประกันสังคม ภาษี และยอดสุทธิทั้งหมดมาจาก backend',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
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
                  ? const Center(child: Text('ไม่มีข้อมูลจาก backend'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Card(
                                elevation: 1,
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'เดือนที่เลือก',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
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
                                                color: Colors.black
                                                    .withOpacity(0.70),
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
                              ),
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
                                      : 'ปิดงวดเงินจริง (ล็อกเดือน $_pickedCloseMonth)',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _backendInfoCard(preview),
                            ],
                          ),
                        ),
                      ),
                    ),
    );
  }
}