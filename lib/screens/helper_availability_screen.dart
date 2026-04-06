// lib/screens/helper/helper_availability_screen.dart
//
// ✅ Helper Availability Screen (LIST -> DETAIL) — COMMERCIAL POLISH (PROD CLEAN)
// - โหลดตารางเวลาว่างของฉัน
// - แตะรายการ -> ไปหน้า HelperAvailabilityDetailScreen
// - มีสรุป + แท็บกรอง (ทั้งหมด/ว่าง/จองแล้ว/ยกเลิก)
// - ✅ ปุ่ม + "ประกาศเวลาว่าง" แล้ว refresh ทันที
// - RefreshIndicator + ปุ่ม refresh
//
// ✅ FIX:
// - ✅ กัน push ซ้อน (double tap / tap รัว) ด้วย lock
// - ✅ เหลือปุ่มเดียว “ดูรายละเอียด”
//
// ✅ PATCH NEW (STORE READY):
// - ✅ ตอนประกาศเวลาว่าง แนบ location snapshot จาก LocationManager ไป backend แบบชัวร์
// - ✅ แก้ป้าย/พื้นเหลืองที่บัง field ตอนพิมพ์ใน bottom sheet
// - ✅ ถ้าไม่มี location ในเครื่อง ยังประกาศได้ตามปกติ
//
// ✅ PATCH FIX:
// - ✅ แก้ bottom overflow ตอน keyboard ขึ้น
// - ✅ แก้จอแดงจาก async/picker หลัง widget ถูก dispose
// - ✅ unfocus ก่อนปิด bottom sheet
//
// ✅ PATCH NEW:
// - ✅ โชว์พิกัดเดิมในหน้าฟอร์มเลย
// - ✅ มีปุ่ม "ใช้พิกัดเดิม" / "อัปเดตพิกัดใหม่"
// - ✅ ถ้ายังไม่มี location เลย จะพาไปหน้า HelperLocationSettingsScreen ก่อนประกาศ
//
// ✅ ไม่เพิ่ม package ใหม่

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/models/availability_model.dart';
import 'package:clinic_smart_staff/screens/helper/helper_availability_detail_screen.dart';
import 'package:clinic_smart_staff/screens/helper/helper_location_settings_screen.dart';
import 'package:clinic_smart_staff/services/location_manager.dart';
import 'package:clinic_smart_staff/services/settings_service.dart';

class HelperAvailabilityScreen extends StatefulWidget {
  const HelperAvailabilityScreen({super.key});

  @override
  State<HelperAvailabilityScreen> createState() =>
      _HelperAvailabilityScreenState();
}

class _HelperAvailabilityScreenState extends State<HelperAvailabilityScreen> {
  bool _loading = true;

  List<Availability> _items = [];

  int _tab = 0; // 0=all,1=open,2=booked,3=cancelled

  bool _pushingDetail = false;

