// lib/models/clinic_shift_need_model.dart
//
// ClinicShiftNeed: คลินิกเปิดความต้องการผู้ช่วย (shift need)
// - date: yyyy-MM-dd
// - start/end: HH:mm
// - role: เช่น "ผู้ช่วยทันตแพทย์"
// - requiredCount: จำนวนที่ต้องการ
// - status: open / filled / cancelled

class ClinicShiftNeed {
  final String id;
  final String clinicId; // ตอนนี้ถ้ายังไม่มีระบบคลินิก ให้ใส่ชื่อ/รหัสคลินิก
  final String clinicName;

  final String role; // เช่น "ผู้ช่วยทันตแพทย์"
  final String date; // yyyy-MM-dd
  final String start; // HH:mm
  final String end; // HH:mm

  final int requiredCount; // ต้องการกี่คน
  final String status; // open | filled | cancelled
  final String note;

  const ClinicShiftNeed({
    required this.id,
    required this.clinicId,
    required this.clinicName,
    required this.role,
    required this.date,
    required this.start,
    required this.end,
    this.requiredCount = 1,
    this.status = 'open',
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'clinicId': clinicId,
        'clinicName': clinicName,
        'role': role,
        'date': date,
        'start': start,
        'end': end,
        'requiredCount': requiredCount,
        'status': status,
        'note': note,
      };

  factory ClinicShiftNeed.fromMap(Map<String, dynamic> map) {
    return ClinicShiftNeed(
      id: (map['id'] ?? '').toString(),
      clinicId: (map['clinicId'] ?? '').toString(),
      clinicName: (map['clinicName'] ?? '').toString(),
      role: (map['role'] ?? 'ผู้ช่วย').toString(),
      date: (map['date'] ?? '').toString(),
      start: (map['start'] ?? '00:00').toString(),
      end: (map['end'] ?? '00:00').toString(),
      requiredCount: (map['requiredCount'] as num? ?? 1).toInt(),
      status: (map['status'] ?? 'open').toString(),
      note: (map['note'] ?? '').toString(),
    );
  }

  // ---------- time utils ----------
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
    return (int.tryParse(p[0]) ?? 0) == y && (int.tryParse(p[1]) ?? 0) == m;
  }

  ClinicShiftNeed copyWith({
    String? clinicId,
    String? clinicName,
    String? role,
    String? date,
    String? start,
    String? end,
    int? requiredCount,
    String? status,
    String? note,
  }) {
    return ClinicShiftNeed(
      id: id,
      clinicId: clinicId ?? this.clinicId,
      clinicName: clinicName ?? this.clinicName,
      role: role ?? this.role,
      date: date ?? this.date,
      start: start ?? this.start,
      end: end ?? this.end,
      requiredCount: requiredCount ?? this.requiredCount,
      status: status ?? this.status,
      note: note ?? this.note,
    );
  }
}
