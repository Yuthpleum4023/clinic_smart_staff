// lib/screens/clinic_shift_need_screen.dart
//
// ✅ FULL FILE (FIXED + SAME PATTERN WHOLE APP)
// - ✅ รองรับของเดิม: ยังรับ clinicId ผ่าน constructor ได้
// - ✅ IMPROVE UX: ไม่ต้องส่ง clinicId ก็ได้ -> resolve อัตโนมัติจาก prefs (app_clinic_id / clinicId / ...)
// - ✅ ไม่ตัด function ใด ๆ ออก (คงครบ) + เพิ่ม resolver/cache ให้เสถียร
// - ✅ FIX BASE URL: ใช้ ApiConfig.payrollBaseUrl ตรง ๆ (อย่าตัด /payroll ออกเอง)
// - ✅ show real API on UI เหมือนเดิม
// - ✅ FIX UI: ไม่ hardcode สีฟ้า -> ใช้ Theme สีม่วงทั้งระบบ
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';

/// ✅ endpoint สำหรับประกาศงานว่าง (ShiftNeed)
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
  final _expectedHoursCtrl = TextEditingController(); // UX only
  final _requiredCountCtrl = TextEditingController(text: '1');

  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;

  bool _loading = false;

  // ✅ show real API on UI
  String _apiBase = '';

  // ✅ clinicId resolved
  String _clinicId = '';
  bool _ctxLoaded = false;

  @override
  void initState() {
    super.initState();
    _start = const TimeOfDay(hour: 9, minute: 0);
    _end = const TimeOfDay(hour: 17, minute: 0);
    _recalcExpectedHours();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final base = await _NeedApi.getBaseUrl();
      if (mounted) setState(() => _apiBase = base);
      await _resolveClinicId();
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
      _snack('เวลาเริ่ม/เลิก ห้ามเท่ากัน');
      return false;
    }
    if (e < s) {
      _snack('หมายเหตุ: เลือกเวลาข้ามวัน');
    }
    return true;
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (!_ctxLoaded) {
      await _resolveClinicId();
    }

    final clinicId = _clinicId.trim();
    if (clinicId.isEmpty) {
      _snack('ไม่พบ clinicId (ลอง logout/login ใหม่ หรือเข้า MyClinic ก่อน)');
      return;
    }

    if (_date == null || _start == null || _end == null) {
      _snack('กรุณาเลือกวันและเวลา');
      return;
    }
    if (!_validateTime()) return;

    final hourlyRate = _toDouble(_hourlyRateCtrl.text);
    final requiredCount = _toInt(_requiredCountCtrl.text);
    if (hourlyRate <= 0 || requiredCount <= 0) {
      _snack('ข้อมูลไม่ถูกต้อง');
      return;
    }

    setState(() => _loading = true);
    try {
      final payload = {
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

      final res = await _NeedApi.createNeed(payload);
      final need = (res['need'] ?? res) as Map?;
      final id = need?['_id'] ?? need?['id'] ?? '';

      _snack('ประกาศงานสำเร็จ ${id.isNotEmpty ? '(id: $id)' : ''}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('ประกาศงานไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicId = _clinicId.trim();
    final api = _apiBase.trim().replaceAll(RegExp(r'\/+$'), '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('คลินิก: ต้องการผู้ช่วย'),
        // ✅ ไม่ hardcode สีฟ้า ให้ Theme คุม
        actions: [
          IconButton(
            tooltip: 'รีเฟรช clinicId',
            onPressed: () async {
              await _resolveClinicId();
              final base = await _NeedApi.getBaseUrl();
              if (mounted) setState(() => _apiBase = base);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                'API: ${api.isEmpty ? '(loading...)' : '$api$kCreateNeedPath'}',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 6),
              Text(
                'clinicId: ${clinicId.isEmpty ? '-' : clinicId}',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _titleCtrl,
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
                decoration: const InputDecoration(
                  labelText: 'ตำแหน่ง/บทบาท',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  );
                  if (d != null) setState(() => _date = d);
                },
                icon: const Icon(Icons.event),
                label: Text(_date == null ? 'เลือกวัน' : _fmtDate(_date!)),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _start!,
                        );
                        if (t != null) {
                          setState(() => _start = t);
                          _recalcExpectedHours();
                        }
                      },
                      child: Text(_start == null ? 'เริ่ม' : _fmtTime(_start!)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _end!,
                        );
                        if (t != null) {
                          setState(() => _end = t);
                          _recalcExpectedHours();
                        }
                      },
                      child: Text(_end == null ? 'เลิก' : _fmtTime(_end!)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _hourlyRateCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'เรท (บาท/ชม.)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _requiredCountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'จำนวนผู้ช่วย',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'หมายเหตุ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),

              // ✅ ปุ่มหลักให้ม่วงชัดตาม Theme (Material 3)
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
                  label: const Text('ประกาศงานว่าง'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// ✅ API helper (no hardcode baseUrl)
/// ============================================================
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
    // ✅ ใช้ ApiConfig.payrollBaseUrl ตรง ๆ
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
    if (token == null) throw Exception('no token (กรุณา login ก่อน)');
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

    final res = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode(payload),
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('createNeed failed: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'data': data};
  }
}
