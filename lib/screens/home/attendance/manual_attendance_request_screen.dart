import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class ManualAttendanceRequestScreen extends StatefulWidget {
  final String role;
  final String clinicId;
  final String userId;
  final String staffId;

  /// ชื่อคลินิกสำหรับแสดงผล
  final String initialClinicName;

  /// ✅ NEW: ชื่อคลินิกของรายการค้างวันก่อน
  final String previousClinicName;

  /// yyyy-MM-dd
  final String initialWorkDate;

  /// check_in | check_out | edit_both | forgot_checkout
  final String initialManualRequestType;

  final String initialReasonCode;
  final String initialReasonText;
  final String initialMessage;

  /// helper shift-first flow
  final String initialShiftId;

  /// สำหรับ flow "มีรายการวันก่อนค้าง"
  final bool isFixingPreviousPending;
  final String previousSessionId;
  final String previousWorkDate;
  final String previousShiftId;

  const ManualAttendanceRequestScreen({
    super.key,
    required this.role,
    required this.clinicId,
    required this.userId,
    required this.staffId,
    this.initialClinicName = '',
    this.previousClinicName = '',
    required this.initialWorkDate,
    required this.initialManualRequestType,
    this.initialReasonCode = '',
    this.initialReasonText = '',
    this.initialMessage = '',
    this.initialShiftId = '',
    this.isFixingPreviousPending = false,
    this.previousSessionId = '',
    this.previousWorkDate = '',
    this.previousShiftId = '',
  });

  @override
  State<ManualAttendanceRequestScreen> createState() =>
      _ManualAttendanceRequestScreenState();
}

