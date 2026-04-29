// ============================================================
// lib/models/employee_model.dart
//
// ✅ PRODUCTION FULL FILE
// รองรับ Full-time + Part-time + OT
//
// ✅ Hardened for backend + local cache:
// - staffId fallback robust
// - linkedUserId robust
// - fullName fallback split เป็น firstName/lastName
// - รองรับ monthlySalary/hourlyRate และ baseSalary/hourlyWage/salary
// - รองรับ employmentType หลายรูปแบบ เช่น fullTime, partTime, hourly
// - bonus / absentDays / position ไม่หายจาก local
// - เพิ่ม toJson/fromJson compatibility
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

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static double _toDouble(dynamic v, [double fallback = 0.0]) {
    if (v is num) return v.toDouble();

    final raw = _s(v).replaceAll(',', '');
    final x = double.tryParse(raw);

    return x ?? fallback;
  }

  Map<String, dynamic> toMap() => {
        'date': date,
        'start': start,
        'end': end,
        'multiplier': multiplier,
      };

  Map<String, dynamic> toJson() => toMap();

  factory OTEntry.fromMap(Map<String, dynamic> map) {
    final mul = _toDouble(map['multiplier'], 1.5);

    return OTEntry(
      date: _s(map['date']).isNotEmpty ? _s(map['date']) : _s(map['workDate']),
      start: _s(map['start']).isNotEmpty
          ? _s(map['start'])
          : _s(map['startTime']).isNotEmpty
              ? _s(map['startTime'])
              : '00:00',
      end: _s(map['end']).isNotEmpty
          ? _s(map['end'])
          : _s(map['endTime']).isNotEmpty
              ? _s(map['endTime'])
              : '00:00',
      multiplier: mul <= 0 ? 1.5 : mul,
    );
  }

  factory OTEntry.fromJson(Map<String, dynamic> json) => OTEntry.fromMap(json);

  static (int, int)? _parseHHmm(String hhmm) {
    final parts = hhmm.trim().split(':');
    if (parts.length != 2) return null;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);

    if (h == null || m == null) return null;
    if (h < 0 || h > 23) return null;
    if (m < 0 || m > 59) return null;

    return (h, m);
  }

  static int _toMinutes(String hhmm) {
    final parsed = _parseHHmm(hhmm);
    if (parsed == null) return 0;
    return parsed.$1 * 60 + parsed.$2;
  }

  double get hours {
    final s = _toMinutes(start);
    final e = _toMinutes(end);

    int diff = e - s;
    if (diff < 0) diff += 24 * 60;

    if (diff <= 0) return 0.0;
    return diff / 60.0;
  }

  bool isInMonth(int year, int month) {
    final d = DateTime.tryParse(date);
    if (d != null) {
      return d.year == year && d.month == month;
    }

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

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static String _normalizeStaffId(String raw, String fallbackId) {
    final s = raw.trim();
    if (s.isNotEmpty) return s;

    final fid = fallbackId.trim();
    if (fid.isNotEmpty) return fid;

    return '';
  }

  static String _normalizeEmploymentType(String raw) {
    final t = raw.trim().toLowerCase();

    if (t == 'parttime' ||
        t == 'part-time' ||
        t == 'part_time' ||
        t == 'part time' ||
        t == 'hourly') {
      return 'parttime';
    }

    return 'fulltime';
  }

  static double _toDouble(dynamic v, [double fallback = 0.0]) {
    if (v is num) return v.toDouble();

    final raw = _s(v).replaceAll(',', '');
    final x = double.tryParse(raw);

    return x ?? fallback;
  }

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();

    final raw = _s(v).replaceAll(',', '');
    final x = int.tryParse(raw);

    return x ?? fallback;
  }

  static double _firstNumber(List<dynamic> values, [double fallback = 0.0]) {
    for (final v in values) {
      final s = _s(v);
      if (v == null || s.isEmpty) continue;

      final n = _toDouble(v, fallback);
      return n;
    }

    return fallback;
  }

  static String _firstString(List<dynamic> values, [String fallback = '']) {
    for (final v in values) {
      final s = _s(v);
      if (s.isNotEmpty) return s;
    }

    return fallback;
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;

    if (v is Map) {
      return Map<String, dynamic>.from(
        v.map((k, val) => MapEntry(k.toString(), val)),
      );
    }

    return <String, dynamic>{};
  }

  static (String, String) _splitName({
    required String firstName,
    required String lastName,
    required String fullName,
  }) {
    final fn = firstName.trim();
    final ln = lastName.trim();

    if (fn.isNotEmpty || ln.isNotEmpty) {
      return (fn, ln);
    }

    final full = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (full.isEmpty) return ('', '');

    final parts = full.split(' ');
    if (parts.length == 1) return (parts.first, '');

    return (parts.first, parts.sublist(1).join(' '));
  }

  String get fullName => '$firstName $lastName'.trim();

  bool get isPartTime => employmentType.toLowerCase().trim() == 'parttime';
  bool get isFullTime => !isPartTime;

  bool get isLinkedUser => linkedUserId.trim().isNotEmpty;

  static const double ssoMaxBaseSalary = 17500.0;
  static const double ssoMaxEmployeeMonthly = 875.0;

  double socialSecurity(double percent) {
    if (!isFullTime) return 0.0;

    final safeBase = baseSalary < 0 ? 0.0 : baseSalary;
    final cappedBase =
        safeBase > ssoMaxBaseSalary ? ssoMaxBaseSalary : safeBase;

    final safePercent = percent < 0 ? 0.0 : percent;
    final sso = cappedBase * (safePercent / 100.0);

    return sso > ssoMaxEmployeeMonthly ? ssoMaxEmployeeMonthly : sso;
  }

  double absentDeduction() {
    if (!isFullTime) return 0.0;

    final safeBase = baseSalary < 0 ? 0.0 : baseSalary;
    final safeAbsent = absentDays < 0 ? 0 : absentDays;

    return (safeBase / 30.0) * safeAbsent;
  }

  double netSalary(double ssoPercent) {
    if (!isFullTime) return 0.0;

    final net = (baseSalary + bonus) -
        socialSecurity(ssoPercent) -
        absentDeduction();

    return net < 0 ? 0.0 : net;
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
      if (e.isInMonth(year, month)) {
        total += e.hours;
      }
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

    if (rate <= 0) return 0.0;

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
      '_id': id,
      'staffId': staffId,
      'linkedUserId': linkedUserId,
      'userId': linkedUserId,
      'employeeCode': employeeCode,
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'position': position,
      'employmentType': employmentType,
      'baseSalary': baseSalary,
      'monthlySalary': baseSalary,
      'bonus': bonus,
      'absentDays': absentDays,
      'hourlyWage': hourlyWage,
      'hourlyRate': hourlyWage,
      'otEntries': otEntries.map((e) => e.toMap()).toList(),
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory EmployeeModel.fromMap(Map<String, dynamic> map) {
    final staffMap = _asMap(map['staff']);
    final userMap = _asMap(map['user']);
    final linkedUserMap = _asMap(map['linkedUser']);

    final id = _firstString([
      map['id'],
      map['_id'],
      map['employeeId'],
      map['staffId'],
      staffMap['id'],
      staffMap['_id'],
      staffMap['staffId'],
    ]);

    final rawStaffId = _firstString([
      map['staffId'],
      map['staffID'],
      map['staff_id'],
      map['employeeId'],
      map['employeeID'],
      map['employee_id'],
      map['principalId'],
      map['principal_id'],
      staffMap['staffId'],
      staffMap['id'],
      staffMap['_id'],
      map['_id'],
      map['id'],
    ]);

    final linkedUserId = _firstString([
      map['linkedUserId'],
      map['linked_user_id'],
      map['userId'],
      map['userID'],
      map['user_id'],
      map['authUserId'],
      map['auth_user_id'],
      userMap['id'],
      userMap['_id'],
      userMap['userId'],
      linkedUserMap['id'],
      linkedUserMap['_id'],
      linkedUserMap['userId'],
    ]);

    final fullName = _firstString([
      map['fullName'],
      map['name'],
      userMap['fullName'],
      linkedUserMap['fullName'],
    ]);

    final names = _splitName(
      firstName: _firstString([map['firstName'], map['first_name']]),
      lastName: _firstString([map['lastName'], map['last_name']]),
      fullName: fullName,
    );

    final rawOt = map['otEntries'];
    final ots = <OTEntry>[];

    if (rawOt is List) {
      for (final item in rawOt) {
        final m = _asMap(item);
        if (m.isNotEmpty) {
          ots.add(OTEntry.fromMap(m));
        }
      }
    }

    final employmentType = _normalizeEmploymentType(
      _firstString([
        map['employmentType'],
        map['employeeType'],
        map['workType'],
        staffMap['employmentType'],
      ], 'fulltime'),
    );

    final baseSalary = _firstNumber([
      map['baseSalary'],
      map['monthlySalary'],
      map['salary'],
      map['monthlyWage'],
      map['grossBase'],
      map['grossMonthly'],
      staffMap['baseSalary'],
      staffMap['monthlySalary'],
      staffMap['salary'],
    ]);

    final hourlyWage = _firstNumber([
      map['hourlyWage'],
      map['hourlyRate'],
      map['wagePerHour'],
      map['ratePerHour'],
      staffMap['hourlyWage'],
      staffMap['hourlyRate'],
    ]);

    final bonus = _firstNumber([
      map['bonus'],
      map['commission'],
      map['otherAllowance'],
      staffMap['bonus'],
    ]);

    final absentDays = _toInt(
      _firstString([
        map['absentDays'],
        map['absent_days'],
        map['leaveDays'],
        staffMap['absentDays'],
      ], '0'),
    );

    return EmployeeModel(
      id: id,
      staffId: rawStaffId,
      linkedUserId: linkedUserId,
      employeeCode: _firstString([
        map['employeeCode'],
        map['employee_code'],
        map['code'],
        staffMap['employeeCode'],
      ]),
      firstName: names.$1,
      lastName: names.$2,
      position: _firstString([
        map['position'],
        map['roleTitle'],
        map['jobTitle'],
        staffMap['position'],
      ], 'Staff'),
      employmentType: employmentType,
      baseSalary: employmentType == 'parttime' ? 0.0 : baseSalary,
      bonus: bonus < 0 ? 0.0 : bonus,
      absentDays: employmentType == 'parttime'
          ? 0
          : absentDays < 0
              ? 0
              : absentDays,
      hourlyWage: employmentType == 'parttime' ? hourlyWage : 0.0,
      otEntries: ots,
    );
  }

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    return EmployeeModel.fromMap(json);
  }
}