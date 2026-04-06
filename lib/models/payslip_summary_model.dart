// lib/models/payslip_summary_model.dart

class PayslipSummaryModel {
  final String employeeId;
  final String clinicId;
  final String month;

  final double salary;
  final double socialSecurity;
  final double ot;
  final double commission;
  final double bonus;
  final double leaveDeduction;
  final double tax;
  final double netPay;

  final String source;
  final bool isClosedPayroll;
  final String grossBaseModeApplied;

  const PayslipSummaryModel({
    required this.employeeId,
    required this.clinicId,
    required this.month,
    required this.salary,
    required this.socialSecurity,
    required this.ot,
    required this.commission,
    required this.bonus,
    required this.leaveDeduction,
    required this.tax,
    required this.netPay,
    required this.source,
    required this.isClosedPayroll,
    required this.grossBaseModeApplied,
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

  static bool _toB(dynamic v, {bool def = false}) {
    if (v == null) return def;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return def;
  }

  static String _toS(dynamic v, {String def = ''}) {
    if (v == null) return def;
    return v.toString().trim();
  }

  factory PayslipSummaryModel.fromMap(Map<String, dynamic> map) {
    final amountsRaw = map['amounts'];
    final metaRaw = map['meta'];

    final amounts = amountsRaw is Map<String, dynamic>
        ? amountsRaw
        : amountsRaw is Map
            ? Map<String, dynamic>.from(amountsRaw)
            : <String, dynamic>{};

    final meta = metaRaw is Map<String, dynamic>
        ? metaRaw
        : metaRaw is Map
            ? Map<String, dynamic>.from(metaRaw)
            : <String, dynamic>{};

    return PayslipSummaryModel(
      employeeId: _toS(map['employeeId']),
      clinicId: _toS(map['clinicId']),
      month: _toS(map['month']),
      salary: _toD(
        amounts['salary'] ??
            map['salary'] ??
            map['grossBase'] ??
            map['baseSalary'],
      ),
      socialSecurity: _toD(
        amounts['socialSecurity'] ??
            map['socialSecurity'] ??
            map['sso'] ??
            map['ssoEmployeeMonthly'],
      ),
      ot: _toD(
        amounts['ot'] ??
            map['ot'] ??
            map['otPay'],
      ),
      commission: _toD(
        amounts['commission'] ??
            map['commission'] ??
            map['otherAllowance'],
      ),
      bonus: _toD(
        amounts['bonus'] ??
            map['bonus'],
      ),
      leaveDeduction: _toD(
        amounts['leaveDeduction'] ??
            map['leaveDeduction'] ??
            map['otherDeduction'] ??
            map['absenceDeduction'],
      ),
      tax: _toD(
        amounts['tax'] ??
            map['tax'] ??
            map['withheldTaxMonthly'],
      ),
      netPay: _toD(
        amounts['netPay'] ??
            map['netPay'],
      ),
      source: _toS(
        meta['source'] ?? map['source'],
        def: 'backend_final',
      ),
      isClosedPayroll: _toB(
        meta['isClosedPayroll'] ?? map['isClosedPayroll'],
        def: true,
      ),
      grossBaseModeApplied: _toS(
        meta['grossBaseModeApplied'] ?? map['grossBaseModeApplied'],
      ),
    );
  }

  factory PayslipSummaryModel.fromJson(Map<String, dynamic> json) =>
      PayslipSummaryModel.fromMap(json);

  Map<String, dynamic> toMap() => {
        'employeeId': employeeId,
        'clinicId': clinicId,
        'month': month,
        'amounts': {
          'salary': salary,
          'socialSecurity': socialSecurity,
          'ot': ot,
          'commission': commission,
          'bonus': bonus,
          'leaveDeduction': leaveDeduction,
          'tax': tax,
          'netPay': netPay,
        },
        'meta': {
          'source': source,
          'isClosedPayroll': isClosedPayroll,
          'grossBaseModeApplied': grossBaseModeApplied,
        },
      };

  Map<String, dynamic> toJson() => toMap();

  double get recomputedNet =>
      salary - socialSecurity + ot + commission + bonus - leaveDeduction - tax;

  double get diffNet => (recomputedNet - netPay).abs();

  bool get hasMismatch => diffNet >= 0.01;

  List<PayslipLineItem> get lineItems => [
        PayslipLineItem(
          keyName: 'salary',
          label: 'เงินเดือน',
          sign: '',
          amount: salary,
        ),
        PayslipLineItem(
          keyName: 'socialSecurity',
          label: 'ประกันสังคม',
          sign: '-',
          amount: socialSecurity,
        ),
        PayslipLineItem(
          keyName: 'ot',
          label: 'OT',
          sign: '+',
          amount: ot,
        ),
        PayslipLineItem(
          keyName: 'commission',
          label: 'Commission',
          sign: '+',
          amount: commission,
        ),
        PayslipLineItem(
          keyName: 'bonus',
          label: 'โบนัส',
          sign: '+',
          amount: bonus,
        ),
        PayslipLineItem(
          keyName: 'leaveDeduction',
          label: 'หักวันลา/ขาด/หยุด',
          sign: '-',
          amount: leaveDeduction,
        ),
        PayslipLineItem(
          keyName: 'tax',
          label: 'ภาษี',
          sign: '-',
          amount: tax,
        ),
      ];
}

class PayslipLineItem {
  final String keyName;
  final String label;
  final String sign;
  final double amount;

  const PayslipLineItem({
    required this.keyName,
    required this.label,
    required this.sign,
    required this.amount,
  });
}