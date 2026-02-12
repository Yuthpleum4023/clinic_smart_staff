// lib/models/user_location_model.dart
//
// ตำแหน่งผู้ใช้ (แบบไม่ใช้ GPS)
// ใช้ได้ทั้ง "คลินิก" และ "ผู้ช่วย"

class UserLocation {
  final String label; // เช่น "สาขาอโศก", "คลินิกหลัก", "โซนบางนา"
  final String address; // รายละเอียดเพิ่มเติม (ไม่บังคับ)

  const UserLocation({
    required this.label,
    this.address = '',
  });

  Map<String, dynamic> toMap() => {
        'label': label,
        'address': address,
      };

  factory UserLocation.fromMap(Map<String, dynamic> map) {
    return UserLocation(
      label: (map['label'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
    );
  }

  bool get isValid => label.trim().isNotEmpty;

  @override
  String toString() {
    final l = label.trim();
    final a = address.trim();
    if (a.isEmpty) return l;
    return '$l • $a';
  }
}
