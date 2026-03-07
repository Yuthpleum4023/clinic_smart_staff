// lib/models/availability_model.dart
//
// ✅ Availability model (robust + booking-safe + clinic-contact ready)
// - รองรับ key หลายชื่อ
// - ไม่เอา userId มาแทน staffId
// - ✅ role
// - ✅ NEW: bookedNote / shiftId / bookedHourlyRate
// - ✅ NEW: bookedByClinicId + clinic contact (for helper to see who booked)
// - ✅ มีทั้ง fromMap และ fromJson (กันไฟล์อื่นแดง)
//

class Availability {
  final String id;

  final String staffId;   // ผู้ช่วย
  final String userId;    // user ของผู้ช่วย (optional)
  final String clinicId;  // อาจว่าง (บางระบบไม่ใช้)

  final String fullName;
  final String phone;

  final String role;

  final String date;
  final String start;
  final String end;

  final String note;
  final String status;

  // ✅ BOOKING
  final String bookedNote;
  final String shiftId;
  final num bookedHourlyRate;

  // ✅ NEW: who booked (clinicId from booking)
  final String bookedByClinicId;

  // ✅ NEW: clinic contact (optional; backend may enrich)
  final String clinicName;
  final String clinicPhone;
  final String clinicAddress;
  final num? clinicLat;
  final num? clinicLng;

  final Map<String, dynamic> raw;

  Availability({
    required this.id,
    required this.staffId,
    required this.userId,
    required this.clinicId,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.date,
    required this.start,
    required this.end,
    required this.note,
    required this.status,
    required this.bookedNote,
    required this.shiftId,
    required this.bookedHourlyRate,
    required this.bookedByClinicId,
    required this.clinicName,
    required this.clinicPhone,
    required this.clinicAddress,
    required this.clinicLat,
    required this.clinicLng,
    required this.raw,
  });

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static num _n0(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  static num? _nNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    final t = v.toString().trim();
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  // ✅ ใช้ได้ทั้งเดิมและใหม่
  factory Availability.fromMap(Map<String, dynamic> m) => Availability.fromJson(m);

  factory Availability.fromJson(Map<String, dynamic> m) {
    final id = _s(m['_id'] ?? m['id']);

    // ✅ staffId strict (ห้ามเอา userId มาแทน)
    final staffId = _s(m['staffId'] ?? m['assistantId']);

    final userId = _s(m['userId'] ?? m['user_id']);
    final clinicId = _s(m['clinicId'] ?? m['clinic_id']);

    final fullName = _s(m['fullName'] ?? m['name'] ?? m['staffName']);
    final phone = _s(m['phone'] ?? m['tel']);

    final role = _s(m['role'] ?? m['position'] ?? m['job'] ?? m['title']);

    final date = _s(m['date'] ?? m['day'] ?? m['workDate']);
    final start = _s(m['start'] ?? m['from'] ?? m['startTime']);
    final end = _s(m['end'] ?? m['to'] ?? m['endTime']);

    final note = _s(m['note'] ?? m['remark'] ?? m['comment']);
    final status = _s(m['status'] ?? m['state'] ?? 'open');

    // ✅ BOOKING FIELDS
    final bookedNote = _s(m['bookedNote'] ?? m['bookingNote']);
    final shiftId = _s(m['shiftId'] ?? m['shift_id']);
    final bookedHourlyRate = _n0(m['bookedHourlyRate'] ?? m['hourlyRate']);

    // ✅ who booked
    final bookedByClinicId = _s(m['bookedByClinicId'] ?? m['bookedClinicId'] ?? m['clinicBookedBy']);

    // ✅ clinic contact (backend may attach)
    // รองรับทั้ง key แบบ availability และแบบ shift
    final clinicName = _s(m['clinicName'] ?? m['bookedClinicName']);
    final clinicPhone = _s(m['clinicPhone'] ?? m['bookedClinicPhone']);
    final clinicAddress = _s(m['clinicAddress'] ?? m['bookedClinicAddress']);
    final clinicLat = _nNull(m['clinicLat'] ?? m['bookedClinicLat']);
    final clinicLng = _nNull(m['clinicLng'] ?? m['bookedClinicLng']);

    return Availability(
      id: id,
      staffId: staffId,
      userId: userId,
      clinicId: clinicId,
      fullName: fullName,
      phone: phone,
      role: role,
      date: date,
      start: start,
      end: end,
      note: note,
      status: status,
      bookedNote: bookedNote,
      shiftId: shiftId,
      bookedHourlyRate: bookedHourlyRate,
      bookedByClinicId: bookedByClinicId,
      clinicName: clinicName,
      clinicPhone: clinicPhone,
      clinicAddress: clinicAddress,
      clinicLat: clinicLat,
      clinicLng: clinicLng,
      raw: Map<String, dynamic>.from(m),
    );
  }

  bool get isBooked => status.toLowerCase().trim() == 'booked';

  Map<String, dynamic> toCreatePayload() {
    return <String, dynamic>{
      'date': date,
      'start': start,
      'end': end,
      'note': note,
      // 'role': role, // เปิดถ้า backend ต้องใช้
    };
  }
}