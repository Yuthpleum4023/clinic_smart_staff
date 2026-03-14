// lib/screens/helper/helper_availability_detail_screen.dart
//
// ✅ Helper Availability Detail — PROD CLEAN + POWER ACTIONS (MODEL-MATCHED)
// - PROD CLEAN (ไม่โชว์ debug / ไม่โชว์ id/clinicId/raw status)
// - 🔥 โทรเลย
// - 🔥 เปิด Google Maps
// - 🔥 นำทางทันที (google.navigation)
// - Copy เบอร์/ที่อยู่ ได้
//
// ✅ PATCH NEW (STORE READY)
// - ✅ รองรับ bookedClinicLocationLabel
// - ✅ รองรับ bookedClinicDistanceText / bookedClinicDistanceKm
// - ✅ แสดง "ห่างจากคุณ X กม."
// - ✅ fallback ดีเมื่อไม่มี location/distance
//
// ✅ FIX RED:
// - model ของท่าน clinicLat/clinicLng เป็น num? -> แปลงเป็น double? ด้วย toDouble()

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:clinic_smart_staff/models/availability_model.dart';

class HelperAvailabilityDetailScreen extends StatelessWidget {
  final Availability a;
  const HelperAvailabilityDetailScreen({super.key, required this.a});

  String _s(String v) => v.trim().isEmpty ? '-' : v.trim();
  String _raw(dynamic v) => (v ?? '').toString().trim();

  bool get _isBooked => a.status.toLowerCase().trim() == 'booked';

  double? get _lat => a.clinicLat?.toDouble();
  double? get _lng => a.clinicLng?.toDouble();

  bool get _hasLocation => _lat != null && _lng != null;

  String _mapsUrl() {
    if (!_hasLocation) return '';
    return 'https://www.google.com/maps/search/?api=1&query=$_lat,$_lng';
  }

  Uri _navUri() {
    return Uri.parse('google.navigation:q=$_lat,$_lng');
  }

