import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class ClinicAttendanceSettingsScreen extends StatefulWidget {
  const ClinicAttendanceSettingsScreen({super.key});

  @override
  State<ClinicAttendanceSettingsScreen> createState() =>
      _ClinicAttendanceSettingsScreenState();
}

class _ClinicAttendanceSettingsScreenState
    extends State<ClinicAttendanceSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String _err = '';

  String shiftStart = "09:00";
  String shiftEnd = "18:00";

  String cutoffTime = "03:00";
  int minMinutesBeforeCheckout = 1;

  bool requireReasonForEarlyCheckIn = true;
  bool requireReasonForEarlyCheckOut = true;
  bool forgotCheckoutManualOnly = true;
  bool blockNewCheckInIfPreviousOpen = true;

  Map<String, dynamic> weeklySchedule = {};

  late final TextEditingController _minMinutesCtrl;

  static const _days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday'
  ];

  static const _dayLabels = {
    "monday": "จันทร์",
    "tuesday": "อังคาร",
    "wednesday": "พุธ",
    "thursday": "พฤหัส",
    "friday": "ศุกร์",
    "saturday": "เสาร์",
    "sunday": "อาทิตย์",
  };

  @override
  void initState() {
    super.initState();
    _minMinutesCtrl =
        TextEditingController(text: minMinutesBeforeCheckout.toString());
    _loadPolicy();
  }

  @override
  void dispose() {
    _minMinutesCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Uri _uri(String path) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse("$base$p");
  }

  Future<String?> _getToken() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.isNotEmpty && t != 'null') return t;
    } catch (_) {}

    const keys = [
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
      'accessToken',
      'access_token',
      'auth_token',
    ];

    final prefs = await SharedPreferences.getInstance();

    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }

    return null;
  }

  Map<String, String> _authHeaders(String token) => {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      };

  Map<String, dynamic> _decodeBodyMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {};
    } catch (_) {
      return {};
    }
  }

  String _extractApiMessage(http.Response res) {
    final m = _decodeBodyMap(res.body);
    return (m['message'] ?? m['error'] ?? '').toString();
  }

  String _hhmm(dynamic value, {String fallback = "09:00"}) {
    final s = (value ?? '').toString().trim();
    if (RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').hasMatch(s)) {
      return s;
    }
    return fallback;
  }

  int _intOr(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.floor();
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  Future<void> _loadPolicy() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _err = '';
    });

    try {
      final token = await _getToken();

      if (token == null || token.isEmpty) {
        throw Exception('no token');
      }

      final headers = _authHeaders(token);

      final res = await http.get(_uri("/clinic-policy/me"), headers: headers);

      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _err = _extractApiMessage(res);
        });
        return;
      }

      final root = _decodeBodyMap(res.body);
      final policy = root['policy'] ?? {};

      setState(() {
        shiftStart = _hhmm(policy['shiftStart'], fallback: shiftStart);
        shiftEnd = _hhmm(policy['shiftEnd'], fallback: shiftEnd);

        cutoffTime = _hhmm(policy['cutoffTime'], fallback: cutoffTime);

        minMinutesBeforeCheckout =
            _intOr(policy['minMinutesBeforeCheckout'], minMinutesBeforeCheckout);

        requireReasonForEarlyCheckIn =
            policy['requireReasonForEarlyCheckIn'] ?? true;

        requireReasonForEarlyCheckOut =
            policy['requireReasonForEarlyCheckOut'] ?? true;

        forgotCheckoutManualOnly =
            policy['forgotCheckoutManualOnly'] ?? true;

        blockNewCheckInIfPreviousOpen =
            policy['blockNewCheckInIfPreviousOpen'] ?? true;

        weeklySchedule = Map<String, dynamic>.from(
          policy['weeklySchedule'] ?? {},
        );

        _minMinutesCtrl.text = minMinutesBeforeCheckout.toString();

        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _err = 'โหลดนโยบาย attendance ไม่สำเร็จ';
      });
    }
  }

  Future<void> _savePolicy() async {
    FocusScope.of(context).unfocus();

    final parsedMin = int.tryParse(_minMinutesCtrl.text.trim()) ?? 1;

    setState(() {
      _saving = true;
      minMinutesBeforeCheckout = parsedMin;
    });

    try {
      final token = await _getToken();

      if (token == null) {
        throw Exception("no token");
      }

      final body = jsonEncode({
        "weeklySchedule": weeklySchedule,
        "cutoffTime": cutoffTime,
        "minMinutesBeforeCheckout": minMinutesBeforeCheckout,
        "requireReasonForEarlyCheckIn": requireReasonForEarlyCheckIn,
        "requireReasonForEarlyCheckOut": requireReasonForEarlyCheckOut,
        "forgotCheckoutManualOnly": forgotCheckoutManualOnly,
        "blockNewCheckInIfPreviousOpen": blockNewCheckInIfPreviousOpen,
      });

      final res = await http.patch(
        _uri("/clinic-policy/me"),
        headers: _authHeaders(token),
        body: body,
      );

      if (res.statusCode == 200) {
        _snack("บันทึกสำเร็จ");
      } else {
        _snack("บันทึกไม่สำเร็จ");
      }
    } catch (_) {
      _snack("เชื่อมต่อเซิร์ฟเวอร์ไม่สำเร็จ");
    }

    setState(() => _saving = false);
  }

  Future<void> _pickTime({
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) async {
    final parts = currentValue.split(":");

    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );

    if (picked == null) return;

    final h = picked.hour.toString().padLeft(2, "0");
    final m = picked.minute.toString().padLeft(2, "0");

    onChanged("$h:$m");
  }

  Widget _buildDayTile(String day) {
    final data = weeklySchedule[day] ??
        {
          "enabled": true,
          "start": shiftStart,
          "end": shiftEnd,
        };

    final enabled = data['enabled'] ?? true;
    final start = data['start'] ?? shiftStart;
    final end = data['end'] ?? shiftEnd;

    return Card(
      child: SwitchListTile(
        title: Text(_dayLabels[day]!),
        subtitle: enabled ? Text("$start - $end") : const Text("ปิด"),
        value: enabled,
        onChanged: (v) async {
          if (!v) {
            setState(() {
              weeklySchedule[day] = {
                "enabled": false,
                "start": start,
                "end": end,
              };
            });
            return;
          }

          final newStart = await _pickTimeDialog(start);
          if (newStart == null) return;

          final newEnd = await _pickTimeDialog(end);
          if (newEnd == null) return;

          setState(() {
            weeklySchedule[day] = {
              "enabled": true,
              "start": newStart,
              "end": newEnd,
            };
          });
        },
      ),
    );
  }

  Future<String?> _pickTimeDialog(String current) async {
    final parts = current.split(":");

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );

    if (picked == null) return null;

    return "${picked.hour.toString().padLeft(2, "0")}:${picked.minute.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("ตั้งค่าเวลาเข้า-ออกคลินิก"),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("ตั้งค่าเวลาเข้า-ออกคลินิก"),
        actions: [
          IconButton(
            onPressed: _loadPolicy,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "วันเปิดทำการของคลินิก",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),

          ..._days.map(_buildDayTile),

          const SizedBox(height: 20),

          const Text(
            "กติกา Attendance",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),

          ListTile(
            title: const Text("ขั้นต่ำก่อน Checkout (นาที)"),
            trailing: SizedBox(
              width: 70,
              child: TextField(
                controller: _minMinutesCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
              ),
            ),
          ),

          const SizedBox(height: 30),

          ElevatedButton(
            onPressed: _saving ? null : _savePolicy,
            child: _saving
                ? const CircularProgressIndicator()
                : const Text("บันทึก"),
          )
        ],
      ),
    );
  }
}