// lib/screens/helper/helper_availability_detail_screen.dart
//
// ✅ Helper Availability Detail — FINAL CLEAN
// - PROD CLEAN (ไม่โชว์ debug / ไม่โชว์ id/clinicId/raw status)
// - โทรเลย / เปิด Google Maps / นำทางทันที / copy ได้
//
// ✅ STORE READY
// - รองรับ bookedClinicLocationLabel
// - รองรับ bookedClinicDistanceText / bookedClinicDistanceKm
// - แสดง "ห่างจากคุณ X กม."
// - fallback ดีเมื่อไม่มี distance จาก backend
// - ใช้ LocationEngine / LocationManager แบบเดียวกับทั้งแอป
//
// ✅ FINAL CLEANUP
// - ลบ import ที่ไม่ใช้
// - เช็กพิกัดให้แน่นขึ้น (กัน 0,0)
// - ใช้ Uri ตรง ๆ สำหรับ maps/nav
// - ✅ ไม่สร้าง AppLocation เองแล้ว เพื่อตัดปัญหา undefined
//
// ✅ NOTE
// - model ของท่าน clinicLat/clinicLng เป็น num? -> แปลงเป็น double? ด้วย toDouble()

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:clinic_smart_staff/models/availability_model.dart';
import 'package:clinic_smart_staff/services/location_engine.dart';
import 'package:clinic_smart_staff/services/location_manager.dart';

class HelperAvailabilityDetailScreen extends StatefulWidget {
  final Availability a;

  const HelperAvailabilityDetailScreen({
    super.key,
    required this.a,
  });

  @override
  State<HelperAvailabilityDetailScreen> createState() =>
      _HelperAvailabilityDetailScreenState();
}

class _HelperAvailabilityDetailScreenState
    extends State<HelperAvailabilityDetailScreen> {
  double? _fallbackDistanceKm;
  bool _loadingFallbackDistance = false;

  Availability get a => widget.a;

  String _s(String v) => v.trim().isEmpty ? '-' : v.trim();
  String _raw(dynamic v) => (v ?? '').toString().trim();

  bool get _isBooked => a.status.toLowerCase().trim() == 'booked';

  double? get _lat => a.clinicLat?.toDouble();
  double? get _lng => a.clinicLng?.toDouble();

  bool get _hasLocation {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return false;
    if (lat == 0 || lng == 0) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _prepareFallbackDistance();
  }

  double? _distanceKmBetweenRaw(
    double? lat1,
    double? lng1,
    double? lat2,
    double? lng2,
  ) {
    if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
      return null;
    }
    if (!lat1.isFinite || !lng1.isFinite || !lat2.isFinite || !lng2.isFinite) {
      return null;
    }
    if (lat1 == 0 || lng1 == 0 || lat2 == 0 || lng2 == 0) {
      return null;
    }
    if (lat1 < -90 || lat1 > 90 || lat2 < -90 || lat2 > 90) {
      return null;
    }
    if (lng1 < -180 || lng1 > 180 || lng2 < -180 || lng2 > 180) {
      return null;
    }

    const r = 6371.0;

    double degToRad(double deg) => deg * math.pi / 180.0;

    final dLat = degToRad(lat2 - lat1);
    final dLng = degToRad(lng2 - lng1);

    final aVal = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(degToRad(lat1)) *
            math.cos(degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));
    final km = r * c;

    if (!km.isFinite) return null;
    return km;
  }

  Future<void> _prepareFallbackDistance() async {
    if (!_isBooked) return;
    if (!_hasLocation) return;
    if (_clinicDistanceText.isNotEmpty) return;

    if (mounted) {
      setState(() => _loadingFallbackDistance = true);
    }

    try {
      final helperLoc =
          await LocationManager.loadHelperLocationSmart(allowGpsFallback: false);

      if (helperLoc == null) return;

      final lat = _lat;
      final lng = _lng;
      if (lat == null || lng == null) return;

      final km = _distanceKmBetweenRaw(
        helperLoc.lat,
        helperLoc.lng,
        lat,
        lng,
      );

      if (!mounted) return;
      setState(() {
        _fallbackDistanceKm = km;
      });
    } catch (_) {
      // เงียบไว้ หน้ายังใช้งานได้
    } finally {
      if (mounted) {
        setState(() => _loadingFallbackDistance = false);
      }
    }
  }

  Uri? _mapsUri() {
    if (!_hasLocation) return null;
    return Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${_lat!},${_lng!}',
    );
  }

  Uri? _navUri() {
    if (!_hasLocation) return null;
    return Uri.parse('google.navigation:q=${_lat!},${_lng!}');
  }

  Uri? _webDirUri() {
    if (!_hasLocation) return null;
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${_lat!},${_lng!}&travelmode=driving',
    );
  }

  Uri _telUri(String phone) {
    return Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}');
  }

  String get _clinicLocationLabel {
    final explicit = _raw(a.bookedClinicLocationLabel);
    if (explicit.isNotEmpty) return explicit;

    final fromModel = _raw(a.clinicLocationText);
    if (fromModel.isNotEmpty) return fromModel;

    return LocationEngine.resolveLocationLabelForItem({
      'locationLabel': a.bookedClinicLocationLabel,
      'district': a.bookedClinicDistrict,
      'province': a.bookedClinicProvince,
      'address': a.clinicAddress,
    });
  }

  String get _clinicDistanceText {
    final explicit = _raw(a.bookedClinicDistanceText);
    if (explicit.isNotEmpty) return explicit;

    final modelKm = a.bookedClinicDistanceKm?.toDouble();
    if (modelKm != null) {
      return LocationEngine.formatDistanceKm(modelKm);
    }

    if (_fallbackDistanceKm != null) {
      return LocationEngine.formatDistanceKm(_fallbackDistanceKm);
    }

    return '';
  }

  String get _clinicNearbyLabel {
    if (a.bookedClinicDistanceKm != null) {
      return LocationEngine.nearbyLabelFromDistance(
        a.bookedClinicDistanceKm!.toDouble(),
      );
    }

    if (_fallbackDistanceKm != null) {
      return LocationEngine.nearbyLabelFromDistance(_fallbackDistanceKm);
    }

    return '';
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(okMsg)),
    );
  }

  Future<void> _launchExternal(BuildContext context, Uri? uri) async {
    if (uri == null) return;

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
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
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
    final clinicNearbyLabel = _clinicNearbyLabel;

    final mapsUri = _mapsUri();
    final navUri = _navUri();
    final webDirUri = _webDirUri();

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
                    if (_loadingFallbackDistance) ...[
                      Text(
                        'กำลังคำนวณระยะทาง...',
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (clinicNearbyLabel.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill(clinicNearbyLabel, Colors.green),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                                _launchExternal(context, navUri),
                            icon: const Icon(Icons.navigation),
                            label: const Text('นำทาง'),
                          ),
                        if (_hasLocation)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _launchExternal(context, mapsUri),
                            icon: const Icon(Icons.map),
                            label: const Text('เปิดแผนที่'),
                          ),
                        if (_hasLocation)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _launchExternal(context, webDirUri),
                            icon: const Icon(Icons.directions),
                            label: const Text('เส้นทาง (สำรอง)'),
                          ),
                        if (clinicPhone.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => _copy(
                              context,
                              clinicPhone,
                              'คัดลอกเบอร์แล้ว',
                            ),
                            icon: const Icon(Icons.copy),
                            label: const Text('คัดลอกเบอร์'),
                          ),
                        if (clinicAddr.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => _copy(
                              context,
                              clinicAddr,
                              'คัดลอกที่อยู่แล้ว',
                            ),
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
          child: Text(
            k,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
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