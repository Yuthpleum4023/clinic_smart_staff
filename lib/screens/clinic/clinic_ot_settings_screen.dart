import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class ClinicOtSettingsScreen extends StatefulWidget {
  final String? clinicId;

  const ClinicOtSettingsScreen({
    super.key,
    this.clinicId,
  });

  @override
  State<ClinicOtSettingsScreen> createState() => _ClinicOtSettingsScreenState();
}

class _ClinicOtSettingsScreenState extends State<ClinicOtSettingsScreen> {
  bool _loading = true;
  String _error = '';

  // ===== POLICY FIELDS =====
  TimeOfDay? _otWindowStart;
  TimeOfDay? _otWindowEnd;

  double _otMultiplier = 1.5;
  double _holidayMultiplier = 2.0;

  bool _employeeOnlyOt = true;
  bool _requireOtApproval = true;
  bool _realTimeAttendanceOnly = true;
  bool _manualAttendanceRequireApproval = true;
  bool _manualReasonRequired = true;
  bool _lockAfterPayrollClose = true;

  List<String> _attendanceApprovalRoles = ['clinic_admin'];
  List<String> _otApprovalRoles = ['clinic_admin'];

  // feature flags
  bool _fingerprintAttendance = true;
  bool _manualAttendance = true;
  bool _autoOtCalculation = true;
  bool _otApprovalWorkflow = true;
  bool _attendanceApproval = true;
  bool _payrollLock = true;
  bool _policyHumanReadable = true;

  Uri _uri(String path) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Future<String?> _getToken() async {
    return await AuthStorage.getToken();
  }

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _fmt(TimeOfDay? t) {
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  TimeOfDay? _parseTime(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(
      hour: h.clamp(0, 23),
      minute: m.clamp(0, 59),
    );
  }

  double _parseDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    final x = double.tryParse('${v ?? ''}');
    if (x == null || x <= 0) return fallback;
    return x;
  }

  List<String> _parseRoleList(dynamic value, List<String> fallback) {
    if (value is List) {
      final list = value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      return list.isEmpty ? fallback : list;
    }
    if (value is String && value.trim().isNotEmpty) {
      return [value.trim()];
    }
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) {
        throw Exception('missing token');
      }

      http.Response res = await http.get(
        _uri('/clinic-policy/me'),
        headers: _headers(token),
      );

      if (res.statusCode == 404) {
        res = await http.get(
          _uri('/api/clinic-policy/me'),
          headers: _headers(token),
        );
      }

