// lib/models/availability_model.dart
//
// ✅ Availability model (robust + booking-safe + clinic-contact ready)
// - รองรับ key หลายชื่อ
// - ไม่เอา userId มาแทน staffId
// - ✅ role
// - ✅ bookedNote / shiftId / bookedHourlyRate
// - ✅ bookedByClinicId + clinic contact
// - ✅ NEW: helper location snapshot
// - ✅ NEW: distance for clinic-side list
// - ✅ NEW: nearbyLabel / isNearby
// - ✅ NEW: booked clinic location + distance for helper-side detail
// - ✅ มีทั้ง fromMap และ fromJson
//

class Availability {
  final String id;

  final String staffId; // ผู้ช่วย
  final String userId; // user ของผู้ช่วย (optional)
  final String clinicId; // อาจว่าง (บางระบบไม่ใช้)

  final String fullName;
  final String phone;

  final String role;

  final String date;
  final String start;
  final String end;

  final String note;
  final String status;

  // ✅ helper location snapshot
  final num? lat;
  final num? lng;
  final String district;
  final String province;
  final String address;
  final String locationLabel;

  // ✅ clinic-side distance
  final num? distanceKm;
  final String distanceText;

  // ✅ NEW: nearby
  final bool isNearby;
  final String nearbyLabel;

  // ✅ BOOKING
  final String bookedNote;
  final String shiftId;
  final num bookedHourlyRate;

  // ✅ who booked
  final String bookedByClinicId;

  // ✅ clinic contact
  final String clinicName;
  final String clinicPhone;
  final String clinicAddress;
  final num? clinicLat;
  final num? clinicLng;

  // ✅ booked clinic location + distance
  final String bookedClinicDistrict;
  final String bookedClinicProvince;
  final String bookedClinicLocationLabel;
  final num? bookedClinicDistanceKm;
  final String bookedClinicDistanceText;

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
    required this.lat,
    required this.lng,
    required this.district,
    required this.province,
    required this.address,
    required this.locationLabel,
    required this.distanceKm,
    required this.distanceText,
    required this.isNearby,
    required this.nearbyLabel,
    required this.bookedNote,
    required this.shiftId,
    required this.bookedHourlyRate,
    required this.bookedByClinicId,
    required this.clinicName,
    required this.clinicPhone,
    required this.clinicAddress,
    required this.clinicLat,
    required this.clinicLng,
    required this.bookedClinicDistrict,
    required this.bookedClinicProvince,
    required this.bookedClinicLocationLabel,
    required this.bookedClinicDistanceKm,
    required this.bookedClinicDistanceText,
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

