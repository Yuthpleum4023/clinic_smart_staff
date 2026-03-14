import 'package:flutter/material.dart';

import '../../api/payroll_tax_api.dart';
import '../../api/payroll_close_api.dart';
import '../../models/payroll_tax_result.dart';

class PayrollAfterTaxPreviewScreen extends StatefulWidget {
  final double grossMonthly;
  final double ssoEmployeeMonthly;
  final int? year;

  // required for Close Payroll
  final String clinicId;
  final String employeeId; // ใช้ staffId จริงจาก backend

  // optional components
  final double otPay;
  final double bonus;
  final double otherAllowance;
  final double otherDeduction;
  final double pvdEmployeeMonthly;

  // ถ้าส่งมา จะใช้เป็นเดือนปิดงวดโดยตรง (yyyy-MM)
  final String? closeMonth;

  // ✅ รองรับ 3 flow ภาษี
  // none = ไม่หักภาษี
  // withholding = หักภาษี ณ ที่จ่าย
  // annual = ใช้ tax engine แบบทั้งปี
  final String taxMode;
  final double withholdingPercent;
  final double? withholdingAmount;

  // ✅ NEW:
  // ป้องกัน admin preview ไปเรียก /users/me/payroll/calc-tax ผิดคน
  // - false = ห้ามใช้ self annual tax engine
  // - true  = อนุญาตใช้ self annual tax engine (เหมาะกับ self-service)
  final bool allowSelfAnnualTaxEngine;

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
  });

  @override
  State<PayrollAfterTaxPreviewScreen> createState() =>
      _PayrollAfterTaxPreviewScreenState();
}

class _PreviewTaxVM {
  final int taxYear;
  final String taxMode;

  final double grossMonthly;
  final double estimatedMonthlyTax;
  final double netAfterTaxMonthly;
  final double netAfterTaxAndSSOMonthly;

  final double projectedAnnualIncome;
  final double allowanceTotal;
  final double projectedAnnualTaxable;
  final double projectedAnnualTax;

  final String sourceLabel;

  const _PreviewTaxVM({
    required this.taxYear,
    required this.taxMode,
    required this.grossMonthly,
    required this.estimatedMonthlyTax,
    required this.netAfterTaxMonthly,
    required this.netAfterTaxAndSSOMonthly,
    required this.projectedAnnualIncome,
    required this.allowanceTotal,
    required this.projectedAnnualTaxable,
    required this.projectedAnnualTax,
    required this.sourceLabel,
  });

  factory _PreviewTaxVM.fromAnnualResult(
    PayrollTaxResult r, {
    required String taxMode,
  }) {
    return _PreviewTaxVM(
      taxYear: r.taxYear,
      taxMode: taxMode,
      grossMonthly: r.grossMonthly,
      estimatedMonthlyTax: r.estimatedMonthlyTax,
      netAfterTaxMonthly: r.netAfterTaxMonthly,
      netAfterTaxAndSSOMonthly: r.netAfterTaxAndSSOMonthly,
      projectedAnnualIncome: r.projectedAnnualIncome,
      allowanceTotal: r.allowanceTotal,
      projectedAnnualTaxable: r.projectedAnnualTaxable,
      projectedAnnualTax: r.projectedAnnualTax,
      sourceLabel: 'คำนวณภาษีทั้งปี',
    );
  }

