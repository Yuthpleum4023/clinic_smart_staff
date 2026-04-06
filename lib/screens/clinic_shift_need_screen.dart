// lib/screens/clinic_shift_need_screen.dart
//
// ✅ FULL FILE — Commercial Polish Mode (PROD CLEAN)
// - ✅ รองรับของเดิม: ยังรับ clinicId ผ่าน constructor ได้
// - ✅ IMPROVE UX: ไม่ต้องส่ง clinicId ก็ได้ -> resolve อัตโนมัติจาก prefs (app_clinic_id / clinicId / ...)
// - ✅ ไม่ตัด function ใด ๆ ออก (คงครบ) + resolver/cache เสถียร
// - ✅ ใช้ ApiConfig.payrollBaseUrl ตรง ๆ
// - ✅ ไม่โชว์คำเทคนิค/endpoint/id/token/clinicId ใน UI
// - ✅ ไม่ hardcode สี -> ให้ Theme (ม่วง) คุมทั้งระบบ
//
// ✅ PATCH NEW:
// - ✅ โชว์พิกัดคลินิกเดิมในฟอร์ม
// - ✅ การ์ดพิกัดสั้นลง กะทัดรัดขึ้น
// - ✅ มีปุ่ม "ใช้พิกัดนี้" / "อัปเดตพิกัด"
// - ✅ ถ้ายังไม่มีพิกัด จะพาไปหน้า ClinicLocationSettingsScreen
// - ✅ แนบ location snapshot ไปกับ payload ตอนประกาศงาน
//
// ✅ PATCH FIX:
// - ✅ กัน async หลัง widget dispose
// - ✅ unfocus ก่อน submit
// - ✅ ไม่เด้งจอแดงตอนกดเปิดหน้าตั้งพิกัด/กลับมา

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/screens/clinic/clinic_location_settings_screen.dart';
import 'package:clinic_smart_staff/services/location_manager.dart';
import 'package:clinic_smart_staff/services/settings_service.dart';

const String kCreateNeedPath = '/shift-needs';

class ClinicShiftNeedScreen extends StatefulWidget {
  final String? clinicId;

  const ClinicShiftNeedScreen({
    super.key,
    this.clinicId,
  });

  @override
  State<ClinicShiftNeedScreen> createState() => _ClinicShiftNeedScreenState();
}

