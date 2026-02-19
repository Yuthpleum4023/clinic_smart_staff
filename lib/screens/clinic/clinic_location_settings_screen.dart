//
// lib/screens/clinic/clinic_location_settings_screen.dart
//
// ✅ FULL FILE (clinic_smart_staff) — OSM 403 FIXED + SAFE DRAG PIN
// - ใช้ flutter_map + OSM tiles
// - แตะเลือกจุด / ลากหมุดปรับละเอียด
// - บันทึกลงเครื่อง: SettingService.saveClinicLocation()
// - บันทึก + ส่งระบบ: SettingService.syncClinicLocationToBackend()
//   -> baseUrl: ApiConfig.authBaseUrl (ตามของท่าน)
//   -> path: /users/me/location (ตามของท่าน)
//
// REQUIRE PACKAGES:
//   flutter_map: ^6.x หรือ ^7.x
//   latlong2: ^0.9.x
//

import 'dart:convert';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';
import 'package:clinic_smart_staff/services/settings_service.dart';

class ClinicLocationSettingsScreen extends StatefulWidget {
  const ClinicLocationSettingsScreen({super.key});

  @override
  State<ClinicLocationSettingsScreen> createState() =>
      _ClinicLocationSettingsScreenState();
}

class _ClinicLocationSettingsScreenState
    extends State<ClinicLocationSettingsScreen> {
  final MapController _map = MapController();

  LatLng _center = const LatLng(13.7563, 100.5018); // default Bangkok
  LatLng? _picked;

  bool _loading = true;
  bool _saving = false;

  // ✅ ของท่าน: sync ไป user_service ผ่าน /users/me/location
  final String _syncPath = "/users/me/location";

  // ✅✅✅ IMPORTANT — applicationId จริงของท่านจาก build.gradle.kts
  // ตอนนี้ของท่านคือ com.example.clinic_payroll
  static const String _uaPackageName = 'com.example.clinic_payroll';

  // (optional) ใส่ contact ตาม policy OSM (ถ้า headers ใช้ไม่ได้ไม่เป็นไร)
  static const String _uaString =
      'clinic_smart_staff/1.0 (contact: support@yourdomain.com)';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final saved = await SettingService.loadClinicLocation();
      if (saved != null) {
        final ll = LatLng(saved.lat, saved.lng);
        _center = ll;
        _picked = ll;
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  ClinicLocation _currentLocation() {
    final p = _picked ?? _center;
    return ClinicLocation(lat: p.latitude, lng: p.longitude);
  }

  void _onTapMap(TapPosition _, LatLng latlng) {
    setState(() => _picked = latlng);
    HapticFeedback.selectionClick();
  }

  Future<void> _saveLocalOnly() async {
    if (_saving) return;

    setState(() => _saving = true);
    try {
      final loc = _currentLocation();
      await SettingService.saveClinicLocation(lat: loc.lat, lng: loc.lng);

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
        throw "missing token (กรุณา logout/login ใหม่)";
      }

      final loc = _currentLocation();

      // 1) save local
      await SettingService.saveClinicLocation(lat: loc.lat, lng: loc.lng);

      // 2) sync backend
      final res = await SettingService.syncClinicLocationToBackend(
        baseUrl: ApiConfig.authBaseUrl, // ✅ ของท่าน: ยิงไป auth/user service
        token: token,
        location: loc,
        path: _syncPath, // ✅ /users/me/location
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
        if (j is Map && j["message"] != null) msg = j["message"].toString();
        if (j is Map && j["error"] != null) msg = j["error"].toString();
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

  @override
  Widget build(BuildContext context) {
    final picked = _picked ?? _center;

    return Scaffold(
      appBar: AppBar(
        title: const Text("ตั้งพิกัดคลินิก"),
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

                        // ✅ FIX OSM 403
                        userAgentPackageName: _uaPackageName,

                        // ✅ optional: บางเวอร์ชันรองรับ headers ถ้าแดงให้คอมเมนต์ทิ้งได้
                        // headers: const {
                        //   'User-Agent': _uaString,
                        // },
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
                        "พิกัดที่เลือก",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "lat: ${picked.latitude.toStringAsFixed(6)}   "
                        "lng: ${picked.longitude.toStringAsFixed(6)}",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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

  const _DraggablePin({
    required this.getLatLng,
    required this.map,
    required this.onDragged,
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

        // ✅ ใช้ Point<double> กันแดงเรื่อง CustomPoint
        final nextPx = Point<double>(px.x + delta.dx, px.y + delta.dy);
        final nextLatLng = widget.map.camera.unproject(nextPx);

        widget.onDragged(nextLatLng);
      },
      onPanEnd: (_) {
        setState(() => _dragging = false);
        HapticFeedback.lightImpact();
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
