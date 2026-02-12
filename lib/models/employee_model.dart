// ============================================================
// employee_model.dart
// รองรับ Full-time + Part-time + OT
//
// ✅ แนวทางที่เข้ากับโปรเจกต์คุณตอนนี้:
// - Part-time "ชั่วโมงทำงานปกติ" เก็บใน SharedPreferences แยก key: work_entries_{emp.id}
//   (เป็น List<{date, hours}>) -> ไม่เก็บ start/end ใน EmployeeModel
// - SSO% รับจากภายนอก (ตั้งค่าได้จาก UI)
// - ✅ FIX NEW RULE: ฐานคำนวณประกันสังคม (SSO base) สูงสุด 17,500 บาท
//   (ไม่ fix % แต่ fix เพดานฐานเงินเดือน)
// - ✅ FIX: เพดานเงินหักสูงสุด 875 บาท/เดือน (ตามฐาน 17,500 * 5% = 875)
//   (% ยังปรับได้ แต่ไม่ให้หักเกินเพดานนี้ตามที่คุณกำหนด)
// ============================================================

class OTEntry {
  final String date; // yyyy-MM-dd
  final String start; // HH:mm
  final String end; // HH:mm

  /// 1.5 = OT ปกติ
  /// 2.0 = OT วันหยุด / นักขัตฤกษ์
  final double multiplier;

  const OTEntry({
    required this.date,
    required this.start,
    required this.end,
    this.multiplier = 1.5,
  });

  Map<String, dynamic> toMap() => {
        'date': date,
        'start': start,
        'end': end,
        'multiplier': multiplier,
      };

  factory OTEntry.fromMap(Map<String, dynamic> map) {
    return OTEntry(
      date: (map['date'] ?? '').toString(),
      start: (map['start'] ?? '00:00').toString(),
      end: (map['end'] ?? '00:00').toString(),
      multiplier: (map['multiplier'] as num? ?? 1.5).toDouble(),
    );
  }

  // ---------- Utils ----------
  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  /// ชั่วโมง OT (รองรับข้ามวัน)
  double get hours {
    final s = _toMinutes(start);
    final e = _toMinutes(end);
    int diff = e - s;
    if (diff < 0) diff += 24 * 60;
    return diff / 60.0;
  }

  bool isInMonth(int year, int month) {
    final parts = date.split('-');
    if (parts.length < 2) return false;
    final y = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return y == year && m == month;
  }
}

// ============================================================
// EmployeeModel
// ============================================================
class EmployeeModel {
  final String id;
  final String firstName;
  final String lastName;
  final String position;

  /// fulltime | parttime
  final String employmentType;

  /// ---------- Full-time ----------
  final double baseSalary;
  final double bonus;
  final int absentDays;

  /// ---------- Part-time ----------
  final double hourlyWage; // บาท/ชม.

  /// ---------- OT ----------
  final List<OTEntry> otEntries;

  EmployeeModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.position,
    this.employmentType = 'fulltime',

    // full-time
    this.baseSalary = 0.0,
    this.bonus = 0.0,
    this.absentDays = 0,

    // part-time
    this.hourlyWage = 0.0,

