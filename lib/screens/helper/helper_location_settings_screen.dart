// lib/screens/helper/helper_location_settings_screen.dart
//
// ✅ FULL FILE — HelperLocationSettingsScreen
// ผู้ช่วยตั้งพิกัดของตัวเอง
//
// FEATURES
// - เลือกตำแหน่งบนแผนที่
// - ลากหมุดปรับละเอียด
// - โหลด "ตำแหน่งปัจจุบัน" จาก GPS ถ้ายังไม่เคยบันทึก
// - ปุ่มไปตำแหน่งปัจจุบัน
// - ✅ Reverse geocoding อัตโนมัติจาก lat/lng
// - ✅ เติม district / province / address / label อัตโนมัติ
// - บันทึกลงเครื่อง
// - บันทึก + sync backend
//
// BACKEND
// PATCH /users/me/location
//

import 'dart:convert';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:clinic_smart_staff/services/auth_storage.dart';
import 'package:clinic_smart_staff/services/settings_service.dart';
import 'package:clinic_smart_staff/api/api_config.dart';

class HelperLocationSettingsScreen extends StatefulWidget {
  const HelperLocationSettingsScreen({super.key});

  @override
  State<HelperLocationSettingsScreen> createState() =>
      _HelperLocationSettingsScreenState();
}