  Uri _webDirUri() {
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$_lat,$_lng&travelmode=driving',
    );
  }

  Uri _telUri(String phone) {
    return Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}');
  }

  String get _clinicLocationLabel {
    final v = _raw(a.bookedClinicLocationLabel);
    if (v.isNotEmpty) return v;

    final fromClinicAddress = _raw(a.clinicLocationText);
    if (fromClinicAddress.isNotEmpty) return fromClinicAddress;

    final district = _raw(a.bookedClinicDistrict);
    final province = _raw(a.bookedClinicProvince);
    if (district.isNotEmpty && province.isNotEmpty) return '$district, $province';
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;

    final clinicAddr = _raw(a.clinicAddress);
    if (clinicAddr.isNotEmpty) return clinicAddr;

    return '';
  }

  String get _clinicDistanceText {
    final t = _raw(a.bookedClinicDistanceText);
    if (t.isNotEmpty) return t;

    final km = a.bookedClinicDistanceKm;
    if (km == null) return '';

    final n = km.toDouble();
    if (n < 10) return '${n.toStringAsFixed(1)} กม.';
    return '${n.round()} กม.';
  }

  String get _clinicLocationDistanceLine {
    final loc = _clinicLocationLabel;
    final dist = _clinicDistanceText;

    if (loc.isNotEmpty && dist.isNotEmpty) {
      return '$loc • ห่างจากคุณ $dist';
    }
    if (dist.isNotEmpty) {
      return 'ห่างจากคุณ $dist';
    }
    if (loc.isNotEmpty) {
      return loc;
    }
    return '';
  }

  Future<void> _copy(BuildContext context, String text, String okMsg) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
  }

  Future<void> _launchExternal(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปิดไม่สำเร็จ')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิดไม่สำเร็จ')),
      );
    }
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final dateLine = '${_s(a.date)} • ${_s(a.start)}-${_s(a.end)}';

    final clinicName = _raw(a.clinicName);
    final clinicPhone = _raw(a.clinicPhone);
    final clinicAddr = _raw(a.clinicAddress);
    final clinicLocationDistanceLine = _clinicLocationDistanceLine;

    final maps = _mapsUrl();

    final hasClinicMeta = clinicName.isNotEmpty ||
        clinicPhone.isNotEmpty ||
        clinicAddr.isNotEmpty ||
        clinicLocationDistanceLine.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียดเวลาว่าง'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLine,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _pill(
                        _isBooked ? 'จองแล้ว' : 'ว่าง',
                        _isBooked ? Colors.green : cs.primary,
                      ),
                      if (a.role.trim().isNotEmpty)
                        _pill('ตำแหน่ง: ${_s(a.role)}', cs.secondary),
                      if (a.shiftId.trim().isNotEmpty)
                        _pill('สร้างกะงานแล้ว', Colors.green),
                    ],
                  ),
                  if (a.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('หมายเหตุของฉัน: ${_s(a.note)}'),
                  ],
                  if (a.bookedNote.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('หมายเหตุจากคลินิก: ${_s(a.bookedNote)}'),
                  ],
                  if (a.bookedHourlyRate > 0) ...[
                    const SizedBox(height: 10),
                    Text('เรทที่จองไว้: ${a.bookedHourlyRate} บาท/ชั่วโมง'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('ข้อมูลคลินิก'),
                  const SizedBox(height: 10),
                  if (!_isBooked)
                    Text(
                      'รายการนี้ยังไม่ได้ถูกจอง',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                    )
                  else if (!hasClinicMeta && !_hasLocation) ...[
                    Text(
                      'ยังไม่มีข้อมูลคลินิกแนบมา',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                    ),
                  ] else ...[
                    if (clinicName.isNotEmpty) ...[
                      _row('ชื่อ', clinicName),
                      const SizedBox(height: 6),
                    ],
                    if (clinicLocationDistanceLine.isNotEmpty) ...[
                      _row('ตำแหน่ง', clinicLocationDistanceLine),
                      const SizedBox(height: 6),
                    ],
                    if (clinicPhone.isNotEmpty) ...[
                      _row('โทร', clinicPhone),
                      const SizedBox(height: 6),
                    ],
                    if (clinicAddr.isNotEmpty) ...[
                      _row('ที่อยู่', clinicAddr),
                      const SizedBox(height: 6),
                    ],
                    if (_hasLocation) ...[
                      _row('แผนที่', 'พร้อมใช้งาน'),
                      const SizedBox(height: 6),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (clinicPhone.isNotEmpty)
                          FilledButton.icon(
                            onPressed: () =>
                                _launchExternal(context, _telUri(clinicPhone)),
                            icon: const Icon(Icons.call),
                            label: const Text('โทรเลย'),
                          ),
                        if (_hasLocation)
                          FilledButton.icon(
                            onPressed: () =>
                                _launchExternal(context, _navUri()),
                            icon: const Icon(Icons.navigation),
                            label: const Text('นำทาง'),
                          ),
                        if (_hasLocation)
                          OutlinedButton.icon(
                            onPressed: () => _launchExternal(
                              context,
                              Uri.parse(maps),
                            ),
                            icon: const Icon(Icons.map),
                            label: const Text('เปิดแผนที่'),
                          ),
                        if (_hasLocation)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _launchExternal(context, _webDirUri()),
                            icon: const Icon(Icons.directions),
                            label: const Text('เส้นทาง (สำรอง)'),
                          ),
                        if (clinicPhone.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _copy(context, clinicPhone, 'คัดลอกเบอร์แล้ว'),
                            icon: const Icon(Icons.copy),
                            label: const Text('คัดลอกเบอร์'),
                          ),
                        if (clinicAddr.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _copy(context, clinicAddr, 'คัดลอกที่อยู่แล้ว'),
                            icon: const Icon(Icons.copy),
                            label: const Text('คัดลอกที่อยู่'),
                          ),
                      ],
                    ),
                    if (_hasLocation) ...[
                      const SizedBox(height: 10),
                      Text(
                        'ถ้าปุ่ม “นำทาง” เปิดไม่ได้ ให้ลอง “เปิดแผนที่” หรือ “เส้นทาง (สำรอง)”',
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(_s(v))),
      ],
    );
  }

  Widget _pill(String text, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: c,
          fontSize: 12,
        ),
      ),
    );
  }
}