  Future<String?> _getToken() async {
    const keys = ['jwtToken', 'token', 'authToken', 'userToken', 'jwt_token'];
    final prefs = await SharedPreferences.getInstance();
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  Uri _u(String path) {
    final base =
        ApiConfig.payrollBaseUrl.trim().replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  bool _isBooked(Availability a) => a.status.trim().toLowerCase() == 'booked';
  bool _isCancelled(Availability a) =>
      a.status.trim().toLowerCase() == 'cancelled';
  bool _isOpen(Availability a) {
    final st = a.status.trim().toLowerCase();
    return st.isEmpty || st == 'open';
  }

  bool _hasUsableAppLocation(AppLocation? loc) {
    if (loc == null) return false;
    return loc.lat.isFinite &&
        loc.lng.isFinite &&
        !(loc.lat == 0 && loc.lng == 0);
  }

  String _locationSummary(AppLocation loc) {
    final parts = <String>[
      if (_s(loc.label).isNotEmpty) _s(loc.label),
      if (_s(loc.district).isNotEmpty) _s(loc.district),
      if (_s(loc.province).isNotEmpty) _s(loc.province),
    ].toSet().toList();

    if (parts.isNotEmpty) {
      return parts.join(' • ');
    }

    return 'lat: ${loc.lat.toStringAsFixed(6)}, lng: ${loc.lng.toStringAsFixed(6)}';
  }

  Future<AppLocation?> _loadHelperLocation() async {
    return LocationManager.loadHelperLocationSmart(allowGpsFallback: false);
  }

  Future<Map<String, dynamic>> _readLocationSnapshot() async {
    try {
      final loc = await _loadHelperLocation();

      if (loc == null) {
        return {
          'lat': null,
          'lng': null,
          'district': '',
          'province': '',
          'address': '',
          'locationLabel': '',
        };
      }

      return {
        'lat': loc.lat,
        'lng': loc.lng,
        'district': loc.district,
        'province': loc.province,
        'address': loc.address,
        'locationLabel': loc.label,
      };
    } catch (_) {
      return {
        'lat': null,
        'lng': null,
        'district': '',
        'province': '',
        'address': '',
        'locationLabel': '',
      };
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final token = await _getToken();
      if (token == null) throw Exception('กรุณาเข้าสู่ระบบใหม่');

      final res = await http.get(
        _u('/availabilities/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('โหลดข้อมูลไม่สำเร็จ โปรดลองใหม่');
      }

      final data = jsonDecode(res.body);

      final List list = (data is Map && data['items'] is List)
          ? (data['items'] as List)
          : (data is List)
              ? data
              : const [];

      final items = <Availability>[];
      for (final it in list) {
        if (it is Map) {
          items.add(Availability.fromJson(Map<String, dynamic>.from(it)));
        }
      }

      items.sort((a, b) {
        final c = b.date.compareTo(a.date);
        if (c != 0) return c;
        return b.start.compareTo(a.start);
      });

      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);

      final msg = e.toString();
      final friendly = (msg.contains('เข้าสู่ระบบ') || msg.contains('login'))
          ? 'กรุณาเข้าสู่ระบบใหม่'
          : 'โหลดตารางว่างไม่สำเร็จ โปรดลองใหม่';

      _snack(friendly);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Availability> get _filtered {
    if (_tab == 1) return _items.where(_isOpen).toList();
    if (_tab == 2) return _items.where(_isBooked).toList();
    if (_tab == 3) return _items.where(_isCancelled).toList();
    return _items;
  }

  int get _countAll => _items.length;
  int get _countOpen => _items.where(_isOpen).length;
  int get _countBooked => _items.where(_isBooked).length;
  int get _countCancelled => _items.where(_isCancelled).length;

  Color _statusColor(Availability a, ColorScheme cs) {
    if (_isBooked(a)) return Colors.green;
    if (_isCancelled(a)) return Colors.red;
    return cs.primary;
  }

  String _statusText(Availability a) {
    if (_isBooked(a)) return 'จองแล้ว';
    if (_isCancelled(a)) return 'ยกเลิก';
    return 'ว่าง';
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: color,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _openDetail(Availability a) async {
    if (_pushingDetail) return;
    _pushingDetail = true;
    try {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HelperAvailabilityDetailScreen(a: a),
        ),
      );
    } finally {
      _pushingDetail = false;
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmtTimeOfDay(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  int _timeToMin(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  InputDecoration _cleanInputDecoration({
    required String labelText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.purple.shade400, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _locationBanner({
    required BuildContext context,
    required AppLocation? location,
    required bool useSavedLocation,
    required VoidCallback onUseSaved,
    required VoidCallback onUpdateLocation,
  }) {
    final hasLoc = _hasUsableAppLocation(location);

    if (!hasLoc) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ยังไม่พบพิกัดที่บันทึกไว้',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'กรุณาตั้งพิกัดก่อนประกาศเวลาว่าง เพื่อให้คลินิกเห็นระยะทางจากตำแหน่งของคุณ',
              style: TextStyle(
                color: Colors.orange.shade900,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpdateLocation,
                icon: const Icon(Icons.place_outlined),
                label: const Text('ตั้งพิกัดตอนนี้'),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: useSavedLocation
            ? Colors.green.shade50
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: useSavedLocation
              ? Colors.green.shade200
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            useSavedLocation ? 'จะใช้พิกัดนี้ในการประกาศ' : 'พบพิกัดที่บันทึกไว้',
            style: TextStyle(
              color: useSavedLocation
                  ? Colors.green.shade900
                  : Colors.grey.shade900,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _locationSummary(location!),
            style: TextStyle(
              color: useSavedLocation
                  ? Colors.green.shade900
                  : Colors.grey.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onUpdateLocation,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('อัปเดตพิกัดใหม่'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onUseSaved,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('ใช้พิกัดเดิม'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _createAvailability() async {
    final cs = Theme.of(context).colorScheme;

    DateTime? pickedDate;
    TimeOfDay? pickedStart;
    TimeOfDay? pickedEnd;

    final roleCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    AppLocation? helperLocation = await _loadHelperLocation();
    bool useSavedLocation = _hasUsableAppLocation(helperLocation);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        Future<void> pickDate(StateSetter setD) async {
          FocusScope.of(ctx).unfocus();

          final now = DateTime.now();
          final d = await showDatePicker(
            context: ctx,
            initialDate: pickedDate ?? now,
            firstDate: DateTime(now.year - 1, 1, 1),
            lastDate: DateTime(now.year + 3, 12, 31),
          );

          if (!ctx.mounted) return;
          if (d == null) return;
          setD(() => pickedDate = d);
        }

        Future<void> pickStart(StateSetter setD) async {
          FocusScope.of(ctx).unfocus();

          final t = await showTimePicker(
            context: ctx,
            initialTime: pickedStart ?? const TimeOfDay(hour: 9, minute: 0),
          );

          if (!ctx.mounted) return;
          if (t == null) return;
          setD(() => pickedStart = t);
        }

        Future<void> pickEnd(StateSetter setD) async {
          FocusScope.of(ctx).unfocus();

          final t = await showTimePicker(
            context: ctx,
            initialTime: pickedEnd ?? const TimeOfDay(hour: 10, minute: 0),
          );

          if (!ctx.mounted) return;
          if (t == null) return;
          setD(() => pickedEnd = t);
        }

        Future<void> updateLocation(StateSetter setD) async {
          FocusScope.of(ctx).unfocus();

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const HelperLocationSettingsScreen(),
            ),
          );

          final reloaded = await _loadHelperLocation();
          if (!ctx.mounted) return;

          setD(() {
            helperLocation = reloaded;
            useSavedLocation = _hasUsableAppLocation(reloaded);
          });
        }

        return Theme(
          data: Theme.of(ctx).copyWith(
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: Colors.purple.shade400, width: 1.4),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
          child: StatefulBuilder(
            builder: (ctx, setD) {
              final dateText = pickedDate == null
                  ? 'เลือกวันที่'
                  : '${pickedDate!.year}-${_two(pickedDate!.month)}-${_two(pickedDate!.day)}';

              final startText = pickedStart == null
                  ? 'เวลาเริ่ม'
                  : _fmtTimeOfDay(pickedStart!);
              final endText =
                  pickedEnd == null ? 'เวลาจบ' : _fmtTimeOfDay(pickedEnd!);

              final bottom = MediaQuery.of(ctx).viewInsets.bottom;

              return AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: bottom),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ประกาศเวลาว่าง',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _locationBanner(
                          context: ctx,
                          location: helperLocation,
                          useSavedLocation: useSavedLocation,
                          onUseSaved: () {
                            setD(() {
                              useSavedLocation = true;
                            });
                          },
                          onUpdateLocation: () => updateLocation(setD),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => pickDate(setD),
                                icon: const Icon(Icons.calendar_month),
                                label: Text(dateText),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => pickStart(setD),
                                icon: const Icon(Icons.schedule),
                                label: Text(startText),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => pickEnd(setD),
                                icon: const Icon(Icons.schedule),
                                label: Text(endText),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: roleCtrl,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [],
                          decoration: _cleanInputDecoration(
                            labelText: 'ตำแหน่ง (ไม่บังคับ)',
                            hintText: 'เช่น ผู้ช่วย / Assistant',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: noteCtrl,
                          maxLines: 3,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [],
                          decoration: _cleanInputDecoration(
                            labelText: 'หมายเหตุ (ไม่บังคับ)',
                            hintText:
                                'เช่น ว่างเฉพาะงานใกล้บ้าน / ขอพักกลางวัน 1 ชม.',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  FocusScope.of(ctx).unfocus();
                                  Navigator.pop(ctx, false);
                                },
                                child: const Text('ยกเลิก'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  FocusScope.of(ctx).unfocus();

                                  if (!_hasUsableAppLocation(helperLocation) ||
                                      !useSavedLocation) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'กรุณาเลือกหรือบันทึกพิกัดก่อนประกาศเวลาว่าง',
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  if (pickedDate == null ||
                                      pickedStart == null ||
                                      pickedEnd == null) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text('กรุณาเลือกวันที่/เวลาให้ครบ'),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  final start = _fmtTimeOfDay(pickedStart!);
                                  final end = _fmtTimeOfDay(pickedEnd!);
                                  if (_timeToMin(end) <= _timeToMin(start)) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'เวลาจบต้องมากกว่าเวลาเริ่ม',
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  Navigator.pop(ctx, true);
                                },
                                icon: const Icon(Icons.check),
                                label: const Text('ประกาศ'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tip: หลังประกาศ คลินิกสามารถเห็นและจองเวลาว่างของคุณได้',
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (ok != true) {
      roleCtrl.dispose();
      noteCtrl.dispose();
      return;
    }

    try {
      final token = await _getToken();
      if (token == null) throw Exception('กรุณาเข้าสู่ระบบใหม่');

      final location = await _readLocationSnapshot();

      if (location['lat'] == null || location['lng'] == null) {
        throw Exception('กรุณาตั้งพิกัดก่อนประกาศเวลาว่าง');
      }

      final date =
          '${pickedDate!.year}-${_two(pickedDate!.month)}-${_two(pickedDate!.day)}';
      final start = _fmtTimeOfDay(pickedStart!);
      final end = _fmtTimeOfDay(pickedEnd!);

      final payload = <String, dynamic>{
        'date': date,
        'start': start,
        'end': end,
        'note': noteCtrl.text.trim(),
      };

      final role = roleCtrl.text.trim();
      if (role.isNotEmpty) {
        payload['role'] = role;
      }

      if (location['lat'] != null) payload['lat'] = location['lat'];
      if (location['lng'] != null) payload['lng'] = location['lng'];

      final district = _s(location['district']);
      final province = _s(location['province']);
      final address = _s(location['address']);
      final locationLabel = _s(location['locationLabel']);

      if (district.isNotEmpty) payload['district'] = district;
      if (province.isNotEmpty) payload['province'] = province;
      if (address.isNotEmpty) payload['address'] = address;
      if (locationLabel.isNotEmpty) payload['locationLabel'] = locationLabel;

      final resp = await http.post(
        _u('/availabilities'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String msg = 'ประกาศไม่สำเร็จ โปรดลองใหม่';
        try {
          final m = jsonDecode(resp.body);
          if (m is Map && (m['message'] != null || m['error'] != null)) {
            msg = (m['message'] ?? m['error']).toString().trim();
            if (msg.isEmpty) msg = 'ประกาศไม่สำเร็จ โปรดลองใหม่';
          }
        } catch (_) {}
        throw Exception(msg);
      }

      if (!mounted) return;

      _snack('✅ ประกาศเวลาว่างแล้ว พร้อมตำแหน่ง');

      setState(() => _tab = 0);
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().trim();
      _snack(msg.isEmpty ? 'ประกาศไม่สำเร็จ โปรดลองใหม่' : msg);
    } finally {
      roleCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _filtered;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('ตารางเวลาว่างของฉัน'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _createAvailability,
        icon: const Icon(Icons.add),
        label: const Text('ประกาศเวลาว่าง'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _chip('ทั้งหมด: $_countAll', cs.primary),
                    _chip('ว่าง: $_countOpen', cs.secondary),
                    _chip('จองแล้ว: $_countBooked', Colors.green),
                    _chip('ยกเลิก: $_countCancelled', Colors.red),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      _seg('ทั้งหมด', 0, cs),
                      _seg('ว่าง', 1, cs),
                      _seg('จองแล้ว', 2, cs),
                      _seg('ยกเลิก', 3, cs),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: items.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(child: Text('ยังไม่มีรายการ')),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final a = items[i];

                              final color = _statusColor(a, cs);
                              final dateLine =
                                  '${_s(a.date)}  ${_s(a.start)}-${_s(a.end)}';

                              final clinicName = _s(a.clinicName);
                              final clinicPhone = _s(a.clinicPhone);

                              final clinicPreview = () {
                                if (!_isBooked(a)) return '';
                                if (clinicName.isNotEmpty) return clinicName;
                                return 'คลินิก';
                              }();

                              return InkWell(
                                onTap: () => _openDetail(a),
                                borderRadius: BorderRadius.circular(16),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      12,
                                      14,
                                      12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                dateLine,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            _chip(_statusText(a), color),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 8,
                                          children: [
                                            if (_s(a.role).isNotEmpty)
                                              _chip(
                                                'ตำแหน่ง: ${_s(a.role)}',
                                                cs.primary,
                                              ),
                                            if (_s(a.shiftId).isNotEmpty)
                                              _chip(
                                                'สร้างงานแล้ว',
                                                Colors.green,
                                              ),
                                            if (a.bookedHourlyRate > 0)
                                              _chip(
                                                'เรท: ${a.bookedHourlyRate} บ./ชม.',
                                                cs.secondary,
                                              ),
                                          ],
                                        ),
                                        if (_isBooked(a)) ...[
                                          const SizedBox(height: 10),
                                          Text(
                                            'คลินิกที่จอง: $clinicPreview',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          if (clinicPhone.isNotEmpty)
                                            Text('โทร: $clinicPhone'),
                                        ],
                                        if (_s(a.note).isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            'หมายเหตุของฉัน: ${_s(a.note)}',
                                            style: TextStyle(
                                              color: cs.onSurface
                                                  .withOpacity(0.7),
                                            ),
                                          ),
                                        ],
                                        if (_s(a.bookedNote).isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'หมายเหตุจากคลินิก: ${_s(a.bookedNote)}',
                                            style: TextStyle(
                                              color: cs.onSurface
                                                  .withOpacity(0.7),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            onPressed: _pushingDetail
                                                ? null
                                                : () => _openDetail(a),
                                            icon: const Icon(
                                              Icons.chevron_right_rounded,
                                            ),
                                            label:
                                                const Text('ดูรายละเอียด'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _seg(String text, int idx, ColorScheme cs) {
    final active = _tab == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = idx),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? cs.primary.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: active ? cs.primary : cs.onSurface.withOpacity(0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}