      if (res.statusCode != 200) {
        throw Exception('bad status ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      final rawPolicy = (decoded is Map && decoded['policy'] is Map)
          ? decoded['policy']
          : decoded;

      if (rawPolicy is! Map) {
        throw Exception('invalid policy');
      }

      final policy = Map<String, dynamic>.from(rawPolicy);
      final features = (policy['features'] is Map)
          ? Map<String, dynamic>.from(policy['features'])
          : <String, dynamic>{};

      _otWindowStart = _parseTime(policy['otWindowStart']);
      _otWindowEnd = _parseTime(policy['otWindowEnd']);

      _otMultiplier = _parseDouble(policy['otMultiplier'], 1.5);
      _holidayMultiplier = _parseDouble(policy['holidayMultiplier'], 2.0);

      _employeeOnlyOt = policy['employeeOnlyOt'] != false;
      _requireOtApproval = policy['requireOtApproval'] == true;
      _realTimeAttendanceOnly = policy['realTimeAttendanceOnly'] == true;
      _manualAttendanceRequireApproval =
          policy['manualAttendanceRequireApproval'] == true;
      _manualReasonRequired = policy['manualReasonRequired'] == true;
      _lockAfterPayrollClose = policy['lockAfterPayrollClose'] == true;

      _attendanceApprovalRoles = _parseRoleList(
        policy['attendanceApprovalRoles'],
        ['clinic_admin'],
      );
      _otApprovalRoles = _parseRoleList(
        policy['otApprovalRoles'],
        ['clinic_admin'],
      );

      _fingerprintAttendance = features['fingerprintAttendance'] != false;
      _manualAttendance = features['manualAttendance'] != false;
      _autoOtCalculation = features['autoOtCalculation'] != false;
      _otApprovalWorkflow = features['otApprovalWorkflow'] != false;
      _attendanceApproval = features['attendanceApproval'] != false;
      _payrollLock = features['payrollLock'] != false;
      _policyHumanReadable = features['policyHumanReadable'] != false;

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'ไม่สามารถโหลดข้อมูลได้';
      });
    }
  }

  Future<void> _savePolicy() async {
    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) {
        _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
        return;
      }

      if (_otWindowStart == null || _otWindowEnd == null) {
        _snack('กรุณาตั้งเวลาเริ่มและสิ้นสุด OT');
        return;
      }

      if (_otMultiplier <= 0 || _holidayMultiplier <= 0) {
        _snack('ตัวคูณ OT ต้องมากกว่า 0');
        return;
      }

      final body = jsonEncode({
        'otWindowStart': _fmt(_otWindowStart),
        'otWindowEnd': _fmt(_otWindowEnd),
        'otMultiplier': _otMultiplier,
        'holidayMultiplier': _holidayMultiplier,
        'employeeOnlyOt': _employeeOnlyOt,
        'requireOtApproval': _requireOtApproval,
        'realTimeAttendanceOnly': _realTimeAttendanceOnly,
        'manualAttendanceRequireApproval': _manualAttendanceRequireApproval,
        'manualReasonRequired': _manualReasonRequired,
        'lockAfterPayrollClose': _lockAfterPayrollClose,
        'attendanceApprovalRoles': _attendanceApprovalRoles,
        'otApprovalRoles': _otApprovalRoles,
        'features': {
          'fingerprintAttendance': _fingerprintAttendance,
          'manualAttendance': _manualAttendance,
          'autoOtCalculation': _autoOtCalculation,
          'otApprovalWorkflow': _otApprovalWorkflow,
          'attendanceApproval': _attendanceApproval,
          'payrollLock': _payrollLock,
          'policyHumanReadable': _policyHumanReadable,
        },
      });

      http.Response res = await http.put(
        _uri('/clinic-policy/me'),
        headers: _headers(token),
        body: body,
      );

      if (res.statusCode == 404) {
        res = await http.put(
          _uri('/api/clinic-policy/me'),
          headers: _headers(token),
          body: body,
        );
      }

      if (!mounted) return;

      if (res.statusCode == 200) {
        _snack('บันทึกสำเร็จ');
        await _loadPolicy();
      } else {
        throw Exception('save failed');
      }
    } catch (_) {
      if (!mounted) return;
      _snack('บันทึกไม่สำเร็จ');
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (_otWindowStart ?? const TimeOfDay(hour: 18, minute: 0))
          : (_otWindowEnd ?? const TimeOfDay(hour: 21, minute: 0)),
    );

    if (!mounted) return;

    if (picked != null) {
      setState(() {
        if (isStart) {
          _otWindowStart = picked;
        } else {
          _otWindowEnd = picked;
        }
      });
    }
  }

  Future<void> _editNormalMultiplier() async {
    final controller = TextEditingController(text: _otMultiplier.toString());

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ตั้งค่าตัวคูณ OT ปกติ'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: false),
          decoration: const InputDecoration(
            hintText: 'เช่น 1.5',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              ctx,
              double.tryParse(controller.text.trim()),
            ),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result != null && result > 0) {
      setState(() {
        _otMultiplier = result;
      });
    }
  }

  Future<void> _editHolidayMultiplier() async {
    final controller = TextEditingController(text: _holidayMultiplier.toString());

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ตั้งค่าตัวคูณ OT วันหยุด/พิเศษ'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: false),
          decoration: const InputDecoration(
            hintText: 'เช่น 2.0',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              ctx,
              double.tryParse(controller.text.trim()),
            ),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result != null && result > 0) {
      setState(() {
        _holidayMultiplier = result;
      });
    }
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  String _rolesText(List<String> roles) {
    if (roles.isEmpty) return '-';
    return roles.join(', ');
  }

  Widget _policyHintCard() {
    final startText = _otWindowStart?.format(context) ?? '--:--';
    final endText = _otWindowEnd?.format(context) ?? '--:--';

    return Card(
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ตัวอย่างกติกาที่พนักงานจะเห็น',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (_employeeOnlyOt)
              const Text('• OT ใช้กับพนักงานประจำเท่านั้น'),
            Text('• OT ปกติคิดเฉพาะช่วง $startText - $endText'),
            Text('• ตัวคูณ OT ปกติ ${_otMultiplier.toStringAsFixed(2)}x'),
            Text('• ตัวคูณ OT วันหยุด/พิเศษ ${_holidayMultiplier.toStringAsFixed(2)}x'),
            if (_requireOtApproval)
              const Text('• OT ต้องได้รับการอนุมัติก่อนจึงจะถูกนำไปคิดเงิน'),
            if (_realTimeAttendanceOnly)
              const Text('• การลงเวลาทำงานต้องทำแบบเรียลไทม์'),
            if (_manualAttendanceRequireApproval)
              const Text('• หากลืมลงเวลา ต้องส่งคำขอแก้ไขเวลาและรอผู้ดูแลอนุมัติ'),
            if (_manualReasonRequired)
              const Text('• การแก้ไขเวลาทำงานต้องระบุเหตุผล'),
            if (_lockAfterPayrollClose)
              const Text('• เมื่อปิดงวดเงินเดือนแล้ว จะไม่สามารถแก้ไขเวลาย้อนหลังได้'),
          ],
        ),
      ),
    );
  }

  Widget _roleInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ผู้มีสิทธิ์อนุมัติ',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text('อนุมัติ Attendance: ${_rolesText(_attendanceApprovalRoles)}'),
            const SizedBox(height: 4),
            Text('อนุมัติ OT: ${_rolesText(_otApprovalRoles)}'),
            const SizedBox(height: 8),
            Text(
              'ตอนนี้หน้าแอปนี้แสดงผล role ที่ backend กำหนดไว้ก่อน หากภายหลังท่านต้องการให้แก้ role ได้จาก UI เดี๋ยวค่อยเพิ่มได้',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: null,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('ตั้งค่า OT')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loadPolicy,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองใหม่'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่า OT'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _savePolicy,
            tooltip: 'บันทึก',
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('ช่วงเวลา OT'),
          const SizedBox(height: 10),
          ListTile(
            title: const Text('เวลาเริ่มคิด OT'),
            subtitle: Text(_otWindowStart?.format(context) ?? 'ยังไม่ได้ตั้งค่า'),
            trailing: const Icon(Icons.access_time),
            onTap: () => _pickTime(true),
          ),
          ListTile(
            title: const Text('เวลาสิ้นสุด OT'),
            subtitle: Text(_otWindowEnd?.format(context) ?? 'ยังไม่ได้ตั้งค่า'),
            trailing: const Icon(Icons.access_time),
            onTap: () => _pickTime(false),
          ),
          const Divider(height: 32),

          _sectionTitle('การคำนวณและการอนุมัติ'),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('ตัวคูณ OT ปกติ'),
            subtitle: Text('${_otMultiplier.toStringAsFixed(2)}x'),
            trailing: const Icon(Icons.edit),
            onTap: _editNormalMultiplier,
          ),
          ListTile(
            title: const Text('ตัวคูณ OT วันหยุด/พิเศษ'),
            subtitle: Text('${_holidayMultiplier.toStringAsFixed(2)}x'),
            trailing: const Icon(Icons.edit),
            onTap: _editHolidayMultiplier,
          ),
          SwitchListTile(
            title: const Text('ใช้ OT กับพนักงานประจำเท่านั้น'),
            subtitle: const Text('Helper จะใช้ค่าจ้างตามชั่วโมงจริง ไม่เข้า OT employee'),
            value: _employeeOnlyOt,
            onChanged: (v) => setState(() => _employeeOnlyOt = v),
          ),
          SwitchListTile(
            title: const Text('OT ต้องได้รับการอนุมัติก่อน'),
            subtitle: const Text('หากเปิดไว้ ระบบจะรวม OT เข้า payroll หลังอนุมัติเท่านั้น'),
            value: _requireOtApproval,
            onChanged: (v) => setState(() => _requireOtApproval = v),
          ),
          const Divider(height: 32),

          _sectionTitle('กติกาการลงเวลา'),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('ลงเวลาแบบเรียลไทม์เท่านั้น'),
            subtitle: const Text('พนักงานต้องลงเวลา ณ เวลาที่ทำงานจริง'),
            value: _realTimeAttendanceOnly,
            onChanged: (v) => setState(() => _realTimeAttendanceOnly = v),
          ),
          SwitchListTile(
            title: const Text('การแก้ไขเวลาต้องได้รับการอนุมัติ'),
            subtitle: const Text('หากลืมลงเวลา ต้องส่งคำขอและรอผู้ดูแลอนุมัติ'),
            value: _manualAttendanceRequireApproval,
            onChanged: (v) => setState(() => _manualAttendanceRequireApproval = v),
          ),
          SwitchListTile(
            title: const Text('บังคับกรอกเหตุผลเมื่อแก้ไขเวลา'),
            subtitle: const Text('ช่วยให้ตรวจสอบย้อนหลังได้ง่าย'),
            value: _manualReasonRequired,
            onChanged: (v) => setState(() => _manualReasonRequired = v),
          ),
          SwitchListTile(
            title: const Text('ล็อกหลังปิดงวด payroll'),
            subtitle: const Text('เมื่อปิดงวดเงินเดือนแล้ว จะไม่สามารถแก้ไขเวลาย้อนหลังได้'),
            value: _lockAfterPayrollClose,
            onChanged: (v) => setState(() => _lockAfterPayrollClose = v),
          ),
          const Divider(height: 32),

          _sectionTitle('Feature Flags'),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('เปิดใช้ Attendance แบบลายนิ้วมือ'),
            value: _fingerprintAttendance,
            onChanged: (v) => setState(() => _fingerprintAttendance = v),
          ),
          SwitchListTile(
            title: const Text('เปิดใช้ Manual Attendance'),
            value: _manualAttendance,
            onChanged: (v) => setState(() => _manualAttendance = v),
          ),
          SwitchListTile(
            title: const Text('คำนวณ OT อัตโนมัติ'),
            value: _autoOtCalculation,
            onChanged: (v) => setState(() => _autoOtCalculation = v),
          ),
          SwitchListTile(
            title: const Text('เปิดใช้ OT Approval Workflow'),
            value: _otApprovalWorkflow,
            onChanged: (v) => setState(() => _otApprovalWorkflow = v),
          ),
          SwitchListTile(
            title: const Text('เปิดใช้ Attendance Approval'),
            value: _attendanceApproval,
            onChanged: (v) => setState(() => _attendanceApproval = v),
          ),
          SwitchListTile(
            title: const Text('เปิดใช้ Payroll Lock'),
            value: _payrollLock,
            onChanged: (v) => setState(() => _payrollLock = v),
          ),
          SwitchListTile(
            title: const Text('แสดงกติกาเป็นภาษาคนให้พนักงาน'),
            value: _policyHumanReadable,
            onChanged: (v) => setState(() => _policyHumanReadable = v),
          ),
          const SizedBox(height: 12),

          _roleInfoCard(),
          const SizedBox(height: 12),

          _policyHintCard(),
          const SizedBox(height: 12),

          Text(
            'หมายเหตุ: หน้านี้อ่าน/บันทึกนโยบายผ่าน /clinic-policy/me โดยอ้างอิง clinicId จาก token',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