    // OT
    this.otEntries = const [],
  });

  String get fullName => '$firstName $lastName';

  bool get isPartTime => employmentType.toLowerCase().trim() == 'parttime';
  bool get isFullTime => !isPartTime;

  // ============================================================
  // ✅ SSO RULES (GLOBAL)
  // - ไม่ fix % (รับจากภายนอก)
  // - fix เพดานฐานเงินเดือน = 17,500 บาท
  // - fix เพดานเงินหักสูงสุด = 875 บาท/เดือน
  // ============================================================
  static const double ssoMaxBaseSalary = 17500.0; // ✅ ฐานสูงสุด
  static const double ssoMaxEmployeeMonthly = 875.0; // ✅ เพดานเงินหักสูงสุด

  // ============================================================
  // ---------- Full-time Logic (รับ % จากภายนอก) ----------
  // ============================================================
  double socialSecurity(double percent) {
    if (!isFullTime) return 0.0;

    // ✅ cap ฐานเงินเดือนที่ 17,500 ก่อนคำนวณ %
    final cappedBase =
        baseSalary > ssoMaxBaseSalary ? ssoMaxBaseSalary : baseSalary;

    // % ยังปรับได้จาก UI
    final sso = cappedBase * (percent / 100.0);

    // ✅ cap เพดานเงินหักสูงสุด 875
    return sso > ssoMaxEmployeeMonthly ? ssoMaxEmployeeMonthly : sso;
  }

  double absentDeduction() {
    if (!isFullTime) return 0.0;
    return (baseSalary / 30.0) * absentDays;
  }

  double netSalary(double ssoPercent) {
    if (!isFullTime) return 0.0;
    return (baseSalary + bonus) - socialSecurity(ssoPercent) - absentDeduction();
  }

  double hourlyRate({
    int workDaysPerMonth = 26,
    int hoursPerDay = 8,
  }) {
    if (!isFullTime) return 0.0;
    final denom = workDaysPerMonth * hoursPerDay;
    if (denom <= 0) return 0.0;
    return baseSalary / denom;
  }

  // ============================================================
  // ---------- OT (ใช้ร่วมกัน) ----------
  // ============================================================
  double totalOtHoursOfMonth(int year, int month) {
    double total = 0;
    for (final e in otEntries) {
      if (e.isInMonth(year, month)) total += e.hours;
    }
    return total;
  }

  double totalOtAmountOfMonth(
    int year,
    int month, {
    int workDaysPerMonth = 26,
    int hoursPerDay = 8,
  }) {
    final rate = isFullTime
        ? hourlyRate(workDaysPerMonth: workDaysPerMonth, hoursPerDay: hoursPerDay)
        : hourlyWage;

    double total = 0;
    for (final e in otEntries) {
      if (e.isInMonth(year, month)) {
        total += e.hours * rate * e.multiplier;
      }
    }
    return total;
  }

  // ============================================================
  // ---------- Mutations (immutable) ----------
  // ============================================================
  EmployeeModel addOtEntry(OTEntry entry) {
    final next = List<OTEntry>.from(otEntries)..add(entry);
    return copyWith(otEntries: next);
  }

  EmployeeModel removeOtEntryAt(int index) {
    if (index < 0 || index >= otEntries.length) return this;
    final next = List<OTEntry>.from(otEntries)..removeAt(index);
    return copyWith(otEntries: next);
  }

  EmployeeModel copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? position,
    String? employmentType,
    double? baseSalary,
    double? bonus,
    int? absentDays,
    double? hourlyWage,
    List<OTEntry>? otEntries,
  }) {
    return EmployeeModel(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      position: position ?? this.position,
      employmentType: (employmentType ?? this.employmentType)
              .toLowerCase()
              .trim()
              .isEmpty
          ? 'fulltime'
          : (employmentType ?? this.employmentType).toLowerCase().trim(),
      baseSalary: baseSalary ?? this.baseSalary,
      bonus: bonus ?? this.bonus,
      absentDays: absentDays ?? this.absentDays,
      hourlyWage: hourlyWage ?? this.hourlyWage,
      otEntries: otEntries ?? this.otEntries,
    );
  }

  // ============================================================
  // ---------- Storage ----------
  // ============================================================
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'position': position,
      'employmentType': employmentType,
      'baseSalary': baseSalary,
      'bonus': bonus,
      'absentDays': absentDays,
      'hourlyWage': hourlyWage,
      'otEntries': otEntries.map((e) => e.toMap()).toList(),
    };
  }

  factory EmployeeModel.fromMap(Map<String, dynamic> map) {
    final rawOt = map['otEntries'];

    List<OTEntry> ots = [];
    if (rawOt is List) {
      ots = rawOt
          .whereType<Map>()
          .map((m) => OTEntry.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }

    final typeRaw =
        (map['employmentType'] ?? 'fulltime').toString().toLowerCase().trim();
    final type = (typeRaw == 'parttime') ? 'parttime' : 'fulltime';

    return EmployeeModel(
      id: (map['id'] ?? '').toString(),
      firstName: (map['firstName'] ?? '').toString(),
      lastName: (map['lastName'] ?? '').toString(),
      position: (map['position'] ?? 'Staff').toString(),
      employmentType: type,
      baseSalary: (map['baseSalary'] as num? ?? 0).toDouble(),
      bonus: (map['bonus'] as num? ?? 0).toDouble(),
      absentDays: (map['absentDays'] as int? ?? 0),
      hourlyWage: (map['hourlyWage'] as num? ?? 0).toDouble(),
      otEntries: ots,
    );
  }
}
