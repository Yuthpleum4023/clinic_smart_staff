// lib/models/helper_availability_model.dart
//
// HelperAvailability: ผู้ช่วยลงเวลาว่างทำงาน
// - date: yyyy-MM-dd
// - start/end: HH:mm
// - role: เช่น "ผู้ช่วยทันตแพทย์"
// - status: open / booked / cancelled
// - locationLabel / locationAddress: ระบุตำแหน่ง (เช่น สาขา/โซน)

class HelperAvailability {
  final String id;

  /// ตัวตนผู้ช่วย
  final String helperId;    // เช่น userId / เบอร์ / รหัส
  final String helperName;

  /// บทบาทงาน
  final String role;        // เช่น "ผู้ช่วยทันตแพทย์"

  /// เวลา
  final String date;        // yyyy-MM-dd
  final String start;       // HH:mm
  final String end;         // HH:mm

  /// สถานะ
  final String status;      // open | booked | cancelled
  final String note;

  /// 📍 ตำแหน่ง
  /// ใช้ match กับคลินิก (ไม่บังคับ แต่แนะนำให้ใส่)
  final String locationLabel;    // เช่น "สาขาอโศก", "โซนบางนา"
  final String locationAddress;  // รายละเอียดเพิ่มเติม

  const HelperAvailability({
    required this.id,
    required this.helperId,
    required this.helperName,
    required this.role,
    required this.date,
    required this.start,
    required this.end,
    this.status = 'open',
    this.note = '',
    this.locationLabel = '',
    this.locationAddress = '',
  });

  // =======================
  // Storage
  // =======================
  Map<String, dynamic> toMap() => {
        'id': id,
        'helperId': helperId,
        'helperName': helperName,
        'role': role,
        'date': date,
        'start': start,
        'end': end,
        'status': status,
        'note': note,
        'locationLabel': locationLabel,
        'locationAddress': locationAddress,
      };

  factory HelperAvailability.fromMap(Map<String, dynamic> map) {
    return HelperAvailability(
      id: (map['id'] ?? '').toString(),
      helperId: (map['helperId'] ?? '').toString(),
      helperName: (map['helperName'] ?? '').toString(),
      role: (map['role'] ?? 'ผู้ช่วย').toString(),
      date: (map['date'] ?? '').toString(),
      start: (map['start'] ?? '00:00').toString(),
      end: (map['end'] ?? '00:00').toString(),
      status: (map['status'] ?? 'open').toString(),
      note: (map['note'] ?? '').toString(),
      locationLabel: (map['locationLabel'] ?? '').toString(),
      locationAddress: (map['locationAddress'] ?? '').toString(),
    );
  }

  // =======================
  // Time utils
  // =======================
  static int _toMinutes(String hhmm) {
    final p = hhmm.split(':');
    if (p.length != 2) return 0;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    return h * 60 + m;
  }

  double get hours {
    int diff = _toMinutes(end) - _toMinutes(start);
    if (diff < 0) diff += 24 * 60;
    return diff / 60.0;
  }

  bool isInMonth(int y, int m) {
    final p = date.split('-');
    if (p.length < 2) return false;
    return (int.tryParse(p[0]) ?? 0) == y &&
        (int.tryParse(p[1]) ?? 0) == m;
  }

  /// ใช้ตรวจว่า availability นี้มีตำแหน่งหรือไม่
  bool get hasLocation => locationLabel.trim().isNotEmpty;

  /// ใช้ match แบบง่าย (label เท่ากัน)
  bool matchLocation(String otherLabel) {
    if (locationLabel.isEmpty || otherLabel.isEmpty) return false;
    return locationLabel.trim() == otherLabel.trim();
  }

  bool overlaps(String otherStart, String otherEnd) {
    final a1 = _toMinutes(start);
    final a2 = _toMinutes(end);
    final b1 = _toMinutes(otherStart);
    final b2 = _toMinutes(otherEnd);

    if (a1 <= a2 && b1 <= b2) {
      return (a1 < b2) && (b1 < a2);
    }
    // เคสข้ามวัน (ตอนนี้ยังไม่รองรับแบบแม่น 100%)
    return false;
  }

  // =======================
  // Copy
  // =======================
  HelperAvailability copyWith({
    String? helperId,
    String? helperName,
    String? role,
    String? date,
    String? start,
    String? end,
    String? status,
    String? note,
    String? locationLabel,
    String? locationAddress,
  }) {
    return HelperAvailability(
      id: id,
      helperId: helperId ?? this.helperId,
      helperName: helperName ?? this.helperName,
      role: role ?? this.role,
      date: date ?? this.date,
      start: start ?? this.start,
      end: end ?? this.end,
      status: status ?? this.status,
      note: note ?? this.note,
      locationLabel: locationLabel ?? this.locationLabel,
      locationAddress: locationAddress ?? this.locationAddress,
    );
  }
}