class _HelperLocationSettingsScreenState
    extends State<HelperLocationSettingsScreen> {
  final MapController _map = MapController();

  // ✅ default ไว้เป็น fallback สุดท้ายเท่านั้น
  LatLng _center = const LatLng(13.7563, 100.5018);
  LatLng? _picked;

  bool _loading = true;
  bool _saving = false;

  // ✅ reverse geocoding state
  bool _resolvingAddress = false;
  String _district = '';
  String _province = '';
  String _address = '';
  String _label = '';
  String _geoError = '';
  int _resolveSeq = 0;

  final String _syncPath = "/users/me/location";

  // ✅ เปลี่ยนจาก clinic_payroll ให้ตรงแอปใหม่
  static const String _uaPackageName = 'com.clinicsmartstaff.app';

  static const Duration _geoTimeout = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      // 1) ถ้ามีพิกัดที่เคยบันทึกไว้ ใช้อันนั้นก่อน
      final saved = await SettingService.loadHelperLocation();

      if (saved != null) {
        final ll = LatLng(saved.lat, saved.lng);
        _center = ll;
        _picked = ll;

        _district = saved.district.trim();
        _province = saved.province.trim();
        _address = saved.address.trim();
        _label = saved.label.trim();

        // ถ้าข้อมูลข้อความยังว่าง ค่อย reverse ใหม่
        if (_district.isEmpty &&
            _province.isEmpty &&
            _address.isEmpty &&
            _label.isEmpty) {
          await _resolveLocationText(ll);
        }
      } else {
        // 2) ถ้ายังไม่มี -> ใช้ GPS ปัจจุบัน
        final current = await _getCurrentLocationLatLng();
        if (current != null) {
          _center = current;
          _picked = current;
          await _resolveLocationText(current);
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  Future<LatLng?> _getCurrentLocationLatLng() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  String _pickFirstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _buildLabel({
    required String district,
    required String province,
    required String address,
  }) {
    if (district.isNotEmpty && province.isNotEmpty) {
      return '$district, $province';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;
    if (address.isNotEmpty) return address;
    return '';
  }

  Future<void> _resolveLocationText(LatLng ll) async {
    final seq = ++_resolveSeq;

    if (mounted) {
      setState(() {
        _resolvingAddress = true;
        _geoError = '';
      });
    }

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2'
        '&lat=${ll.latitude}'
        '&lon=${ll.longitude}'
        '&zoom=18'
        '&addressdetails=1',
      );

      final res = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': '$_uaPackageName/1.0',
        },
      ).timeout(_geoTimeout);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('reverse geocoding failed (${res.statusCode})');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) {
        throw Exception('invalid reverse geocoding response');
      }

      final addressMap = decoded['address'] is Map
          ? Map<String, dynamic>.from(decoded['address'])
          : <String, dynamic>{};

      final district = _pickFirstNonEmpty([
        addressMap['city_district'],
        addressMap['suburb'],
        addressMap['town'],
        addressMap['city'],
        addressMap['municipality'],
        addressMap['county'],
        addressMap['state_district'],
      ]);

      final province = _pickFirstNonEmpty([
        addressMap['state'],
        addressMap['province'],
        addressMap['region'],
      ]);

      final address = (decoded['display_name'] ?? '').toString().trim();

      final label = _buildLabel(
        district: district,
        province: province,
        address: address,
      );

      if (!mounted || seq != _resolveSeq) return;

      setState(() {
        _district = district;
        _province = province;
        _address = address;
        _label = label;
        _geoError = '';
        _resolvingAddress = false;
      });
    } catch (e) {
      if (!mounted || seq != _resolveSeq) return;

      setState(() {
        _geoError = e.toString();
        _resolvingAddress = false;
      });
    }
  }

  AppLocation _currentLocation() {
    final p = _picked ?? _center;
    return AppLocation(
      lat: p.latitude,
      lng: p.longitude,
      district: _district,
      province: _province,
      address: _address,
      label: _label,
    );
  }

  void _onTapMap(TapPosition _, LatLng latlng) {
    setState(() => _picked = latlng);
    HapticFeedback.selectionClick();
    _resolveLocationText(latlng);
  }

  Future<void> _goToCurrentLocation() async {
    final ll = await _getCurrentLocationLatLng();

    if (ll == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถดึงตำแหน่งปัจจุบันได้ กรุณาเปิด GPS และอนุญาตสิทธิ์'),
        ),
      );
      return;
    }

    setState(() {
      _center = ll;
      _picked = ll;
    });

    try {
      _map.move(ll, 17);
    } catch (_) {}

    await _resolveLocationText(ll);
  }

  Future<void> _saveLocalOnly() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final loc = _currentLocation();

      await SettingService.saveHelperLocation(
        lat: loc.lat,
        lng: loc.lng,
        district: loc.district,
        province: loc.province,
        address: loc.address,
        label: loc.label,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("บันทึกพิกัดลงเครื่องแล้ว ✅")),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("บันทึกไม่สำเร็จ: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndSync() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final token = await AuthStorage.getToken();

      if (token == null || token.trim().isEmpty) {
        throw "missing token (กรุณา login ใหม่)";
      }

      final loc = _currentLocation();

      await SettingService.saveHelperLocation(
        lat: loc.lat,
        lng: loc.lng,
        district: loc.district,
        province: loc.province,
        address: loc.address,
        label: loc.label,
      );

      final res = await SettingService.syncHelperLocationToBackend(
        baseUrl: ApiConfig.authBaseUrl,
        token: token,
        location: loc,
        path: _syncPath,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("บันทึก + ส่งพิกัดขึ้นระบบแล้ว ✅")),
        );

        return;
      }

      String msg = "sync failed (${res.statusCode})";

      try {
        final j = jsonDecode(res.body);

        if (j is Map && j["message"] != null) {
          msg = j["message"].toString();
        }

        if (j is Map && j["error"] != null) {
          msg = j["error"].toString();
        }
      } catch (_) {}

      throw msg;
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("ส่งพิกัดไม่สำเร็จ: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildLocationInfo(BuildContext context, LatLng picked) {
    final theme = Theme.of(context);

    final labelText = _label.trim().isNotEmpty ? _label.trim() : '-';
    final addressText = _address.trim().isNotEmpty ? _address.trim() : '-';
    final districtText = _district.trim().isNotEmpty ? _district.trim() : '-';
    final provinceText = _province.trim().isNotEmpty ? _province.trim() : '-';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ตำแหน่งที่ระบบอ่านได้",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 8),
          Text("label: $labelText"),
          const SizedBox(height: 4),
          Text("อำเภอ/เขต: $districtText"),
          const SizedBox(height: 4),
          Text("จังหวัด: $provinceText"),
          const SizedBox(height: 4),
          Text("ที่อยู่: $addressText"),
          const SizedBox(height: 8),
          Text(
            "lat: ${picked.latitude.toStringAsFixed(6)}   lng: ${picked.longitude.toStringAsFixed(6)}",
          ),
          if (_resolvingAddress) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            const Text("กำลังค้นหาชื่อพื้นที่จากพิกัด..."),
          ],
          if (!_resolvingAddress && _geoError.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "หมายเหตุ: อ่านชื่อพื้นที่ไม่สำเร็จ ระบบจะยังบันทึกพิกัดได้",
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange[800],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked ?? _center;

    return Scaffold(
      appBar: AppBar(
        title: const Text("ตั้งพิกัดของฉัน"),
        actions: [
          IconButton(
            tooltip: 'ไปตำแหน่งปัจจุบัน',
            onPressed: _saving ? null : _goToCurrentLocation,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: picked,
                      initialZoom: 16,
                      onTap: _onTapMap,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                        userAgentPackageName: _uaPackageName,
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: picked,
                            width: 64,
                            height: 64,
                            child: _DraggablePin(
                              map: _map,
                              getLatLng: () => _picked ?? _center,
                              onDragged: (newLatLng) {
                                setState(() => _picked = newLatLng);
                              },
                              onDragEnd: (newLatLng) {
                                _resolveLocationText(newLatLng);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 12,
                        offset: Offset(0, -2),
                        color: Color(0x22000000),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "พิกัดของฉัน",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      _buildLocationInfo(context, picked),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _saveLocalOnly,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text("บันทึกลงเครื่อง"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _saveAndSync,
                              icon: const Icon(Icons.cloud_upload_outlined),
                              label: const Text("บันทึก + ส่งระบบ"),
                            ),
                          ),
                        ],
                      ),
                      if (_saving) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        "ทิป: แตะบนแผนที่เพื่อเลือกจุด • ลากหมุดเพื่อปรับละเอียด",
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _DraggablePin extends StatefulWidget {
  final LatLng Function() getLatLng;
  final MapController map;
  final void Function(LatLng newLatLng) onDragged;
  final void Function(LatLng newLatLng)? onDragEnd;

  const _DraggablePin({
    required this.getLatLng,
    required this.map,
    required this.onDragged,
    this.onDragEnd,
  });

  @override
  State<_DraggablePin> createState() => _DraggablePinState();
}

class _DraggablePinState extends State<_DraggablePin> {
  Offset? _lastGlobal;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) {
        _lastGlobal = d.globalPosition;
        setState(() => _dragging = true);
        HapticFeedback.selectionClick();
      },
      onPanUpdate: (d) {
        if (_lastGlobal == null) return;

        final delta = d.globalPosition - _lastGlobal!;
        _lastGlobal = d.globalPosition;

        final latlng = widget.getLatLng();
        final px = widget.map.camera.project(latlng);

        final nextPx = Point<double>(px.x + delta.dx, px.y + delta.dy);
        final nextLatLng = widget.map.camera.unproject(nextPx);

        widget.onDragged(nextLatLng);
      },
      onPanEnd: (_) {
        setState(() => _dragging = false);
        HapticFeedback.lightImpact();
        final latlng = widget.getLatLng();
        widget.onDragEnd?.call(latlng);
      },
      child: AnimatedScale(
        scale: _dragging ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: const Icon(
          Icons.location_pin,
          size: 48,
          color: Colors.red,
        ),
      ),
    );
  }
}