  factory _PreviewTaxVM.manual({
    required int taxYear,
    required String taxMode,
    required double grossMonthly,
    required double monthlyTax,
    required double ssoEmployeeMonthly,
    required double pvdEmployeeMonthly,
    required String sourceLabel,
  }) {
    final safeGross = grossMonthly < 0 ? 0.0 : grossMonthly;
    final safeTax = monthlyTax < 0 ? 0.0 : monthlyTax;
    final safeSso = ssoEmployeeMonthly < 0 ? 0.0 : ssoEmployeeMonthly;
    final safePvd = pvdEmployeeMonthly < 0 ? 0.0 : pvdEmployeeMonthly;

    final netAfterTax = (safeGross - safeTax).clamp(0.0, double.infinity);
    final netAfterTaxAndSSO =
        (safeGross - safeTax - safeSso - safePvd).clamp(0.0, double.infinity);

    final projectedAnnualIncome = safeGross * 12.0;
    final projectedAnnualTax = safeTax * 12.0;
    final projectedAnnualTaxable =
        (projectedAnnualIncome - projectedAnnualTax).clamp(
      0.0,
      double.infinity,
    );

    return _PreviewTaxVM(
      taxYear: taxYear,
      taxMode: taxMode,
      grossMonthly: safeGross,
      estimatedMonthlyTax: safeTax,
      netAfterTaxMonthly: netAfterTax,
      netAfterTaxAndSSOMonthly: netAfterTaxAndSSO,
      projectedAnnualIncome: projectedAnnualIncome,
      allowanceTotal: 0.0,
      projectedAnnualTaxable: projectedAnnualTaxable,
      projectedAnnualTax: projectedAnnualTax,
      sourceLabel: sourceLabel,
    );
  }
}

