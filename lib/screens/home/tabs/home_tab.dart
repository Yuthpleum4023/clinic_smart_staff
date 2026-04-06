import 'package:flutter/material.dart';

class HomeTab extends StatelessWidget {
  final bool isAttendanceUser;
  final bool attendancePremiumEnabled;
  final bool isEmployee;
  final bool isClinic;
  final bool isHelper;

  final Widget premiumGateCard;
  final Widget attendanceCard;
  final Widget policyCard;
  final Widget payslipCard;
  final Widget urgentCard;
  final Widget? trustScoreCard;
  final Widget? marketCard;

  // ✅ NEW: สำหรับ helper เลือกกะก่อนสแกน
  final Widget? helperShiftCard;

  const HomeTab({
    super.key,
    required this.isAttendanceUser,
    required this.attendancePremiumEnabled,
    required this.isEmployee,
    required this.isClinic,
    required this.isHelper,
    required this.premiumGateCard,
    required this.attendanceCard,
    required this.policyCard,
    required this.payslipCard,
    required this.urgentCard,
    this.trustScoreCard,
    this.marketCard,
    this.helperShiftCard,
  });

  static const double _sectionGap = 10;

  Widget _gap() => const SizedBox(height: _sectionGap);

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];

    if (isAttendanceUser) {
      sections.add(premiumGateCard);
      sections.add(_gap());

      // ✅ NEW: ถ้าเป็น helper และมีการ์ดเลือกกะ ให้แสดงก่อน attendance card
      if (isHelper && helperShiftCard != null) {
        sections.add(helperShiftCard!);
        sections.add(_gap());
      }

      sections.add(attendanceCard);
      sections.add(_gap());

      sections.add(policyCard);
    }

    if (isEmployee) {
      if (sections.isNotEmpty) sections.add(_gap());
      sections.add(payslipCard);
    }

    if (sections.isNotEmpty) sections.add(_gap());
    sections.add(urgentCard);

    if (isClinic && trustScoreCard != null) {
      sections.add(_gap());
      sections.add(trustScoreCard!);
    }

    if ((isClinic || isHelper) && marketCard != null) {
      sections.add(_gap());
      sections.add(marketCard!);
    }

    sections.add(
      SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      physics: const BouncingScrollPhysics(),
      children: sections,
    );
  }
}