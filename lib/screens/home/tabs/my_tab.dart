import 'package:flutter/material.dart';

class MyTab extends StatelessWidget {
  final bool isAttendanceUser;
  final bool attendancePremiumEnabled;
  final bool hasBackendPolicy;
  final bool isClinic;
  final bool isHelper;
  final bool isEmployee;
  final bool premiumAttendanceEnabled;

  final VoidCallback onOpenAttendanceHistory;
  final Widget policyCard;
  final Widget? clinicSection;
  final Widget? helperSection;
  final Widget? employeeSection;
  final ValueChanged<bool>? onTogglePremiumAttendance;
  final VoidCallback onLogout;

  const MyTab({
    super.key,
    required this.isAttendanceUser,
    required this.attendancePremiumEnabled,
    required this.hasBackendPolicy,
    required this.isClinic,
    required this.isHelper,
    required this.isEmployee,
    required this.premiumAttendanceEnabled,
    required this.onOpenAttendanceHistory,
    required this.policyCard,
    this.clinicSection,
    this.helperSection,
    this.employeeSection,
    this.onTogglePremiumAttendance,
    required this.onLogout,
  });

  static const double _sectionGap = 10;

  Widget _gap() => const SizedBox(height: _sectionGap);

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _attendanceHistoryCard() {
    return Card(
      elevation: 0.6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.purple.shade100),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 6,
        ),
        leading: CircleAvatar(
          backgroundColor: Colors.purple.shade50,
          child: Icon(Icons.history, color: Colors.purple.shade700),
        ),
        title: const Text(
          'ประวัติการลงเวลาย้อนหลัง',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text(
            'ดูรายการลงเวลาย้อนหลัง พร้อมสถานะการทำงานและรายละเอียดในแต่ละวัน',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpenAttendanceHistory,
      ),
    );
  }

  Widget _premiumSwitchCard() {
    return Card(
      elevation: 0.4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        title: const Text(
          'บันทึกเวลางานแบบพรีเมียม (ทดสอบ)',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text(
          'เปิดหรือปิดฟีเจอร์สแกนลายนิ้วมือสำหรับบันทึกเวลาทำงาน',
        ),
        value: premiumAttendanceEnabled,
        onChanged: onTogglePremiumAttendance,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _logoutCard() {
    return Card(
      elevation: 0.4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 4,
        ),
        leading: const Icon(Icons.logout),
        title: const Text(
          'ออกจากระบบ',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('ออกจากบัญชีนี้'),
        onTap: onLogout,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      const SizedBox(height: 4),
      _sectionHeader(context, 'เมนูของฉัน'),
    ];

    if (isAttendanceUser && attendancePremiumEnabled) {
      sections.add(_attendanceHistoryCard());
      sections.add(_gap());
    }

    if (isAttendanceUser) {
      sections.add(policyCard);
      sections.add(_gap());
    }

    if (isClinic && clinicSection != null) {
      sections.add(clinicSection!);
      sections.add(_gap());
    }

    if (isHelper && helperSection != null) {
      sections.add(helperSection!);
      sections.add(_gap());
    }

    if (isEmployee && employeeSection != null) {
      sections.add(employeeSection!);
      sections.add(_gap());
    }

    if (isAttendanceUser &&
        !hasBackendPolicy &&
        onTogglePremiumAttendance != null) {
      sections.add(_premiumSwitchCard());
      sections.add(_gap());
    }

    sections.add(_logoutCard());
    sections.add(
      SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      physics: const BouncingScrollPhysics(),
      children: sections,
    );
  }
}