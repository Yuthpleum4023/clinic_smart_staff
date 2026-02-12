// lib/screens/payroll/payroll_after_tax_preview_screen.dart
import 'package:flutter/material.dart';

import '../../api/payroll_tax_api.dart';
import '../../api/payroll_close_api.dart'; // ✅ NEW: ปิดงวดจริง
import '../../models/payroll_tax_result.dart';

class PayrollAfterTaxPreviewScreen extends StatefulWidget {
  final double grossMonthly;
  final double ssoEmployeeMonthly; // ✅ NEW
  final int? year;

  // ✅ NEW (ใช้ตอนปิดงวดจริง)
  final String clinicId;
  final String employeeId;

  // ✅ NEW (optionals: เผื่ออนาคต)
  final double otPay;
  final double bonus;
  final double otherAllowance;
  final double otherDeduction;
  final double pvdEmployeeMonthly;

  // ✅ NEW: ถ้าส่งมา จะใช้เป็นเดือนปิดงวดโดยตรง (yyyy-MM)
  // ถ้าไม่ส่ง จะใช้เดือนปัจจุบัน
  final String? closeMonth;

  const PayrollAfterTaxPreviewScreen({
    super.key,
    required this.grossMonthly,
    this.ssoEmployeeMonthly = 0,
    this.year,

    // ✅ required for Close Payroll
    required this.clinicId,
    required this.employeeId,

    // ✅ optional components
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

  bool _closing = false; // ✅ NEW

  @override
  void initState() {
    super.initState();
    _year = widget.year ?? DateTime.now().year;
    _load();
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

  String _money(num n) => n.toStringAsFixed(2);

  String _closeMonthValue() {
    if (widget.closeMonth != null && widget.closeMonth!.trim().isNotEmpty) {
      return widget.closeMonth!.trim();
    }
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _closePayroll() async {
    if (_closing || _loading) return;

    // ✅ ต้องมีข้อมูลผลคำนวณก่อน
    if (_result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่มีข้อมูลคำนวณ กรุณาโหลดใหม่')),
      );
      return;
    }

    final month = _closeMonthValue();

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
      // ✅ ปิดงวดจริงที่ payroll_service
      // หมายเหตุ: grossBase = grossMonthly ของคุณ (ถ้าอนาคตจะแยกฐานเงินเดือนจริงค่อยปรับ)
      await PayrollCloseApi.closeMonth(
        clinicId: widget.clinicId,
        employeeId: widget.employeeId,
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ ปิดงวดเรียบร้อย')),
      );

      Navigator.pop(context, true); // ✅ ส่งผลกลับ (optional)
    } catch (e) {
      if (!mounted) return;

      // ✅ ถ้าปิดซ้ำ payroll_service จะตอบ 409
      final msg = e.toString();
      final friendly = msg.contains('409') || msg.contains('already closed')
          ? 'เดือนนี้ถูกปิดงวดไปแล้ว'
          : 'ปิดงวดไม่สำเร็จ: $msg';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
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

                        final month = _closeMonthValue();

                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
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

                                          // Earnings
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

                                          // ✅ Optional items (ถ้ามี)
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

                                          // Deductions
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

                                          // Net
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

                                  // ✅ NEW: ปุ่มปิดงวดจริง
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