  static bool _b(dynamic v) {
    if (v is bool) return v;
    final s = _s(v).toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  static String _buildLocationLabel({
    dynamic district,
    dynamic province,
    dynamic address,
    dynamic fallback,
  }) {
    final d = _s(district);
    final p = _s(province);
    final a = _s(address);
    final f = _s(fallback);

    if (f.isNotEmpty) return f;
    if (d.isNotEmpty && p.isNotEmpty) return '$d, $p';
    if (p.isNotEmpty) return p;
    if (d.isNotEmpty) return d;
    if (a.isNotEmpty) return a;
    return '';
  }

  factory Availability.fromMap(Map<String, dynamic> m) =>
      Availability.fromJson(m);

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

    // ✅ helper location snapshot
    final lat = _nNull(m['lat'] ?? m['helperLat']);
    final lng = _nNull(m['lng'] ?? m['helperLng']);
    final district = _s(m['district'] ?? m['helperDistrict']);
    final province = _s(m['province'] ?? m['helperProvince']);
    final address = _s(m['address'] ?? m['helperAddress']);
    final locationLabel = _buildLocationLabel(
      district: district,
      province: province,
      address: address,
      fallback: m['locationLabel'],
    );

    // ✅ clinic-side distance
    final distanceKm = _nNull(m['distanceKm']);
    final distanceText = _s(m['distanceText']);

    // ✅ NEW: nearby
    final isNearby = _b(m['isNearby']);
    final nearbyLabel = _s(m['nearbyLabel']);

    // ✅ BOOKING FIELDS
    final bookedNote = _s(m['bookedNote'] ?? m['bookingNote']);
    final shiftId = _s(m['shiftId'] ?? m['shift_id']);
    final bookedHourlyRate = _n0(m['bookedHourlyRate'] ?? m['hourlyRate']);

    // ✅ who booked
    final bookedByClinicId =
        _s(m['bookedByClinicId'] ?? m['bookedClinicId'] ?? m['clinicBookedBy']);

    // ✅ clinic contact
    final clinicName = _s(m['clinicName'] ?? m['bookedClinicName']);
    final clinicPhone = _s(m['clinicPhone'] ?? m['bookedClinicPhone']);
    final clinicAddress = _s(m['clinicAddress'] ?? m['bookedClinicAddress']);
    final clinicLat = _nNull(m['clinicLat'] ?? m['bookedClinicLat']);
    final clinicLng = _nNull(m['clinicLng'] ?? m['bookedClinicLng']);

    // ✅ booked clinic location + distance
    final bookedClinicDistrict =
        _s(m['bookedClinicDistrict'] ?? m['clinicDistrict']);
    final bookedClinicProvince =
        _s(m['bookedClinicProvince'] ?? m['clinicProvince']);
    final bookedClinicLocationLabel = _buildLocationLabel(
      district: bookedClinicDistrict,
      province: bookedClinicProvince,
      address: clinicAddress,
      fallback: m['bookedClinicLocationLabel'] ?? m['clinicLocationLabel'],
    );
    final bookedClinicDistanceKm =
        _nNull(m['bookedClinicDistanceKm'] ?? m['clinicDistanceKm']);
    final bookedClinicDistanceText =
        _s(m['bookedClinicDistanceText'] ?? m['clinicDistanceText']);

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
      lat: lat,
      lng: lng,
      district: district,
      province: province,
      address: address,
      locationLabel: locationLabel,
      distanceKm: distanceKm,
      distanceText: distanceText,
      isNearby: isNearby,
      nearbyLabel: nearbyLabel,
      bookedNote: bookedNote,
      shiftId: shiftId,
      bookedHourlyRate: bookedHourlyRate,
      bookedByClinicId: bookedByClinicId,
      clinicName: clinicName,
      clinicPhone: clinicPhone,
      clinicAddress: clinicAddress,
      clinicLat: clinicLat,
      clinicLng: clinicLng,
      bookedClinicDistrict: bookedClinicDistrict,
      bookedClinicProvince: bookedClinicProvince,
      bookedClinicLocationLabel: bookedClinicLocationLabel,
      bookedClinicDistanceKm: bookedClinicDistanceKm,
      bookedClinicDistanceText: bookedClinicDistanceText,
      raw: Map<String, dynamic>.from(m),
    );
  }

  bool get isBooked => status.toLowerCase().trim() == 'booked';

  bool get isOpen =>
      status.toLowerCase().trim().isEmpty ||
      status.toLowerCase().trim() == 'open';

  bool get isCancelled => status.toLowerCase().trim() == 'cancelled';

  bool get hasHelperLocation =>
      locationLabel.isNotEmpty ||
      district.isNotEmpty ||
      province.isNotEmpty ||
      address.isNotEmpty ||
      lat != null ||
      lng != null;

  bool get hasClinicDistance =>
      bookedClinicDistanceText.isNotEmpty || bookedClinicDistanceKm != null;

  String get helperLocationText {
    if (locationLabel.isNotEmpty) return locationLabel;
    if (district.isNotEmpty && province.isNotEmpty) {
      return '$district, $province';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;
    if (address.isNotEmpty) return address;
    return '';
  }

  String get clinicLocationText {
    if (bookedClinicLocationLabel.isNotEmpty) return bookedClinicLocationLabel;
    if (clinicAddress.isNotEmpty) return clinicAddress;
    return '';
  }

  Map<String, dynamic> toCreatePayload() {
    return <String, dynamic>{
      'date': date,
      'start': start,
      'end': end,
      'note': note,
      if (role.trim().isNotEmpty) 'role': role,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (district.trim().isNotEmpty) 'district': district,
      if (province.trim().isNotEmpty) 'province': province,
      if (address.trim().isNotEmpty) 'address': address,
      if (locationLabel.trim().isNotEmpty) 'locationLabel': locationLabel,
    };
  }
}