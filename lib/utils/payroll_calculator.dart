// lib/utils/payroll_calculator.dart
//
// ✅ Payroll Calculator (Full-time + Part-time + OT)
// - Full-time: baseSalary + bonus + OT - SSO(% with BASE CAP 17,500 & MAX 750) - absentDeduction
// - Part-time: (regularHours * hourlyWage) + bonus + OT (no SSO, no absent)
// - OT: sum(hours * rate * multiplier)  rate = hourlyRate(fulltime) or hourlyWage(parttime)
//
// ✅ IMPORTANT FIX:
// - ❌ ไม่ fix % ประกันสังคม
// - ✅ fix "ฐานเงินเดือนสูงสุด" ที่ 17,500 บาท
// - ✅ คงเพดานเงินหักสูงสุด 750 บาท
//

import '../models/employee_model.dart';

class PayrollMonthResult {
  final int year;
  final int month;

  final bool isPartTime;

  // Full-time
  final double monthlyBaseSalary;
  final int absentDays;
  final double socialSecurity; // SSO deduction
  final double absentDeduction;

  // Shared
  final double bonus;

  // Part-time
  final double hourlyWage;
  final double regularHours;
  final double regularPay;

  // OT
  final double otHours;
  final double otPay;

  // Final
  final double net;

  const PayrollMonthResult({
    required this.year,
    required this.month,
    required this.isPartTime,

    required this.monthlyBaseSalary,
    required this.absentDays,
    required this.socialSecurity,
    required this.absentDeduction,

    required this.bonus,

    required this.hourlyWage,
    required this.regularHours,
    required this.regularPay,

    required this.otHours,
    required this.otPay,

    required this.net,
  });
}

class PayrollCalculator {
  // ============================================================
  // ✅ SSO GLOBAL RULES (ต้องตรงกับ EmployeeModel)
  // ============================================================
  static const double ssoMaxBaseSalary = 17500.0; // ✅ เพดานฐานเงินเดือน
  static const double ssoMaxEmployeeMonthly = 750.0; // ✅ เพดานเงินหัก

  static bool isPartTime(EmployeeModel emp) =>
      emp.employmentType.toLowerCase() == 'parttime';

  // ============================================================
  // ✅ FIXED: คำนวณ SSO ด้วยฐาน capped
  // ============================================================
  static double _calcSso(double baseSalary, double percent) {
    // cap ฐานเงินเดือนก่อน
    final cappedBase =
        baseSalary > ssoMaxBaseSalary ? ssoMaxBaseSalary : baseSalary;

    final raw = cappedBase * (percent / 100.0);

    // cap เงินหักสูงสุด
    return raw > ssoMaxEmployeeMonthly ? ssoMaxEmployeeMonthly : raw;
  }

  static double _calcAbsentDeduction(double baseSalary, int absentDays) {
    return (baseSalary / 30.0) * absentDays;
  }

  static double _sumOtHours(EmployeeModel emp, int year, int month) {
    double total = 0.0;
    for (final e in emp.otEntries) {
      if (e.isInMonth(year, month)) total += e.hours;
    }
    return total;
  }

  static double _sumOtPay({
    required EmployeeModel emp,
    required int year,
    required int month,
    required double rate, // hourly rate
  }) {
    double total = 0.0;
    for (final e in emp.otEntries) {
      if (e.isInMonth(year, month)) {
        total += e.hours * rate * e.multiplier;
      }
    }
    return total;
  }

  /// ============================================================
  /// ✅ Core compute: 1 employee, 1 month
  /// [parttimeRegularHours] = hours จาก SharedPreferences (work_entries_{id})
  /// ============================================================
  static PayrollMonthResult computeMonth({
    required EmployeeModel emp,
    required int year,
    required int month,
    required double ssoPercent,
    required double parttimeRegularHours,
    int workDaysPerMonth = 26,
    int hoursPerDay = 8,
  }) {
    final part = isPartTime(emp);
    final bonus = emp.bonus;
    final otHours = _sumOtHours(emp, year, month);

    if (!part) {
      // ---------------- Full-time ----------------
      final baseSalary = emp.baseSalary;
      final absentDays = emp.absentDays;

      final hourlyRate = emp.hourlyRate(
        workDaysPerMonth: workDaysPerMonth,
        hoursPerDay: hoursPerDay,
      );

      final otPay =
          _sumOtPay(emp: emp, year: year, month: month, rate: hourlyRate);

      // ✅ FIXED SSO (cap base 17,500)
      final sso = _calcSso(baseSalary, ssoPercent);
      final absentDeduction = _calcAbsentDeduction(baseSalary, absentDays);

      final net = (baseSalary + bonus + otPay) - sso - absentDeduction;

      return PayrollMonthResult(
        year: year,
        month: month,
        isPartTime: false,

        monthlyBaseSalary: baseSalary,
        absentDays: absentDays,
        socialSecurity: sso,
        absentDeduction: absentDeduction,

        bonus: bonus,

        hourlyWage: 0.0,
        regularHours: 0.0,
        regularPay: 0.0,

        otHours: otHours,
        otPay: otPay,

        net: net,
      );
    } else {
      // ---------------- Part-time ----------------
      final hourlyWage = emp.hourlyWage;

      final regularHours = parttimeRegularHours;
      final regularPay = regularHours * hourlyWage;

      final otPay =
          _sumOtPay(emp: emp, year: year, month: month, rate: hourlyWage);

      final net = regularPay + bonus + otPay;

      return PayrollMonthResult(
        year: year,
        month: month,
        isPartTime: true,

        monthlyBaseSalary: 0.0,
        absentDays: 0,
        socialSecurity: 0.0,
        absentDeduction: 0.0,

        bonus: bonus,

        hourlyWage: hourlyWage,
        regularHours: regularHours,
        regularPay: regularPay,

        otHours: otHours,
        otPay: otPay,

        net: net,
      );
    }
  }
}
