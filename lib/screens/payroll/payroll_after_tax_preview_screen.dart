import 'package:flutter/material.dart';

import '../../api/payroll_tax_api.dart';
import '../../api/payroll_close_api.dart'; // ✅ ปิดงวดจริง
import '../../models/payroll_tax_result.dart';

class PayrollAfterTaxPreviewScreen extends StatefulWidget {
  final double grossMonthly;
  final double ssoEmployeeMonthly;
  final int? year;

  // ✅ required for Close Payroll
  final String clinicId;
  final String employeeId; // ต้องเป็น staffId (stf_...)

  // ✅ optional components
  final double otPay;
  final double bonus;
  final double otherAllowance;
  final double otherDeduction;
  final double pvdEmployeeMonthly;

  // ✅ ถ้าส่งมา จะใช้เป็นเดือนปิดงวดโดยตรง (yyyy-MM)
  final String? closeMonth;

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
  });

  @override
  State<PayrollAfterTaxPreviewScreen> createState() =>
      _PayrollAfterTaxPreviewScreenState();
}

class _PayrollAfterTaxPreviewScreenState
    extends State<PayrollAfterTaxPreviewScreen> {
  late int _year;
  bool _loading = true;
  PayrollTaxResult? _result;
  String? _error;

  bool _closing = false;

  // ✅ เดือนที่ผู้ใช้เลือกเอง (yyyy-MM) — ทำให้ UI เปลี่ยนทันที
  late String _pickedCloseMonth;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _year = widget.year ?? now.year;

    // ✅ initial month: user picked > widget.closeMonth > current month
    final cm = (widget.closeMonth ?? '').trim();
    _pickedCloseMonth = cm.isNotEmpty
        ? cm
        : '${now.year}-${now.month.toString().padLeft(2, '0')}';

    _load();
  }

  // ---------------- utils ----------------
  String _money(num n) => n.toStringAsFixed(2);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _isYm(String v) => RegExp(r'^\d{4}-\d{2}$').hasMatch(v.trim());

  // ✅ กัน 400: employeeId ต้องเป็น staffId (stf_...)
  bool _isValidStaffId(String v) => v.trim().startsWith('stf_');

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

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await PayrollTaxApi.calcMyTax(
        year: _year,
        grossMonthly: widget.grossMonthly,
        ssoEmployeeMonthly: widget.ssoEmployeeMonthly,
      );

      final PayrollTaxResult r = _ensureResult(raw);

      if (!mounted) return;
      setState(() {
        _result = r;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ✅ สร้างรายการเดือนย้อนหลัง (รวมเดือนนี้)
  List<String> _buildMonthOptions({int backMonths = 24}) {
    final now = DateTime.now();
    final out = <String>[];

    for (int i = 0; i <= backMonths; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      out.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    }
    return out; // ล่าสุด -> เก่าสุด
  }

  // ✅ เลือกเดือนแบบ “เห็นชัดบนหน้า” (แก้ปัญหาเลือกแล้วไม่เปลี่ยน)
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
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
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

      // ✅ ถ้า user เลือกเดือนคนละปี ให้ปีใน UI ตามด้วย (กันความงง)
      final yy = int.tryParse(v.split('-').first);
      if (yy != null) _year = yy;
    });

    // ภาษีที่คำนวณในหน้านี้ใช้ year เป็นหลัก (ไม่ผูกกับเดือน)
    // แต่เพื่อให้ user มั่นใจว่า update แล้ว จะโหลดใหม่ให้ด้วย (ไม่หนัก)
    await _load();
  }

  // ✅ ปิดงวดจริง
  Future<void> _closePayroll() async {
    if (_closing || _loading) return;

    if (_result == null) {
      _snack('ยังไม่มีข้อมูลคำนวณ กรุณาโหลดใหม่');
      return;
    }

    // ✅ กัน 400: validate staffId
    final staffId = widget.employeeId.trim();
    if (!_isValidStaffId(staffId)) {
      _snack('ปิดงวดไม่สำเร็จ: employeeId ต้องเป็น staffId (stf_...)');
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
        employeeId: staffId, // ✅ staffId เท่านั้น
        month: month,
        grossBase: widget.grossMonthly,
        otPay: widget.otPay,
        bonus: widget.bonus,
        otherAllowance: widget.otherAllowance,
        otherDeduction: widget.otherDeduction,
        ssoEmployeeMonthly: widget.ssoEmployeeMonthly,
        pvdEmployeeMonthly: widget.pvdEmployeeMonthly,
      );

      if (!mounted) return;

      _snack('✅ ปิดงวดเรียบร้อย');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      final msg = e.toString();
      final friendly = (msg.contains('409') || msg.contains('already closed'))
          ? 'เดือนนี้ถูกปิดงวดไปแล้ว'
          : msg.contains('400') && msg.contains('staffId')
              ? 'ปิดงวดไม่สำเร็จ: employeeId ต้องเป็น staffId (stf_...)'
              : 'ปิดงวดไม่สำเร็จ: $msg';

      _snack(friendly);
    } finally {
      if (!mounted) return;
      setState(() => _closing = false);
    }
  }

  // ✅ FIX OVERFLOW: ทำให้ value ไม่ล้นจอ และตัด/ขึ้นบรรทัดได้
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('พรีวิวสลิป: หลังหักภาษี'),
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
              : _result == null
                  ? const Center(child: Text('ไม่มีข้อมูล'))
                  : LayoutBuilder(
                      builder: (context, c) {
                        final r = _result!;

                        final fallbackNetAfterTaxAndSSO =
                            (r.grossMonthly - r.estimatedMonthlyTax - ssoInput);
                        final netAfterTaxAndSSO =
                            (r.netAfterTaxAndSSOMonthly > 0)
                                ? r.netAfterTaxAndSSOMonthly
                                : (fallbackNetAfterTaxAndSSO > 0
                                    ? fallbackNetAfterTaxAndSSO
                                    : 0);

                        final month = _pickedCloseMonth;

                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // ✅ แถบเลือกเดือน (ชัดมาก) — แก้ “เลือกแล้วไม่เปลี่ยน”
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
                                            'สรุปสลิป (ประมาณการ)',
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
                                          if (widget.pvdEmployeeMonthly > 0)
                                            _row(
                                              label:
                                                  'กองทุนสำรองเลี้ยงชีพ (PVD)',
                                              value:
                                                  '-${_money(widget.pvdEmployeeMonthly)} บาท',
                                            ),
                                          _row(
                                            label: 'ภาษีหัก ณ ที่จ่าย (ประมาณ)',
                                            value:
                                                '-${_money(r.estimatedMonthlyTax)} บาท',
                                          ),

                                          const Divider(height: 24),

                                          _row(
                                            label:
                                                'Net หลังหักภาษี (ยังไม่หัก SSO)',
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
                                                  '${_money(netAfterTaxAndSSO)} บาท',
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
                                            'รายละเอียดการคำนวณ (ทั้งปีแบบประมาณ)',
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
                                          _row(
                                            label: 'ลดหย่อนรวม (Tax Profile)',
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
                                          const Text(
                                            'หมายเหตุ: เป็นการ “ประมาณการ” จาก grossMonthly*12 - ลดหย่อน (tax profile) '
                                            'และ (ถ้าส่งมา) จะหัก SSO รายเดือนเพื่อลดฐานภาษีด้วย',
                                            style: TextStyle(
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