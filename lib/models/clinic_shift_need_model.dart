// lib/models/clinic_shift_need_model.dart
//
// ClinicShiftNeed: คลินิกเปิดความต้องการผู้ช่วย (shift need)
// - date: yyyy-MM-dd
// - start/end: HH:mm
// - role: เช่น "ผู้ช่วยทันตแพทย์"
// - requiredCount: จำนวนที่ต้องการ
// - status: open / filled / cancelled
//
// ✅ FIX สำคัญ:
// - backend (Mongo) มักส่ง id เป็น "_id" ไม่ใช่ "id"
// - บางที่อาจส่ง "needId"
// => ทำให้ id ว่าง แล้วเปิดรายชื่อผู้สมัครไม่ได้ (needId ว่าง)
// => เลยต้อง resolve id ให้ robust

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

  // =========================
  // Helpers
  // =========================
  static String _s(dynamic v, {String def = ''}) {
    final x = (v ?? def).toString().trim();
    if (x.isEmpty || x == 'null') return def;
    return x;
  }

  static int _i(dynamic v, {int def = 0}) {
    if (v == null) return def;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? def;
  }

  /// ✅ id resolver: รองรับ id/_id/needId
  static String _pickId(Map<String, dynamic> map) {
    return _s(
      map['_id'] ?? map['id'] ?? map['needId'],
      def: '',
    );
  }

  Map<String, dynamic> toMap() => {
        // ✅ เวลา create/update มักส่งเป็น field ชื่อ id ได้
        // (backend จะ map เป็น _id เองตอน save)
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
    final id = _pickId(map);

    return ClinicShiftNeed(
      // ✅ FIX: รับ _id ด้วย
      id: id,
      clinicId: _s(map['clinicId']),
      clinicName: _s(map['clinicName']),
      role: _s(map['role'], def: 'ผู้ช่วย'),
      date: _s(map['date']),
      start: _s(map['start'], def: '00:00'),
      end: _s(map['end'], def: '00:00'),
      requiredCount: _i(map['requiredCount'], def: 1),
      status: _s(map['status'], def: 'open'),
      note: _s(map['note']),
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