class _ManualAttendanceRequestScreenState
    extends State<ManualAttendanceRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _submitting = false;
  String _err = '';

  late String _workDate;
  late String _manualRequestType;

  final TextEditingController _reasonTextCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  TimeOfDay? _checkInTime;
  TimeOfDay? _checkOutTime;

  static const List<String> _types = [
    'check_in',
    'check_out',
    'edit_both',
    'forgot_checkout',
  ];

  static const Map<String, String> _typeLabels = {
    'check_in': 'เช็คอินย้อนหลัง / เช็คอินก่อนเวลา',
    'check_out': 'เช็คเอาท์ย้อนหลัง',
    'edit_both': 'แก้ทั้งเวลาเข้าและเวลาออก',
    'forgot_checkout': 'ลืมเช็คเอาท์',
  };

  static const Map<String, String> _reasonLabels = {
    'EARLY_CHECKIN': 'เช็คอินก่อนเวลา',
    'EARLY_CHECKOUT': 'เช็คเอาท์ก่อนเวลา',
    'FORGOT_CHECKOUT': 'ลืมเช็คเอาท์',
    'PREVIOUS_OPEN_SESSION': 'มีรายการวันก่อนค้าง',
    'MISS_SCAN': 'สแกนไม่สำเร็จ',
    'DEVICE_ISSUE': 'อุปกรณ์มีปัญหา',
    'OTHER': 'อื่น ๆ',
  };

  String _selectedReasonCode = 'OTHER';

  bool get _isHelper => widget.role.trim().toLowerCase() == 'helper';

  String get _effectiveShiftId {
    if (widget.previousShiftId.trim().isNotEmpty) {
      return widget.previousShiftId.trim();
    }
    return widget.initialShiftId.trim();
  }

  bool get _isFixingPreviousPending =>
      widget.isFixingPreviousPending ||
      widget.previousSessionId.trim().isNotEmpty ||
      widget.previousWorkDate.trim().isNotEmpty ||
      widget.previousShiftId.trim().isNotEmpty;

  String get _effectiveClinicDisplay {
    final previousClinicName = widget.previousClinicName.trim();
    if (_isFixingPreviousPending && previousClinicName.isNotEmpty) {
      return previousClinicName;
    }

    final clinicName = widget.initialClinicName.trim();
    if (clinicName.isNotEmpty) return clinicName;

    final clinicId = widget.clinicId.trim();
    if (clinicId.isEmpty) return '-';

    if (clinicId.length <= 24) return clinicId;
    return '${clinicId.substring(0, 10)}...${clinicId.substring(clinicId.length - 8)}';
  }

  @override
  void initState() {
    super.initState();

    _workDate = widget.previousWorkDate.trim().isNotEmpty
        ? widget.previousWorkDate.trim()
        : (widget.initialWorkDate.trim().isNotEmpty
            ? widget.initialWorkDate.trim()
            : _todayYmd());

    _manualRequestType = _normalizeType(widget.initialManualRequestType);

    if (_isFixingPreviousPending &&
        (widget.initialManualRequestType.trim().isEmpty ||
            widget.initialManualRequestType.trim() == 'check_in')) {
      _manualRequestType = 'forgot_checkout';
    }

    _selectedReasonCode = widget.initialReasonCode.trim().isNotEmpty &&
            _reasonLabels.containsKey(widget.initialReasonCode.trim())
        ? widget.initialReasonCode.trim()
        : (_isFixingPreviousPending
            ? 'PREVIOUS_OPEN_SESSION'
            : _defaultReasonByType(_manualRequestType));

    _reasonTextCtrl.text = widget.initialReasonText.trim();
    _noteCtrl.text = widget.initialMessage.trim();

    if (_isFixingPreviousPending && _noteCtrl.text.trim().isEmpty) {
      _noteCtrl.text =
          'กำลังส่งคำขอแก้ไขรายการค้างของวันก่อน เพื่อรอการอนุมัติก่อนเริ่มลงเวลาวันใหม่';
    }

    _prefillTimesByType();
  }

  @override
  void dispose() {
    _reasonTextCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _normalizeType(String raw) {
    final v = raw.trim();
    if (_types.contains(v)) return v;
    return 'check_in';
  }

  String _defaultReasonByType(String type) {
    switch (type) {
      case 'check_in':
        return 'EARLY_CHECKIN';
      case 'check_out':
        return 'EARLY_CHECKOUT';
      case 'forgot_checkout':
        return 'FORGOT_CHECKOUT';
      default:
        return 'OTHER';
    }
  }

  String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Uri _payrollUri(String path) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Future<String?> _getTokenAny() async {
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
    ];
    final prefs = await SharedPreferences.getInstance();
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  Map<String, String> _authHeaders(String token) => <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<http.Response> _tryPost(
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) async {
    return http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 20));
  }

  Map<String, dynamic> _decodeBodyMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _extractApiMessage(http.Response res) {
    final decoded = _decodeBodyMap(res.body);
    final msg = (decoded['message'] ??
            decoded['error'] ??
            decoded['msg'] ??
            decoded['detail'] ??
            '')
        .toString()
        .trim();
    return msg;
  }

  String _labelOfType(String type) {
    return _typeLabels[type] ?? type;
  }

  String _labelOfReason(String code) {
    return _reasonLabels[code] ?? code;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _prefillTimesByType() {
    final now = TimeOfDay.now();

    if (_manualRequestType == 'check_in') {
      _checkInTime ??= now;
    } else if (_manualRequestType == 'check_out' ||
        _manualRequestType == 'forgot_checkout') {
      _checkOutTime ??= now;
    } else if (_manualRequestType == 'edit_both') {
      _checkInTime ??= const TimeOfDay(hour: 8, minute: 0);
      _checkOutTime ??= const TimeOfDay(hour: 17, minute: 0);
    }
  }

  bool _needsCheckInTime() {
    return _manualRequestType == 'check_in' || _manualRequestType == 'edit_both';
  }

  bool _needsCheckOutTime() {
    return _manualRequestType == 'check_out' ||
        _manualRequestType == 'forgot_checkout' ||
        _manualRequestType == 'edit_both';
  }

  String _fmtTimeOfDay(TimeOfDay? t) {
    if (t == null) return '--:--';
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  DateTime _combineDateAndTime(String ymd, TimeOfDay tod) {
    final parts = ymd.split('-');
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return DateTime(y, m, d, tod.hour, tod.minute);
  }

  String _toIsoWithOffset(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');

    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final oh = offset.inHours.abs().toString().padLeft(2, '0');
    final om = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');

    return '$y-$m-$d'
        'T$hh:$mm:$ss'
        '$sign$oh:$om';
  }

  Future<void> _pickWorkDate() async {
    final initial = DateTime.tryParse(_workDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;

    final y = picked.year.toString().padLeft(4, '0');
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    setState(() {
      _workDate = '$y-$m-$d';
    });
  }

  Future<void> _pickCheckInTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkInTime ?? TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkInTime = picked;
    });
  }

  Future<void> _pickCheckOutTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkOutTime ?? TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkOutTime = picked;
    });
  }

  Map<String, dynamic> _buildPayload() {
    final body = <String, dynamic>{
      'workDate': _workDate,
      'manualRequestType': _manualRequestType,
      'reasonCode': _selectedReasonCode,
      'reasonText': _reasonTextCtrl.text.trim(),
      'note': _noteCtrl.text.trim(),
    };

    if (!_isHelper && widget.clinicId.trim().isNotEmpty) {
      body['clinicId'] = widget.clinicId.trim();
    }
    if (widget.staffId.trim().isNotEmpty) {
      body['staffId'] = widget.staffId.trim();
    }

    if (_effectiveShiftId.isNotEmpty) {
      body['shiftId'] = _effectiveShiftId;
    }

    if (_needsCheckInTime() && _checkInTime != null) {
      body['requestedCheckInAt'] =
          _toIsoWithOffset(_combineDateAndTime(_workDate, _checkInTime!));
    }

    if (_needsCheckOutTime() && _checkOutTime != null) {
      body['requestedCheckOutAt'] =
          _toIsoWithOffset(_combineDateAndTime(_workDate, _checkOutTime!));
    }

    return body;
  }

  String? _validateBeforeSubmit() {
    if (_workDate.trim().isEmpty) {
      return 'กรุณาเลือกวันที่';
    }

    if (_needsCheckInTime() && _checkInTime == null) {
      return 'กรุณาเลือกเวลาเช็คอิน';
    }

    if (_needsCheckOutTime() && _checkOutTime == null) {
      return 'กรุณาเลือกเวลาเช็คเอาท์';
    }

    if (_manualRequestType == 'edit_both' &&
        _checkInTime != null &&
        _checkOutTime != null) {
      final inDt = _combineDateAndTime(_workDate, _checkInTime!);
      final outDt = _combineDateAndTime(_workDate, _checkOutTime!);
      if (!outDt.isAfter(inDt)) {
        return 'เวลาเช็คเอาท์ต้องมากกว่าเวลาเช็คอิน';
      }
    }

    if (_selectedReasonCode.trim().isEmpty) {
      return 'กรุณาเลือกเหตุผล';
    }

    if (_reasonTextCtrl.text.trim().isEmpty && _noteCtrl.text.trim().isEmpty) {
      return 'กรุณาระบุรายละเอียดอย่างน้อย 1 ช่อง';
    }

    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    final localErr = _validateBeforeSubmit();
    if (localErr != null) {
      _snack(localErr);
      return;
    }

    final token = await _getTokenAny();
    if (token == null || token.isEmpty) {
      _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
      return;
    }

    setState(() {
      _submitting = true;
      _err = '';
    });

    final headers = _authHeaders(token);
    final body = jsonEncode(_buildPayload());

    final candidates = <String>[
      '/attendance/manual-request',
      '/api/attendance/manual-request',
    ];

    http.Response? lastRes;

    try {
      for (final p in candidates) {
        final uri = _payrollUri(p);
        final res = await _tryPost(uri, headers: headers, body: body);
        lastRes = res;

        if (res.statusCode == 200 || res.statusCode == 201) {
          final decoded = _decodeBodyMap(res.body);
          final updatedPrevious =
              decoded['updatedPreviousPendingRequest'] == true;

          if (!mounted) return;

          _snack(
            updatedPrevious
                ? 'อัปเดตรายการค้างของวันก่อนเรียบร้อยแล้ว กรุณารอการอนุมัติ'
                : 'ส่งคำขอสำเร็จ',
          );
          Navigator.pop(context, true);
          return;
        }

        if (res.statusCode == 404) continue;

        if (res.statusCode == 401) {
          setState(() {
            _err = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
          });
          return;
        }

        final apiMsg = _extractApiMessage(res);
        setState(() {
          _err = apiMsg.isNotEmpty ? apiMsg : 'ส่งคำขอไม่สำเร็จ กรุณาลองใหม่';
        });
        return;
      }

      setState(() {
        _err = (lastRes == null)
            ? 'เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่'
            : 'ส่งคำขอไม่สำเร็จ กรุณาลองใหม่';
      });
    } catch (_) {
      setState(() {
        _err = 'เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _timePickerTile({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.access_time),
      title: Text(title),
      subtitle: Text(value),
      trailing: const Icon(Icons.chevron_right),
      onTap: _submitting ? null : onTap,
    );
  }

  Widget _helperClinicCard() {
    if (!_isHelper) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'คลินิกที่อ้างอิง',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'คำขอนี้จะถูกส่งโดยอ้างอิงคลินิกของกะงานที่เลือกไว้ เพื่อให้อนุมัติได้ตรงรายการ',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.25)),
              ),
              child: Text(
                _effectiveClinicDisplay,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftInfoCard() {
    if (_effectiveShiftId.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'กะงานที่อ้างอิง',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isFixingPreviousPending
                  ? 'คำขอนี้จะใช้แก้รายการค้างของวันก่อน โดยอ้างอิงกะงานเดิมเพื่อให้ระบบอนุมัติได้ตรงรายการ'
                  : 'คำขอนี้จะถูกผูกกับกะที่เลือกไว้แล้ว เพื่อให้ระบบแก้เวลาได้ตรงกะงาน',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.25)),
              ),
              child: Text(
                'shiftId: $_effectiveShiftId',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previousPendingCard() {
    if (!_isFixingPreviousPending) return const SizedBox.shrink();

    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'กำลังแก้ไขรายการค้างของวันก่อน',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.orange.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'หลังส่งคำขอแล้ว ต้องรอให้คลินิกอนุมัติก่อน จึงจะสามารถเริ่มลงเวลาของวันใหม่ได้',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            if (widget.previousWorkDate.trim().isNotEmpty)
              Text('วันที่ค้าง: ${widget.previousWorkDate.trim()}'),
            if (_effectiveClinicDisplay.trim().isNotEmpty &&
                _effectiveClinicDisplay.trim() != '-')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('คลินิก: $_effectiveClinicDisplay'),
              ),
            if (widget.previousSessionId.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('sessionId: ${widget.previousSessionId.trim()}'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final intro = _isFixingPreviousPending
        ? 'คุณกำลังส่งคำขอแก้ไขรายการค้างของวันก่อน หลังส่งแล้วต้องรอคลินิกอนุมัติก่อน จึงจะเริ่มลงเวลาวันใหม่ได้'
        : (widget.initialMessage.trim().isNotEmpty
            ? widget.initialMessage.trim()
            : 'กรุณาระบุรายละเอียดคำขอให้ครบถ้วน เพื่อส่งให้คลินิกพิจารณาอนุมัติ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('คำขอแก้ไขเวลาแบบ Manual'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              if (_isFixingPreviousPending) ...[
                _previousPendingCard(),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'รายละเอียดคำขอ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        intro,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isHelper) ...[
                const SizedBox(height: 12),
                _helperClinicCard(),
              ],
              if (_effectiveShiftId.isNotEmpty) ...[
                const SizedBox(height: 12),
                _shiftInfoCard(),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('ประเภทคำขอ'),
                      DropdownButtonFormField<String>(
                        value: _manualRequestType,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'เลือกประเภทคำขอ',
                        ),
                        items: _types.map((t) {
                          return DropdownMenuItem<String>(
                            value: t,
                            child: Text(_labelOfType(t)),
                          );
                        }).toList(),
                        onChanged: _submitting
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() {
                                  _manualRequestType = v;
                                  _selectedReasonCode = _isFixingPreviousPending
                                      ? 'PREVIOUS_OPEN_SESSION'
                                      : _defaultReasonByType(_manualRequestType);
                                  _prefillTimesByType();
                                });
                              },
                      ),
                      const SizedBox(height: 14),
                      _sectionTitle('วันที่ทำงาน'),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_today),
                        title: const Text('วันที่'),
                        subtitle: Text(_workDate),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _submitting ? null : _pickWorkDate,
                      ),
                      if (_needsCheckInTime()) ...[
                        const Divider(height: 18),
                        _timePickerTile(
                          title: 'เวลาเช็คอินที่ต้องการแก้ไข',
                          value: _fmtTimeOfDay(_checkInTime),
                          onTap: _pickCheckInTime,
                        ),
                      ],
                      if (_needsCheckOutTime()) ...[
                        const Divider(height: 18),
                        _timePickerTile(
                          title: 'เวลาเช็คเอาท์ที่ต้องการแก้ไข',
                          value: _fmtTimeOfDay(_checkOutTime),
                          onTap: _pickCheckOutTime,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('เหตุผล'),
                      DropdownButtonFormField<String>(
                        value: _selectedReasonCode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'เลือกเหตุผล',
                        ),
                        items: _reasonLabels.keys.map((code) {
                          return DropdownMenuItem<String>(
                            value: code,
                            child: Text(_labelOfReason(code)),
                          );
                        }).toList(),
                        onChanged: _submitting
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() {
                                  _selectedReasonCode = v;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _reasonTextCtrl,
                        enabled: !_submitting,
                        decoration: const InputDecoration(
                          labelText: 'รายละเอียดเหตุผล',
                          hintText: 'เช่น ออกก่อนเวลาเพราะมีเหตุจำเป็น',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 2,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _noteCtrl,
                        enabled: !_submitting,
                        decoration: const InputDecoration(
                          labelText: 'หมายเหตุเพิ่มเติม',
                          hintText: 'ระบุรายละเอียดเพิ่มเติมถ้ามี',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 2,
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
              ),
              if (_err.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _err,
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_submitting ? 'กำลังส่งคำขอ...' : 'ส่งคำขอ'),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: const Text('ยกเลิก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}