// ============================================================
// employee_model.dart
// รองรับ Full-time + Part-time + OT
// ✅ HARDENED: staffId fallback + robust parsing
// ✅ PATCH: robust numeric parsing for OT multiplier / absentDays / salary fields
// ✅ NEW: linkedUserId รองรับการเชื่อม employee ↔ user account
// ✅ UPDATED:
// - รองรับ staffId จริงจาก backend staff_service (Mongo _id string)
// - ไม่บังคับ prefix stf_ อีกแล้ว
// - รองรับทั้ง monthlySalary/hourlyRate และ baseSalary/hourlyWage
// - รองรับ employmentType ทั้ง fulltime/fullTime และ parttime/partTime
// ============================================================

class OTEntry {
  final String date;
  final String start;
  final String end;
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
    double parseDouble(dynamic v, double fallback) {
      if (v is num) return v.toDouble();
      final x = double.tryParse('${v ?? ''}');
      return (x == null || x <= 0) ? fallback : x;
    }

    return OTEntry(
      date: (map['date'] ?? '').toString(),
      start: (map['start'] ?? '00:00').toString(),
      end: (map['end'] ?? '00:00').toString(),
      multiplier: parseDouble(map['multiplier'], 1.5),
    );
  }

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

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

class EmployeeModel {
  final String id;

  /// staff_service / payroll_service ใช้ employee master id จริง
  /// อาจเป็น Mongo _id string หรือ legacy stf_...
  final String staffId;

  /// ใช้เชื่อม employee record กับ user account จริง
  final String linkedUserId;

  final String employeeCode;
  final String firstName;
  final String lastName;
  final String position;
  final String employmentType;

  final double baseSalary;
  final double bonus;
  final int absentDays;
  final double hourlyWage;

  final List<OTEntry> otEntries;

  EmployeeModel({
    required this.id,
    String staffId = '',
    this.linkedUserId = '',
    this.employeeCode = '',
    required this.firstName,
    required this.lastName,
    required this.position,
    String employmentType = 'fulltime',
    this.baseSalary = 0.0,
    this.bonus = 0.0,
    this.absentDays = 0,
    this.hourlyWage = 0.0,
    this.otEntries = const [],
  })  : staffId = _normalizeStaffId(staffId, id),
        employmentType = _normalizeEmploymentType(employmentType);

  static String _normalizeStaffId(String raw, String fallbackId) {
    final s = raw.trim();
    if (s.isNotEmpty) return s;

    final fid = fallbackId.trim();
    if (fid.isNotEmpty) return fid;

    return '';
  }

  static String _normalizeEmploymentType(String raw) {
    final t = raw.trim().toLowerCase();
    if (t == 'parttime' || t == 'part-time' || t == 'part_time') {
      return 'parttime';
    }
    return 'fulltime';
  }

  static double _toDouble(dynamic v, [double fallback = 0.0]) {
    if (v is num) return v.toDouble();
    final raw = '${v ?? ''}'.replaceAll(',', '').trim();
    final x = double.tryParse(raw);
    return x ?? fallback;
  }

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final raw = '${v ?? ''}'.trim();
    final x = int.tryParse(raw);
    return x ?? fallback;
  }

  String get fullName => '$firstName $lastName'.trim();

  bool get isPartTime => employmentType.toLowerCase().trim() == 'parttime';
  bool get isFullTime => !isPartTime;

  bool get isLinkedUser => linkedUserId.trim().isNotEmpty;

  static const double ssoMaxBaseSalary = 17500.0;
  static const double ssoMaxEmployeeMonthly = 875.0;

  double socialSecurity(double percent) {
    if (!isFullTime) return 0.0;

    final cappedBase =
        baseSalary > ssoMaxBaseSalary ? ssoMaxBaseSalary : baseSalary;

    final sso = cappedBase * (percent / 100.0);

    return sso > ssoMaxEmployeeMonthly ? ssoMaxEmployeeMonthly : sso;
  }

  double absentDeduction() {
    if (!isFullTime) return 0.0;
    return (baseSalary / 30.0) * absentDays;
  }

  double netSalary(double ssoPercent) {
    if (!isFullTime) return 0.0;
    return (baseSalary + bonus) -
        socialSecurity(ssoPercent) -
        absentDeduction();
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
        ? hourlyRate(
            workDaysPerMonth: workDaysPerMonth,
            hoursPerDay: hoursPerDay,
          )
        : hourlyWage;

    double total = 0;
    for (final e in otEntries) {
      if (e.isInMonth(year, month)) {
        total += e.hours * rate * e.multiplier;
      }
    }
    return total;
  }

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
    String? staffId,
    String? linkedUserId,
    String? employeeCode,
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
    final nextId = id ?? this.id;
    return EmployeeModel(
      id: nextId,
      staffId: staffId ?? this.staffId,
      linkedUserId: linkedUserId ?? this.linkedUserId,
      employeeCode: employeeCode ?? this.employeeCode,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      position: position ?? this.position,
      employmentType: employmentType ?? this.employmentType,
      baseSalary: baseSalary ?? this.baseSalary,
      bonus: bonus ?? this.bonus,
      absentDays: absentDays ?? this.absentDays,
      hourlyWage: hourlyWage ?? this.hourlyWage,
      otEntries: otEntries ?? this.otEntries,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'staffId': staffId,
      'linkedUserId': linkedUserId,
      'employeeCode': employeeCode,
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
    String s(dynamic v) => (v ?? '').toString().trim();

    final id = s(map['id']).isNotEmpty ? s(map['id']) : s(map['_id']);

    final candidates = <String>[
      s(map['staffId']),
      s(map['staffID']),
      s(map['staff_id']),
      s(map['employeeId']),
      s(map['employeeID']),
      s(map['employee_id']),
      s(map['principalId']),
      s(map['principal_id']),
      s(map['_id']),
      s(map['id']),
    ].where((x) => x.isNotEmpty).toList();

    final rawStaffId = candidates.isNotEmpty ? candidates.first : '';

    final rawOt = map['otEntries'];
    List<OTEntry> ots = [];
    if (rawOt is List) {
      ots = rawOt
          .whereType<Map>()
          .map((m) => OTEntry.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }

    final linkedCandidates = <String>[
      s(map['linkedUserId']),
      s(map['linked_user_id']),
      s(map['userId']),
      s(map['userID']),
      s(map['user_id']),
      s(map['authUserId']),
      s(map['auth_user_id']),
    ].where((x) => x.isNotEmpty).toList();

    final linkedUserId =
        linkedCandidates.isNotEmpty ? linkedCandidates.first : '';

    return EmployeeModel(
      id: id,
      staffId: rawStaffId,
      linkedUserId: linkedUserId,
      employeeCode: s(map['employeeCode']),
      firstName: s(map['firstName']),
      lastName: s(map['lastName']),
      position: s(map['position']).isNotEmpty ? s(map['position']) : 'Staff',
      employmentType: s(map['employmentType']),
      baseSalary: _toDouble(map['baseSalary'] ?? map['monthlySalary']),
      bonus: _toDouble(map['bonus']),
      absentDays: _toInt(map['absentDays']),
      hourlyWage: _toDouble(map['hourlyWage'] ?? map['hourlyRate']),
      otEntries: ots,
    );
  }
}