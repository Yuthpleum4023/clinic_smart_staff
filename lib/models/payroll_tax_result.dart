// lib/models/payroll_tax_result.dart
class PayrollTaxResult {
  final int taxYear;

  final double grossMonthly;

  // annual projection
  final double projectedAnnualIncome;
  final double allowanceTotal;
  final double projectedAnnualTaxable;
  final double projectedAnnualTax;

  // monthly outputs
  final double estimatedMonthlyTax;
  final double netAfterTaxMonthly;

  // ✅ NEW (optional from backend)
  final double netAfterTaxAndSSOMonthly;

  const PayrollTaxResult({
    required this.taxYear,
    required this.grossMonthly,
    required this.projectedAnnualIncome,
    required this.allowanceTotal,
    required this.projectedAnnualTaxable,
    required this.projectedAnnualTax,
    required this.estimatedMonthlyTax,
    required this.netAfterTaxMonthly,
    this.netAfterTaxAndSSOMonthly = 0,
  });

  static double _toD(dynamic v, {double def = 0}) {
    if (v == null) return def;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? def;
  }

  static int _toI(dynamic v, {int def = 0}) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? def;
  }

  /// ✅ ใช้ตัวนี้ในหน้าจอได้เลย (หายแดง fromMap)
  factory PayrollTaxResult.fromMap(Map<String, dynamic> map) {
    return PayrollTaxResult(
      taxYear: _toI(map['taxYear'] ?? map['year']),
      grossMonthly: _toD(map['grossMonthly']),
      projectedAnnualIncome: _toD(map['projectedAnnualIncome']),
      allowanceTotal: _toD(map['allowanceTotal']),
      projectedAnnualTaxable: _toD(map['projectedAnnualTaxable']),
      projectedAnnualTax: _toD(map['projectedAnnualTax']),
      estimatedMonthlyTax: _toD(map['estimatedMonthlyTax']),
      netAfterTaxMonthly: _toD(map['netAfterTaxMonthly']),
      netAfterTaxAndSSOMonthly: _toD(
        map['netAfterTaxAndSSOMonthly'],
        def: 0,
      ),
    );
  }

  /// เผื่อบางจุดใช้ชื่อ fromJson
  factory PayrollTaxResult.fromJson(Map<String, dynamic> json) =>
      PayrollTaxResult.fromMap(json);

  Map<String, dynamic> toMap() => {
        'taxYear': taxYear,
        'grossMonthly': grossMonthly,
        'projectedAnnualIncome': projectedAnnualIncome,
        'allowanceTotal': allowanceTotal,
        'projectedAnnualTaxable': projectedAnnualTaxable,
        'projectedAnnualTax': projectedAnnualTax,
        'estimatedMonthlyTax': estimatedMonthlyTax,
        'netAfterTaxMonthly': netAfterTaxMonthly,
        'netAfterTaxAndSSOMonthly': netAfterTaxAndSSOMonthly,
      };
}