class _PayrollAfterTaxPreviewScreenState
    extends State<PayrollAfterTaxPreviewScreen> {
  late int _year;
  bool _loading = true;
  _PreviewTaxVM? _vm;
  String? _error;

  bool _closing = false;
  late String _pickedCloseMonth;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _year = widget.year ?? now.year;

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
    if (v == 'none') return 'none';
    if (v == 'withholding') return 'withholding';
    return 'annual';
  }

  String get _backendTaxMode {
    return _safeTaxMode == 'none' ? 'NO_WITHHOLDING' : 'WITHHOLDING';
  }

  String _taxModeLabel(String mode) {
    switch (mode) {
      case 'none':
        return 'ไม่หักภาษี';
      case 'withholding':
        return 'หักภาษี ณ ที่จ่าย';
      default:
        return 'คำนวณภาษีทั้งปี';
    }
  }

  PayrollTaxResult _ensureResult(dynamic raw) {
    if (raw is PayrollTaxResult) return raw;

    if (raw is Map<String, dynamic>) {
      return PayrollTaxResult.fromMap(raw);
    }

    if (raw is Map) {
      return PayrollTaxResult.fromMap(Map<String, dynamic>.from(raw));
    }

    throw Exception(
      'รูปแบบผลลัพธ์ไม่ถูกต้องจาก calcMyTax(): ${raw.runtimeType}',
    );
  }

  double _resolveWithholdingAmount() {
    final explicit = widget.withholdingAmount;
    if (explicit != null && explicit >= 0) return explicit;

    final pct = widget.withholdingPercent;
    if (pct <= 0) return 0.0;

    return widget.grossMonthly * (pct / 100.0);
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final mode = _safeTaxMode;

      if (mode == 'none') {
        final vm = _PreviewTaxVM.manual(
          taxYear: _year,
          taxMode: mode,
          grossMonthly: widget.grossMonthly,
          monthlyTax: 0.0,
          ssoEmployeeMonthly: widget.ssoEmployeeMonthly,
          pvdEmployeeMonthly: widget.pvdEmployeeMonthly,
          sourceLabel: 'ตามโหมดไม่หักภาษี',
        );

        if (!mounted) return;
        setState(() => _vm = vm);
        return;
      }

      if (mode == 'withholding') {
        final withholding = _resolveWithholdingAmount();

        final vm = _PreviewTaxVM.manual(
          taxYear: _year,
          taxMode: mode,
          grossMonthly: widget.grossMonthly,
          monthlyTax: withholding,
          ssoEmployeeMonthly: widget.ssoEmployeeMonthly,
          pvdEmployeeMonthly: widget.pvdEmployeeMonthly,
          sourceLabel: widget.withholdingPercent > 0
              ? 'ตามอัตราหักภาษี ${widget.withholdingPercent.toStringAsFixed(2)}%'
              : 'ตามยอดภาษีหัก ณ ที่จ่าย',
        );

        if (!mounted) return;
        setState(() => _vm = vm);
        return;
      }

      // ✅ annual mode
      // เรียก self tax engine เฉพาะตอน caller อนุญาตเท่านั้น
      if (!widget.allowSelfAnnualTaxEngine) {
        final vm = _PreviewTaxVM.manual(
          taxYear: _year,
          taxMode: mode,
          grossMonthly: widget.grossMonthly,
          monthlyTax: 0.0,
          ssoEmployeeMonthly: widget.ssoEmployeeMonthly,
          pvdEmployeeMonthly: widget.pvdEmployeeMonthly,
          sourceLabel:
              'annual preview แบบปลอดภัย (ไม่ได้เรียก self tax engine เพราะหน้าจอนี้อาจเป็น admin preview)',
        );

        if (!mounted) return;
        setState(() => _vm = vm);
        return;
      }

      final raw = await PayrollTaxApi.calcMyTax(
        year: _year,
        grossMonthly: widget.grossMonthly,
        ssoEmployeeMonthly: widget.ssoEmployeeMonthly,
        pvdEmployeeMonthly: widget.pvdEmployeeMonthly,
      );

      final r = _ensureResult(raw);

      if (!mounted) return;
      setState(() {
        _vm = _PreviewTaxVM.fromAnnualResult(r, taxMode: mode);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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

    setState(() {
      _pickedCloseMonth = v;
      final yy = int.tryParse(v.split('-').first);
      if (yy != null) _year = yy;
    });

    await _load();
  }

  Future<void> _closePayroll() async {
    if (_closing || _loading) return;

    if (_vm == null) {
      _snack('ยังไม่มีข้อมูลคำนวณ กรุณาโหลดใหม่');
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
          'รูปแบบภาษี: ${_taxModeLabel(_safeTaxMode)}\n'
          '${_safeTaxMode == 'withholding' ? 'ยอดภาษีเดือนนี้: ${_money(_vm!.estimatedMonthlyTax)} บาท\n' : ''}'
          '\nการปิดงวดจะ “ล็อกข้อมูล” และไม่สามารถแก้ไขย้อนหลังได้\n'
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
        grossBase: widget.grossMonthly,
        otPay: widget.otPay,
        bonus: widget.bonus,
        otherAllowance: widget.otherAllowance,
        otherDeduction: widget.otherDeduction,
        ssoEmployeeMonthly: widget.ssoEmployeeMonthly,
        pvdEmployeeMonthly: widget.pvdEmployeeMonthly,
        taxMode: _backendTaxMode,
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

  @override
  Widget build(BuildContext context) {
    final ssoInput = widget.ssoEmployeeMonthly;
    final pvdInput = widget.pvdEmployeeMonthly;

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
              : _vm == null
                  ? const Center(child: Text('ไม่มีข้อมูล'))
                  : LayoutBuilder(
                      builder: (context, c) {
                        final r = _vm!;
                        final month = _pickedCloseMonth;

                        return SingleChildScrollView(
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
                                                  month,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'รูปแบบภาษี: ${_taxModeLabel(r.taxMode)}',
                                                  style: TextStyle(
                                                    color: Colors.black.withOpacity(
                                                      0.70,
                                                    ),
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
                                  Card(
                                    elevation: 2,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'สรุปสลิป (${r.sourceLabel})',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          _row(
                                            label: 'ปีภาษี',
                                            value: '${r.taxYear}',
                                          ),
                                          _row(
                                            label: 'เดือนที่จะปิดงวด',
                                            value: month,
                                          ),
                                          const Divider(height: 24),
                                          Text(
                                            'รายได้ (Earnings)',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          _row(
                                            label: 'Gross รายเดือน (ก่อนหัก)',
                                            value:
                                                '${_money(r.grossMonthly)} บาท',
                                            bold: true,
                                          ),
                                          if (widget.otPay > 0)
                                            _row(
                                              label: 'OT (เป็นเงิน)',
                                              value:
                                                  '+${_money(widget.otPay)} บาท',
                                            ),
                                          if (widget.bonus > 0)
                                            _row(
                                              label: 'โบนัส',
                                              value:
                                                  '+${_money(widget.bonus)} บาท',
                                            ),
                                          if (widget.otherAllowance > 0)
                                            _row(
                                              label: 'รายได้อื่น',
                                              value:
                                                  '+${_money(widget.otherAllowance)} บาท',
                                            ),
                                          if (widget.otherDeduction > 0)
                                            _row(
                                              label: 'หักอื่น',
                                              value:
                                                  '-${_money(widget.otherDeduction)} บาท',
                                            ),
                                          const Divider(height: 24),
                                          Text(
                                            'รายการหัก (Deductions)',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          _row(
                                            label: 'ประกันสังคม (พนักงาน)',
                                            value: '-${_money(ssoInput)} บาท',
                                          ),
                                          if (pvdInput > 0)
                                            _row(
                                              label:
                                                  'กองทุนสำรองเลี้ยงชีพ (PVD)',
                                              value: '-${_money(pvdInput)} บาท',
                                            ),
                                          _row(
                                            label: r.taxMode == 'none'
                                                ? 'ภาษี'
                                                : 'ภาษีหัก ณ ที่จ่าย',
                                            value:
                                                '-${_money(r.estimatedMonthlyTax)} บาท',
                                          ),
                                          const Divider(height: 24),
                                          _row(
                                            label:
                                                'Net หลังหักภาษี (ยังไม่หัก SSO/PVD)',
                                            value:
                                                '${_money(r.netAfterTaxMonthly)} บาท',
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              color:
                                                  Colors.green.withOpacity(0.10),
                                            ),
                                            child: _row(
                                              label: 'เงินรับจริง (Net Pay)',
                                              value:
                                                  '${_money(r.netAfterTaxAndSSOMonthly)} บาท',
                                              bold: true,
                                              valueColor:
                                                  Colors.green.shade800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: (_closing || _loading)
                                        ? null
                                        : _closePayroll,
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
                                          : 'ปิดงวดเงินจริง (ล็อกเดือน $month)',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Card(
                                    elevation: 1,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r.taxMode == 'annual'
                                                ? 'รายละเอียดการคำนวณ (ทั้งปีแบบประมาณ)'
                                                : 'รายละเอียดการคำนวณ',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                          _row(
                                            label: 'รายได้ทั้งปี (ประมาณ)',
                                            value:
                                                '${_money(r.projectedAnnualIncome)} บาท',
                                          ),
                                          if (r.taxMode == 'withholding')
                                            _row(
                                              label: 'อัตราหักภาษี',
                                              value:
                                                  '${widget.withholdingPercent.toStringAsFixed(2)}%',
                                            ),
                                          if (r.taxMode == 'annual')
                                            _row(
                                              label:
                                                  'ลดหย่อนรวม (Tax Profile)',
                                              value:
                                                  '${_money(r.allowanceTotal)} บาท',
                                            ),
                                          _row(
                                            label: 'ฐานภาษีทั้งปี',
                                            value:
                                                '${_money(r.projectedAnnualTaxable)} บาท',
                                          ),
                                          _row(
                                            label: 'ภาษีทั้งปี',
                                            value:
                                                '${_money(r.projectedAnnualTax)} บาท',
                                            bold: true,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            r.taxMode == 'none'
                                                ? 'โหมดนี้ไม่หักภาษี โดยสลิปและการปิดงวดจะแสดงภาษีเป็น 0 บาท'
                                                : r.taxMode == 'withholding'
                                                    ? 'โหมดนี้ใช้การหักภาษี ณ ที่จ่ายตามค่าที่ส่งมาจากหน้าเงินเดือน'
                                                    : widget.allowSelfAnnualTaxEngine
                                                        ? 'โหมดนี้ใช้การคำนวณภาษีทั้งปีแบบประมาณการจาก tax engine'
                                                        : 'โหมด annual ในหน้านี้ถูกทำเป็น safe preview เพื่อกันไปคำนวณจาก tax profile ของคนล็อกอินผิดคน',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}