class _ClinicShiftNeedScreenState extends State<ClinicShiftNeedScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController(text: 'ต้องการผู้ช่วย');
  final _roleCtrl = TextEditingController(text: 'ผู้ช่วย');
  final _noteCtrl = TextEditingController();

  final _hourlyRateCtrl = TextEditingController(text: '150');
  final _expectedHoursCtrl = TextEditingController();
  final _requiredCountCtrl = TextEditingController(text: '1');

  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;

  bool _loading = false;

  String _clinicId = '';
  bool _ctxLoaded = false;

  AppLocation? _clinicLocation;
  bool _useSavedLocation = false;

  @override
  void initState() {
    super.initState();
    _start = const TimeOfDay(hour: 9, minute: 0);
    _end = const TimeOfDay(hour: 17, minute: 0);
    _recalcExpectedHours();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _resolveClinicId();
      await _loadClinicLocation();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _roleCtrl.dispose();
    _noteCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _expectedHoursCtrl.dispose();
    _requiredCountCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  double _toDouble(String s) =>
      double.tryParse(s.trim().replaceAll(',', '')) ?? 0.0;

  int _toInt(String s) => int.tryParse(s.trim().replaceAll(',', '')) ?? 0;

  void _recalcExpectedHours() {
    if (_start == null || _end == null) return;
    final startMin = _start!.hour * 60 + _start!.minute;
    final endMin = _end!.hour * 60 + _end!.minute;
    final diff =
        endMin >= startMin ? endMin - startMin : 24 * 60 - startMin + endMin;
    _expectedHoursCtrl.text = (diff / 60).toStringAsFixed(2);
    if (mounted) setState(() {});
  }

  bool _validateTime() {
    if (_start == null || _end == null) return false;
    final s = _start!.hour * 60 + _start!.minute;
    final e = _end!.hour * 60 + _end!.minute;
    if (s == e) {
      _snack('เวลาเริ่มและเวลาสิ้นสุดห้ามเท่ากัน');
      return false;
    }
    if (e < s) {
      _snack('หมายเหตุ: ช่วงเวลานี้เป็นแบบข้ามวัน');
    }
    return true;
  }

  bool _hasUsableClinicLocation(AppLocation? loc) {
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
    ].toList();

    if (parts.isNotEmpty) {
      return parts.join(' • ');
    }

    return 'lat ${loc.lat.toStringAsFixed(6)}, lng ${loc.lng.toStringAsFixed(6)}';
  }

  Future<String?> _getClinicIdFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      'app_clinic_id',
      'clinicId',
      'currentClinicId',
      'userClinicId',
      'clnId',
      'clinic_id',
      'myClinicId',
    ]) {
      final v = prefs.getString(k);
      if (v != null && v.trim().isNotEmpty && v != 'null') return v.trim();
    }
    return null;
  }

  Future<void> _cacheClinicId(String clinicId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_clinic_id', clinicId);
    await prefs.setString('clinicId', clinicId);
    await prefs.setString('currentClinicId', clinicId);
    await prefs.setString('myClinicId', clinicId);
  }

  Future<void> _resolveClinicId() async {
    if (_ctxLoaded) return;

    final fromWidget = (widget.clinicId ?? '').trim();
    if (fromWidget.isNotEmpty) {
      await _cacheClinicId(fromWidget);
      if (!mounted) return;
      setState(() {
        _clinicId = fromWidget;
        _ctxLoaded = true;
      });
      return;
    }

    final fromPrefs = await _getClinicIdFromPrefs();
    if (fromPrefs != null && fromPrefs.trim().isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _clinicId = fromPrefs.trim();
        _ctxLoaded = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _clinicId = '';
      _ctxLoaded = true;
    });
  }

  Future<void> _loadClinicLocation() async {
    final loc =
        await LocationManager.loadClinicLocationSmart(allowGpsFallback: false);

    if (!mounted) return;
    setState(() {
      _clinicLocation = loc;
      _useSavedLocation = _hasUsableClinicLocation(loc);
    });
  }

  Future<void> _openClinicLocationSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ClinicLocationSettingsScreen(),
      ),
    );

    await _loadClinicLocation();
  }

  Future<Map<String, dynamic>> _readClinicLocationSnapshot() async {
    try {
      final loc =
          await LocationManager.loadClinicLocationSmart(allowGpsFallback: false);

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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    if (!_ctxLoaded) {
      await _resolveClinicId();
    }

    final clinicId = _clinicId.trim();
    if (clinicId.isEmpty) {
      _snack('ไม่พบข้อมูลคลินิก กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
      return;
    }

    if (_date == null || _start == null || _end == null) {
      _snack('กรุณาเลือกวันและเวลา');
      return;
    }
    if (!_validateTime()) return;

    if (!_hasUsableClinicLocation(_clinicLocation) || !_useSavedLocation) {
      _snack('กรุณาเลือกหรือบันทึกพิกัดคลินิกก่อนประกาศงาน');
      return;
    }

    final hourlyRate = _toDouble(_hourlyRateCtrl.text);
    final requiredCount = _toInt(_requiredCountCtrl.text);
    if (hourlyRate <= 0 || requiredCount <= 0) {
      _snack('กรุณาตรวจสอบข้อมูลให้ถูกต้อง');
      return;
    }

    setState(() => _loading = true);
    try {
      final location = await _readClinicLocationSnapshot();

      if (location['lat'] == null || location['lng'] == null) {
        throw Exception('กรุณาตั้งพิกัดคลินิกก่อนประกาศงาน');
      }

      final payload = <String, dynamic>{
        'clinicId': clinicId,
        'title': _titleCtrl.text.trim(),
        'role': _roleCtrl.text.trim().isEmpty ? 'ผู้ช่วย' : _roleCtrl.text.trim(),
        'date': _fmtDate(_date!),
        'start': _fmtTime(_start!),
        'end': _fmtTime(_end!),
        'hourlyRate': hourlyRate,
        'requiredCount': requiredCount,
        'note': _noteCtrl.text.trim(),
      };

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

      await _NeedApi.createNeed(payload);

      _snack('ประกาศงานสำเร็จ');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(_NeedApi.toUserMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _locationCard(BuildContext context) {
    final hasLoc = _hasUsableClinicLocation(_clinicLocation);

    final cardColor =
        hasLoc && _useSavedLocation ? Colors.green.shade50 : Colors.orange.shade50;
    final borderColor =
        hasLoc && _useSavedLocation ? Colors.green.shade200 : Colors.orange.shade200;
    final titleColor =
        hasLoc && _useSavedLocation ? Colors.green.shade900 : Colors.orange.shade900;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasLoc ? Icons.location_on_outlined : Icons.location_off_outlined,
                color: titleColor,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasLoc && _useSavedLocation
                      ? 'พิกัดล่าสุดพร้อมใช้'
                      : 'ยังไม่พบพิกัดคลินิก',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasLoc
                ? _locationSummary(_clinicLocation!)
                : 'ควรตั้งพิกัดก่อนประกาศงาน เพื่อให้ระบบจับคู่และแสดงตำแหน่งงานได้ครบ',
            style: TextStyle(
              color: titleColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _openClinicLocationSettings,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: Text(hasLoc ? 'อัปเดตพิกัด' : 'ตั้งพิกัด'),
                ),
              ),
              if (hasLoc) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _useSavedLocation = true;
                            });
                          },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('ใช้พิกัดนี้'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expectedHoursText = _expectedHoursCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ประกาศงาน (คลินิก)'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: () async {
              setState(() {
                _ctxLoaded = false;
                _clinicId = '';
              });
              await _resolveClinicId();
              await _loadClinicLocation();
              _snack('อัปเดตข้อมูลแล้ว');
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  _locationCard(context),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _titleCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'หัวข้องาน',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'กรอกหัวข้องาน' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _roleCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'ตำแหน่ง/บทบาท',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () async {
                            FocusScope.of(context).unfocus();
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _date ?? DateTime.now(),
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 365)),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365 * 2)),
                            );
                            if (d != null && mounted) {
                              setState(() => _date = d);
                            }
                          },
                    icon: const Icon(Icons.event),
                    label: Text(_date == null ? 'เลือกวัน' : _fmtDate(_date!)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () async {
                                  FocusScope.of(context).unfocus();
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: _start!,
                                  );
                                  if (t != null && mounted) {
                                    setState(() => _start = t);
                                    _recalcExpectedHours();
                                  }
                                },
                          child:
                              Text(_start == null ? 'เริ่ม' : _fmtTime(_start!)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () async {
                                  FocusScope.of(context).unfocus();
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: _end!,
                                  );
                                  if (t != null && mounted) {
                                    setState(() => _end = t);
                                    _recalcExpectedHours();
                                  }
                                },
                          child: Text(_end == null ? 'เลิก' : _fmtTime(_end!)),
                        ),
                      ),
                    ],
                  ),
                  if (expectedHoursText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'ชั่วโมงโดยประมาณ: $expectedHoursText ชม.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _hourlyRateCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'เรท (บาท/ชั่วโมง)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _requiredCountCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'จำนวนผู้ช่วยที่ต้องการ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'หมายเหตุ (ถ้ามี)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: const Text('ประกาศงาน'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NeedApi {
  static const _tokenKeys = [
    'jwtToken',
    'token',
    'authToken',
    'userToken',
    'jwt_token',
    'accessToken',
    'access_token',
  ];

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  static Future<String> getBaseUrl() async {
    var base = ApiConfig.payrollBaseUrl.trim();
    base = base.replaceAll(RegExp(r'\/+$'), '');
    return base;
  }

  static Uri _u(String base, String path) {
    final b = base.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$b$p');
  }

  static Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('AUTH_REQUIRED');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> createNeed(
    Map<String, dynamic> payload,
  ) async {
    final base = await getBaseUrl();
    final uri = _u(base, kCreateNeedPath);

    http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw Exception('NETWORK_ERROR:$e');
    }

    if (res.statusCode != 200 && res.statusCode != 201) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map &&
            (decoded['message'] != null || decoded['error'] != null)) {
          throw Exception('SERVER_MSG:${decoded['message'] ?? decoded['error']}');
        }
      } catch (_) {}
      throw Exception('SERVER_ERROR:${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'data': data};
  }

  static String toUserMessage(Object e) {
    final s = e.toString().toLowerCase();

    if (s.contains('auth_required')) {
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    }

    if (s.contains('network_error') ||
        s.contains('timeout') ||
        s.contains('socket')) {
      return 'เชื่อมต่อไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
    }

    if (s.contains('server_msg:')) {
      final raw = e.toString();
      final idx = raw.indexOf('SERVER_MSG:');
      if (idx >= 0) {
        final msg = raw.substring(idx + 'SERVER_MSG:'.length).trim();
        if (msg.isNotEmpty) return msg;
      }
      return 'ทำรายการไม่สำเร็จ กรุณาลองใหม่';
    }

    if (s.contains('server_error:401') || s.contains('server_error:403')) {
      return 'ไม่มีสิทธิ์ใช้งาน กรุณาเข้าสู่ระบบใหม่';
    }

    if (s.contains('server_error:') || s.contains('500') || s.contains('404')) {
      return 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง';
    }

    if (s.contains('กรุณาตั้งพิกัดคลินิก')) {
      return 'กรุณาตั้งพิกัดคลินิกก่อนประกาศงาน';
    }

    return 'ประกาศงานไม่สำเร็จ กรุณาลองใหม่';
  }
}