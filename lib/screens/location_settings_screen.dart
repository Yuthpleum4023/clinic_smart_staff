//
// lib/screens/location_settings_screen.dart
//
// ✅ FULL FILE (OSM 403 FIXED + PRODUCTION SAFE)
// - FIX: OpenStreetMap 403 "Access blocked"
// - ✅ ใส่ userAgentPackageName = applicationId จริง
// - ✅ ไม่มี type ซ้ำ ClinicLocation
// - ✅ Save local + Sync backend
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

class LocationSettingsScreen extends StatefulWidget {
  const LocationSettingsScreen({super.key});

  @override
  State<LocationSettingsScreen> createState() => _LocationSettingsScreenState();
}

class _LocationSettingsScreenState extends State<LocationSettingsScreen> {
  final MapController _map = MapController();

  LatLng _center = const LatLng(13.7563, 100.5018); // Bangkok default
  LatLng? _picked;

  bool _loading = true;
  bool _saving = false;

  static const String _syncPath = "/clinics/me/location";

  // ✅✅✅ IMPORTANT — applicationId จริงจาก build.gradle.kts
  static const String _uaPackageName = 'com.example.clinic_payroll';

  // (optional แต่ดีต่อ policy)
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

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  // ✅ ใช้ ClinicLocation จาก SettingService เท่านั้น
  ClinicLocation _currentLoc() {
    final p = _picked ?? _center;
    return ClinicLocation(lat: p.latitude, lng: p.longitude);
  }

  // ============================================================
  // ✅ SAVE LOCAL
  // ============================================================
  Future<void> _saveLocal() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final loc = _currentLoc();

      await SettingService.saveClinicLocation(
        lat: loc.lat,
        lng: loc.lng,
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

  // ============================================================
  // ✅ SAVE + SYNC BACKEND
  // ============================================================
  Future<void> _saveAndSync() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final token = await AuthStorage.getToken();

      if (token == null || token.trim().isEmpty) {
        throw "missing token (กรุณา login ใหม่)";
      }

      final loc = _currentLoc();

      // 1️⃣ Save local first
      await SettingService.saveClinicLocation(
        lat: loc.lat,
        lng: loc.lng,
      );

      // 2️⃣ Sync backend
      final res = await SettingService.syncClinicLocationToBackend(
        baseUrl: ApiConfig.payrollBaseUrl,
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

  // ============================================================
  // MAP EVENTS
  // ============================================================
  void _onTapMap(TapPosition _, LatLng latlng) {
    setState(() => _picked = latlng);
    HapticFeedback.selectionClick();
  }

  Future<void> _goToMySaved() async {
    try {
      final saved = await SettingService.loadClinicLocation();

      if (saved == null) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ยังไม่มีพิกัดที่บันทึกไว้")),
        );

        return;
      }

      final ll = LatLng(saved.lat, saved.lng);

      setState(() {
        _center = ll;
        _picked = ll;
      });

      try {
        _map.move(ll, 16);
      } catch (_) {}
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked ?? _center;

    return Scaffold(
      appBar: AppBar(
        title: const Text("ตั้งพิกัดคลินิก"),
        actions: [
          IconButton(
            tooltip: "ไปพิกัดที่บันทึกไว้",
            onPressed: _saving ? null : _goToMySaved,
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

                        // ✅✅✅ FIX 403
                        userAgentPackageName: _uaPackageName,

                        // ✅ (optional fallback)
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
                              onDragged: (newLatLng) {
                                setState(() => _picked = newLatLng);
                              },
                              getLatLng: () => _picked ?? _center,
                              map: _map,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("พิกัดที่เลือก"),
                      const SizedBox(height: 6),
                      Text(
                        "lat: ${picked.latitude.toStringAsFixed(6)}   "
                        "lng: ${picked.longitude.toStringAsFixed(6)}",
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _saveLocal,
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
                      const SizedBox(height: 8),
                      Text(
                        ApiConfig.debugPayroll,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
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

        final nextPx = Point<double>(
          px.x + delta.dx,
          px.y + delta.dy,
        );

        final nextLatLng = widget.map.camera.unproject(nextPx);

        widget.onDragged(nextLatLng);
      },
      onPanEnd: (_) {
        setState(() => _dragging = false);
        HapticFeedback.lightImpact();
      },
      child: AnimatedScale(
        scale: _dragging ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: const Icon(
          Icons.location_pin,
          size: 52,
          color: Colors.red,
        ),
      ),
    );
  }
}
